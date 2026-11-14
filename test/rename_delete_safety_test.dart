import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late VaultController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_rds');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    File('${tmp.path}/A.md').writeAsStringSync('# A\n\ntext');
    File('${tmp.path}/B.md').writeAsStringSync('# B\n\nsee [[A]]');
    Directory('${tmp.path}/Work').createSync();
    File('${tmp.path}/Work/One.md').writeAsStringSync('# One');
    File('${tmp.path}/Work/Two.md').writeAsStringSync('# Two');
    controller = VaultController(
      passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
    );
    await controller.openVault(tmp.path);
  });

  tearDown(() async {
    controller.dispose();
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

  test('a rename whose follow-up work fails still points at the new file',
      () async {
    final a = controller.notes.firstWhere((n) => n.title == 'A');
    controller.select(a);
    await controller.togglePin('A');
    // Make rewriting the [[A]] link in B fail: a folder sits where B.md was.
    File('${tmp.path}/B.md').deleteSync();
    Directory('${tmp.path}/B.md').createSync();

    try {
      await controller.renameNote(a, 'Renamed');
    } on Exception {
      // The failure may surface or be queued for retry; either is fine.
    }

    expect(File('${tmp.path}/Renamed.md').existsSync(), isTrue);
    expect(File('${tmp.path}/A.md').existsSync(), isFalse);
    expect(controller.current?.path, endsWith('Renamed.md'));
    expect(controller.openTabs.map((n) => n.title), contains('Renamed'));
    expect(controller.isPinned('Renamed'), isTrue);

    // The next edit goes to the renamed file; the old one is not re-created.
    Directory('${tmp.path}/B.md').deleteSync();
    controller.editCurrentBody('# Renamed\n\nmore');
    await controller.flushPendingSave();
    expect(File('${tmp.path}/A.md').existsSync(), isFalse);
    expect(
      File('${tmp.path}/Renamed.md').readAsStringSync(),
      '# Renamed\n\nmore',
    );
  });

  test('a project delete that fails leaves the list matching the disk, '
      'and a second try finishes it', () async {
    // Block the archive: a plain file sits where the _archive folder goes.
    final blocker = File('${tmp.path}/_archive')..writeAsStringSync('x');

    await expectLater(
      controller.deleteProject('Work'),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.projects, contains('Work'));
    expect(
      controller.notes.map((n) => n.title),
      containsAll(['One', 'Two']),
    );
    expect(File('${tmp.path}/Work/One.md').existsSync(), isTrue);

    blocker.deleteSync();
    await controller.deleteProject('Work');
    expect(controller.projects, isNot(contains('Work')));
    expect(Directory('${tmp.path}/Work').existsSync(), isFalse);
    final archived = (await controller.loadArchived()).map((n) => n.title);
    expect(archived.toList()..sort(), ['One', 'Two']);
  });

  test('a damaged settings file keeps the launch password', () async {
    final f = File('${tmp.path}/settings.json');
    final store = PasswordStore(file: f);
    await store.setPassword('secret');
    // Cut the file short, as a crash mid-write would.
    final text = f.readAsStringSync();
    f.writeAsStringSync(text.substring(0, text.length - 1));

    expect(await store.verify('secret'), isTrue);
    expect(await store.verify('wrong'), isFalse);
    expect(File('${f.path}.corrupt').existsSync(), isTrue);

    // Remembering a vault rewrites the file — with the password still in it.
    AppSettings.overrideFile = f;
    await AppSettings.setLastVault(r'C:\some\vault');
    expect(await AppSettings.lastVault(), r'C:\some\vault');
    expect(await PasswordStore(file: f).verify('secret'), isTrue);
  });
}
