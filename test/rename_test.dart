import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/note_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;
  late VaultController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_rename');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    File('${tmp.path}/Plan.md').writeAsStringSync('# Plan\n\nbody');
    File('${tmp.path}/Other.md').writeAsStringSync('# Other');
    Directory('${tmp.path}/Work').createSync();
    File('${tmp.path}/Work/Task.md').writeAsStringSync('# Task');
    controller = VaultController(
      passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
    );
    await controller.openVault(tmp.path);
  });

  tearDown(() async {
    await controller.reload();
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

  group('createNote', () {
    test('never overwrites a note with the same title', () async {
      final note = await controller.createNote('plan');

      expect(note.title, 'plan (1)');
      expect(File('${tmp.path}/Plan.md').readAsStringSync(), contains('body'));
    });

    test('strips characters a file name cannot hold', () async {
      final note = await controller.createNote('a/b: c?');
      expect(note.title, 'a-b- c-');
    });
  });

  group('renameNote', () {
    test('renames the file, its heading and keeps the pin', () async {
      final plan = controller.notes.firstWhere((n) => n.title == 'Plan');
      await controller.togglePin('Plan');

      final renamed = await controller.renameNote(plan, 'Roadmap');

      expect(renamed?.title, 'Roadmap');
      expect(File('${tmp.path}/Plan.md').existsSync(), isFalse);
      final text = File('${tmp.path}/Roadmap.md').readAsStringSync();
      expect(text, startsWith('# Roadmap'));
      expect(text, contains('body'));
      expect(controller.isPinned('Roadmap'), isTrue);
      expect(controller.isPinned('Plan'), isFalse);
    });

    test('a taken title gets a suffix instead of replacing the note', () async {
      final plan = controller.notes.firstWhere((n) => n.title == 'Plan');

      final renamed = await controller.renameNote(plan, 'Other');

      expect(renamed?.title, 'Other (1)');
      expect(File('${tmp.path}/Other.md').readAsStringSync(), '# Other');
    });

    test('empty or unchanged names do nothing', () async {
      final plan = controller.notes.firstWhere((n) => n.title == 'Plan');
      expect(await controller.renameNote(plan, '   '), isNull);
      expect(await controller.renameNote(plan, 'Plan'), isNull);
    });
  });

  group('renameProject', () {
    test('moves the folder with its notes and colour', () async {
      await controller.setProjectColor('Work', 2);

      final ok = await controller.renameProject('Work', 'Clients');

      expect(ok, isTrue);
      expect(controller.projects, contains('Clients'));
      expect(controller.projects, isNot(contains('Work')));
      expect(controller.colorOf('Clients'), 2);
      final task = controller.notes.firstWhere((n) => n.title == 'Task');
      expect(controller.projectOf(task), 'Clients');
    });

    test('refuses a name another project already has', () async {
      await controller.createProject('Home');

      expect(await controller.renameProject('Work', 'home'), isFalse);
      expect(Directory('${tmp.path}/Work').existsSync(), isTrue);
    });
  });

  testWidgets('note list shows a small date stamp and renames inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: NoteList(onNew: () {}, onNewInProject: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('note-stamp-Plan')), findsOneWidget);

    final tile = find.ancestor(
      of: find.text('Plan'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byIcon(Icons.more_horiz)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('rename-note-field'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Roadmap');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('Roadmap'), findsOneWidget);
    expect(File('${tmp.path}/Roadmap.md').existsSync(), isTrue);
  });
}
