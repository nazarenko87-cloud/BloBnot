import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/services/vault_storage.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late VaultController c;

  File fileOf(String name) => File('${tmp.path}/$name');

  /// Simulates an edit from another device: new text, a later mtime.
  void editElsewhere(String name, String body) {
    final f = fileOf(name)..writeAsStringSync(body);
    f.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_save');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    fileOf('A.md').writeAsStringSync('# A');
    fileOf('B.md').writeAsStringSync('# B');
    c = VaultController(
      passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
    );
    await c.openVault(tmp.path);
  });

  tearDown(() async {
    await c.flushPendingSave();
    c.dispose();
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

  test('switching notes during a pending save stays on the new note', () async {
    final a = c.notes.firstWhere((n) => n.title == 'A');
    final b = c.notes.firstWhere((n) => n.title == 'B');
    c.select(a);
    c.editCurrentBody('# A edited');
    c.select(b);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(c.current?.title, 'B');
    expect(fileOf('A.md').readAsStringSync(), '# A edited');
  });

  test('text typed while a write is in flight is kept and saved', () async {
    c.select(c.notes.firstWhere((n) => n.title == 'A'));
    c.editCurrentBody('one');
    final first = c.flushPendingSave();
    c.editCurrentBody('one two');
    await first;

    expect(c.current?.body, 'one two');
    expect(c.isDirty, isTrue);
    await c.flushPendingSave();
    expect(fileOf('A.md').readAsStringSync(), 'one two');
  });

  test('a failed write keeps the edit unsaved and reports it', () async {
    c.select(c.notes.firstWhere((n) => n.title == 'A'));
    // A folder where the note's file should be: every write fails.
    fileOf('A.md').deleteSync();
    Directory('${tmp.path}/A.md').createSync();
    c.editCurrentBody('precious');
    await c.flushPendingSave();

    expect(c.isDirty, isTrue);
    expect(c.saveError, isNotNull);

    Directory('${tmp.path}/A.md').deleteSync();
    await c.flushPendingSave();
    expect(c.isDirty, isFalse);
    expect(c.saveError, isNull);
    expect(fileOf('A.md').readAsStringSync(), 'precious');
  });

  test('an edit made on another device is kept as a conflict copy', () async {
    c.select(c.notes.firstWhere((n) => n.title == 'A'));
    editElsewhere('A.md', 'from the other PC');
    c.editCurrentBody('from this PC');
    await c.flushPendingSave();

    expect(fileOf('A.md').readAsStringSync(), 'from this PC');
    final copies = c.notes.where((n) => n.title.startsWith('A (conflict'));
    expect(copies, hasLength(1));
    expect(copies.single.body, 'from the other PC');
    expect(c.conflictNotice, contains(copies.single.title));
  });

  test('our own saves never look like a conflict', () async {
    c.select(c.notes.firstWhere((n) => n.title == 'A'));
    c.editCurrentBody('first');
    await c.flushPendingSave();
    c.editCurrentBody('second');
    await c.flushPendingSave();

    expect(c.notes.where((n) => n.title.contains('conflict')), isEmpty);
    expect(c.conflictNotice, isNull);
  });

  test('opening a note picks up a newer copy from disk', () async {
    editElsewhere('B.md', '# B from the other PC');
    final before = c.reloadCount;
    c.select(c.notes.firstWhere((n) => n.title == 'B'));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(c.current?.body, '# B from the other PC');
    expect(c.reloadCount, greaterThan(before));
  });

  test('writes replace the file whole and leave no temp files', () async {
    final storage = VaultStorage(tmp.path);
    final a = c.notes.firstWhere((n) => n.title == 'A');
    await storage.write(a.copyWith(body: 'x' * 10000));
    await storage.write(a.copyWith(body: 'short'));
    await storage.writeText('_hot/tasks.md', '# Hot tasks\n');
    await storage.writeText('_hot/tasks.md', '# Hot tasks\n- [ ] a\n');

    expect(fileOf('A.md').readAsStringSync(), 'short');
    expect(fileOf('_hot/tasks.md').readAsStringSync(), contains('- [ ] a'));
    final leftovers = tmp
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.tmp'));
    expect(leftovers, isEmpty);
  });
}
