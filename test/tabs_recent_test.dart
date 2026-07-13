import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late VaultController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_tabs');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    File('${tmp.path}/A.md').writeAsStringSync('# A');
    File('${tmp.path}/B.md').writeAsStringSync('# B\n[[A]]');
    Directory('${tmp.path}/_templates').createSync();
    File('${tmp.path}/_templates/Meeting.md')
        .writeAsStringSync('# Meeting\n\n## Agenda\n- ');
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

  test('selecting notes builds tabs and recents', () async {
    final a = controller.notes.firstWhere((n) => n.title == 'A');
    final b = controller.notes.firstWhere((n) => n.title == 'B');

    controller.select(b);
    controller.select(a);

    expect(controller.openTabs.map((n) => n.title), containsAll(['A', 'B']));
    // Most-recent first.
    expect(controller.recentNotes.first.title, 'A');

    controller.closeTab(a.path);
    expect(controller.openTabs.map((n) => n.title), isNot(contains('A')));
    expect(controller.current?.title, 'B');
  });

  test('templates are discovered and excluded from notes', () async {
    // _templates dir must not leak into the notes list.
    expect(controller.notes.map((n) => n.title), isNot(contains('Meeting')));
    final templates = await controller.loadTemplates();
    expect(templates.map((n) => n.title), ['Meeting']);
  });

  test('createNote from template body creates a note with that content',
      () async {
    final note = await controller.createNote('Standup', body: '# Standup\n\n## Agenda\n- ');
    expect(note.body, contains('## Agenda'));
    expect(controller.openTabs, contains(note));
  });
}
