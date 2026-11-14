import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:blobnot/ui/note_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;
  late VaultController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_columns');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    File('${tmp.path}/Plan.md').writeAsStringSync(
      '# Plan\n\n- [ ] Call the **supplier** about [[Prices|prices]] #work',
    );
    Directory('${tmp.path}/Work').createSync();
    File('${tmp.path}/Work/Prices.md').writeAsStringSync(
      '---\nstatus: draft\n---\n# Prices\n\nModules 12 V, new list #work',
    );
    File('${tmp.path}/Work/Staff.md').writeAsStringSync('# Staff\n\nTeam');
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

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider(create: (_) => ExternalFilesController()),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();
  }

  Finder inNotesColumn(String text) => find.descendant(
    of: find.byKey(const Key('notes-column')),
    matching: find.text(text),
  );
  Finder inFolders(String text) => find.descendant(
    of: find.byKey(const Key('folders-pane')),
    matching: find.text(text),
  );

  test('three columns is the default layout', () {
    expect(const VaultSettings().layout, 'columns');
    expect(VaultSettings.fromJson(const {}).layout, 'columns');
    expect(VaultSettings.fromJson(const {'layout': 'classic'}).layout,
        'classic');
  });

  test('first line skips front matter, the title and Markdown marks', () {
    final plan = controller.notes.firstWhere((n) => n.title == 'Plan');
    final prices = controller.notes.firstWhere((n) => n.title == 'Prices');
    expect(firstLineOf(plan), 'Call the supplier about prices #work');
    expect(firstLineOf(prices), 'Modules 12 V, new list #work');
  });

  testWidgets('folders, tags and the notes column work together', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1400, 900));

    // Left: the views, the folder with its count, the tag.
    expect(inFolders('All notes'), findsOneWidget);
    expect(inFolders('Work'), findsOneWidget);
    expect(inFolders('work'), findsOneWidget);
    expect(inFolders('No folder'), findsOneWidget);
    // No rail, no tab strip in this layout.
    expect(find.byKey(const Key('rail')), findsNothing);

    // Middle: every note, each with its first line.
    expect(
      tester
          .widget<Text>(find.byKey(const Key('notes-column-title')))
          .data,
      'All notes',
    );
    expect(inNotesColumn('Plan'), findsOneWidget);
    expect(inNotesColumn('Staff'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('notes-column')),
        matching: find.textContaining('Modules 12 V'),
      ),
      findsOneWidget,
    );

    // Pick the folder: only its notes.
    await tester.tap(inFolders('Work'));
    await tester.pump();
    expect(inNotesColumn('Prices'), findsOneWidget);
    expect(inNotesColumn('Staff'), findsOneWidget);
    expect(inNotesColumn('Plan'), findsNothing);

    // Pick the tag: notes carrying it, across folders.
    await tester.tap(inFolders('work'));
    await tester.pump();
    expect(inNotesColumn('Plan'), findsOneWidget);
    expect(inNotesColumn('Prices'), findsOneWidget);
    expect(inNotesColumn('Staff'), findsNothing);

    // Opening a note puts it in the editor.
    await tester.tap(inNotesColumn('Prices'));
    await tester.pump();
    expect(controller.current?.title, 'Prices');

    // Table from the left column, then back to the notes.
    await tester.tap(inFolders('Table'));
    await tester.pump();
    expect(find.byKey(const Key('note-table')), findsOneWidget);
    await tester.tap(inFolders('All notes'));
    await tester.pump();
    expect(find.byKey(const Key('notes-column')), findsOneWidget);
  });

  testWidgets('a narrow window falls back to the classic layout', (
    tester,
  ) async {
    await pumpApp(tester, const Size(900, 700));
    expect(find.byKey(const Key('folders-pane')), findsNothing);
    expect(find.byKey(const Key('rail')), findsOneWidget);
  });

  testWidgets('choosing Classic in the settings switches the layout', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1400, 900));
    await tester.runAsync(() => controller.setTheme(layout: 'classic'));
    await tester.pump();
    expect(find.byKey(const Key('rail')), findsOneWidget);
    expect(find.byKey(const Key('folders-pane')), findsNothing);
  });
}
