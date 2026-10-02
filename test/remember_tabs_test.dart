import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/models/note.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_tabs_mem');
    AppSettings.overrideFile = File('${tmp.path}/app/settings.json');
    Directory('${tmp.path}/vault').createSync();
    for (final t in ['A', 'B', 'C']) {
      File('${tmp.path}/vault/$t.md').writeAsStringSync('# $t\n');
    }
  });

  tearDown(() async {
    AppSettings.overrideFile = null;
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; the temp dir is cleaned up later.
    }
  });

  Future<VaultController> open() async {
    final c = VaultController(
      passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
    );
    await c.openVault('${tmp.path}/vault');
    return c;
  }

  test('the next start reopens the same tabs and note', () async {
    final first = await open();
    Note? byTitle(String t) => first.notes.firstWhere((n) => n.title == t);
    first.select(byTitle('B')!);
    first.select(byTitle('C')!);
    first.select(byTitle('B')!);
    // Saving is fire-and-forget; give it a moment.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    first.dispose();

    final second = await open();
    expect(second.openTabs.map((n) => n.title), ['A', 'B', 'C']);
    expect(second.current?.title, 'B');
    second.dispose();
  });

  test('tabs for notes deleted since are dropped', () async {
    final first = await open();
    first.select(first.notes.firstWhere((n) => n.title == 'C'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    first.dispose();
    File('${tmp.path}/vault/C.md').deleteSync();

    final second = await open();
    expect(second.openTabs.map((n) => n.title), ['A']);
    expect(second.current?.title, 'A');
    second.dispose();
  });
}
