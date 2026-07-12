import 'dart:io';

import 'package:blobnot/models/note.dart';
import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/pinned_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/services/vault_storage.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_m3');
    AppSettings.overrideFile = File('${tmp.path}/app_settings.json');
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

  VaultController newController() => VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );

  group('PinnedStore', () {
    test('round-trips pinned titles as a JSON array', () async {
      await PinnedStore(tmp.path).save({'B', 'A'});
      expect(await PinnedStore(tmp.path).load(), {'A', 'B'});
      expect(
        File('${tmp.path}/pinned.json').readAsStringSync(),
        '["A","B"]',
      );
    });
  });

  group('Archive', () {
    test('archive moves note to _archive; restore brings it back', () async {
      File('${tmp.path}/Keep.md').writeAsStringSync('# Keep');
      File('${tmp.path}/Gone.md').writeAsStringSync('# Gone');
      final controller = newController();
      await controller.openVault(tmp.path);

      final gone = controller.notes.firstWhere((n) => n.title == 'Gone');
      await controller.archiveNote(gone);

      expect(controller.notes.map((n) => n.title), ['Keep']);
      expect(File('${tmp.path}/_archive/Gone.md').existsSync(), isTrue);

      final archived = await controller.loadArchived();
      expect(archived.map((n) => n.title), ['Gone']);

      await controller.restoreArchived(archived.first);
      expect(
        controller.notes.map((n) => n.title).toSet(),
        {'Keep', 'Gone'},
      );
      expect(File('${tmp.path}/_archive/Gone.md').existsSync(), isFalse);

      controller.dispose();
    });

    test('archived notes are not loaded by loadNotes', () async {
      Directory('${tmp.path}/_archive').createSync();
      File('${tmp.path}/_archive/Old.md').writeAsStringSync('# Old');
      File('${tmp.path}/New.md').writeAsStringSync('# New');

      final notes = await VaultStorage(tmp.path).loadNotes();
      expect(notes.map((n) => n.title), ['New']);
    });
  });

  group('Backlinks', () {
    test('finds notes linking to a title', () async {
      File('${tmp.path}/A.md').writeAsStringSync('links [[B]]');
      File('${tmp.path}/B.md').writeAsStringSync('plain');
      File('${tmp.path}/C.md').writeAsStringSync('also [[B]] and [[A]]');
      final controller = newController();
      await controller.openVault(tmp.path);

      expect(
        controller.backlinksTo('B').map((n) => n.title).toSet(),
        {'A', 'C'},
      );
      expect(controller.backlinksTo('A').map((n) => n.title), ['C']);

      controller.dispose();
    });
  });

  group('Pin via controller', () {
    test('togglePin persists to pinned.json', () async {
      File('${tmp.path}/A.md').writeAsStringSync('# A');
      final controller = newController();
      await controller.openVault(tmp.path);

      await controller.togglePin('A');
      expect(controller.isPinned('A'), isTrue);
      expect(await PinnedStore(tmp.path).load(), {'A'});

      await controller.togglePin('A');
      expect(controller.isPinned('A'), isFalse);

      controller.dispose();
    });
  });

  group('Note model', () {
    test('titleFromPath strips extension', () {
      expect(Note.titleFromPath('C:\\v\\Hello.md'), 'Hello');
    });
  });
}
