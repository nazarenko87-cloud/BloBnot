import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/pinned_store.dart';
import 'package:blobnot/services/reminder_store.dart';
import 'package:blobnot/services/safe_file.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A file that exists but cannot be read — what a sync client's lock looks
/// like to the app. Anything else called on it fails the test loudly.
class _LockedFile implements File {
  _LockedFile(this.path);

  @override
  final String path;

  int writes = 0;

  @override
  File get absolute => this;

  @override
  Future<bool> exists() async => true;

  @override
  Future<Uint8List> readAsBytes() async =>
      throw FileSystemException('locked', path);

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writes++;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName} on a locked file');
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_safe');
  });

  tearDown(() async {
    AppSettings.overrideFile = null;
    for (var i = 0; i < 10; i++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  group('readJsonFile', () {
    test('missing file is null, not an error', () async {
      expect(await readJsonFile(File('${tmp.path}/none.json')), isNull);
    });

    test('a locked file throws instead of looking empty', () async {
      expect(
        readJsonFile(_LockedFile('${tmp.path}/x.json')),
        throwsA(isA<UnreadableFileException>()),
      );
    });

    test('a corrupt file is kept as .corrupt before it reads as empty',
        () async {
      final f = File('${tmp.path}/reminders.json')
        ..writeAsStringSync('{"a": "2026-01-01T10:00:00", ');
      expect(await ReminderStore(tmp.path).load(), isEmpty);
      expect(
        File('${f.path}.corrupt').readAsStringSync(),
        '{"a": "2026-01-01T10:00:00", ',
      );
    });

    test('valid JSON of the wrong shape reads as empty, without throwing',
        () async {
      File('${tmp.path}/pinned.json').writeAsStringSync('{"not": "a list"}');
      File('${tmp.path}/reminders.json').writeAsStringSync('[1, 2]');
      File('${tmp.path}/settings.json').writeAsStringSync('{"accentIndex":"x"}');
      expect(await PinnedStore(tmp.path).load(), isEmpty);
      expect(await ReminderStore(tmp.path).load(), isEmpty);
      expect((await SettingsStore(tmp.path).load()).accentIndex, 0);
    });
  });

  group('writeFileAtomic', () {
    test('replaces the file and leaves no .tmp behind', () async {
      final f = File('${tmp.path}/note.md')..writeAsStringSync('old');
      await writeFileAtomic(f, 'new text');
      expect(f.readAsStringSync(), 'new text');
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    });

    test('writes fired together land in order', () async {
      final f = File('${tmp.path}/settings.json');
      final writes = [for (var i = 0; i < 25; i++) writeFileAtomic(f, 'v$i')];
      await Future.wait(writes);
      expect(f.readAsStringSync(), 'v24');
    });
  });

  group('the settings file that holds the launch password', () {
    test('a locked file keeps the app locked and is not overwritten',
        () async {
      final locked = _LockedFile('${tmp.path}/settings.json');
      AppSettings.overrideFile = locked;
      final controller = VaultController(
        passwordStore: PasswordStore(file: locked),
      );
      await controller.refreshLock();
      expect(controller.locked, isTrue);
      expect(controller.unlock('anything'), isFalse);

      // Remembering the vault must not write over what could not be read.
      await AppSettings.setLastVault(tmp.path);
      expect(locked.writes, 0);
      controller.dispose();
    });

    test('remembering the same vault again does not rewrite the file',
        () async {
      final f = File('${tmp.path}/settings.json');
      AppSettings.overrideFile = f;
      await PasswordStore(file: f).setPassword('secret');
      await AppSettings.setLastVault(tmp.path);
      final stamp = f.lastModifiedSync();
      final before = f.readAsStringSync();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await AppSettings.setLastVault(tmp.path);
      expect(f.readAsStringSync(), before);
      expect(f.lastModifiedSync(), stamp);
      expect(await PasswordStore(file: f).verify('secret'), isTrue);
    });
  });

  group('vault', () {
    late VaultController controller;

    setUp(() async {
      AppSettings.overrideFile = File('${tmp.path}/app.json');
      File('${tmp.path}/A.md').writeAsStringSync('# A');
      File('${tmp.path}/B.md').writeAsStringSync('# B');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);
    });

    tearDown(() => controller.dispose());

    test('typing while a refresh is reading the disk is kept', () async {
      controller.select(controller.notes.firstWhere((n) => n.title == 'A'));
      final refresh = controller.reload();
      controller.editCurrentBody('# A\ntyped during refresh');
      await refresh;
      expect(controller.current?.body, '# A\ntyped during refresh');
      await controller.flushPendingSave();
      expect(
        File('${tmp.path}/A.md').readAsStringSync(),
        '# A\ntyped during refresh',
      );
    });

    test('a burst of typing notifies listeners twice, not per key', () async {
      controller.select(controller.notes.firstWhere((n) => n.title == 'A'));
      var notified = 0;
      controller.addListener(() => notified++);
      for (var i = 0; i < 10; i++) {
        controller.editCurrentBody('# A\n${'x' * i}');
      }
      expect(notified, 1, reason: 'the save indicator flips at once');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(notified, 2, reason: 'one catch-up for the rest of the UI');
      expect(controller.current?.body, '# A\n${'x' * 9}');
      await controller.flushPendingSave();
    });

    test('opening a vault reads its metadata and leaves the file alone',
        () async {
      final other = Directory('${tmp.path}/other')..createSync();
      File('${other.path}/N.md').writeAsStringSync('# N');
      final reminders = File('${other.path}/reminders.json')
        ..writeAsStringSync('{"N": "2030-01-01T10:00:00.000"}');
      await controller.openVault(other.path);
      expect(controller.openError, isNull);
      expect(controller.reminders.keys, ['N']);
      expect(reminders.readAsStringSync(), contains('2030-01-01'));
    });
  });
}
