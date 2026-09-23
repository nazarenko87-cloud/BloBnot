import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late VaultController controller;

  Future<void> pumpApp(
    WidgetTester tester, {
    Map<String, String> extra = const {},
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_table');
      AppSettings.overrideFile = File('${dir.path}/app.json');
      for (final e in extra.entries) {
        File('${dir.path}/${e.key}').writeAsStringSync(e.value);
      }
      File('${dir.path}/Report Oleg.md').writeAsStringSync(
        '---\nmanager: Oleg\nstatus: needs fixes\nscore: 3\n---\n# Report\n',
      );
      File('${dir.path}/Report Ivan.md').writeAsStringSync(
        '---\nmanager: Ivan\nstatus: ok\nscore: 5\n---\n# Report\n',
      );
      File('${dir.path}/Plain.md').writeAsStringSync('# Plain note\n');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${dir.path}/pw.json')),
      );
      await controller.openVault(dir.path);
    });
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
    await tester.tap(find.byTooltip('Table — notes by their fields'));
    await tester.pumpAndSettle();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      AppSettings.overrideFile = null;
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold a handle.
      }
    });
  }

  String countText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('table-count'))).data!;

  testWidgets('lists notes with fields as rows, fields as columns', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('note-table')), findsOneWidget);
    expect(countText(tester), startsWith('2 notes'));
    for (final header in ['Note', 'manager', 'status', 'score', 'Project']) {
      expect(find.text(header), findsWidgets, reason: header);
    }
    expect(find.text('needs fixes'), findsOneWidget);
    expect(find.text('Plain'), findsNothing);

    // Showing every note brings the one without fields in.
    await tester.tap(find.byKey(const Key('table-only-fields')));
    await tester.pumpAndSettle();
    expect(countText(tester), startsWith('3 notes'));
    await cleanUp(tester);
  });

  testWidgets('columns follow the visible rows', (tester) async {
    await pumpApp(
      tester,
      extra: {'Strip 24V.md': '---\nproduct: LED strip\nprice: 120\n---\n'},
    );
    expect(find.text('price'), findsOneWidget);
    expect(find.text('manager'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('table-search')), 'strip');
    await tester.pumpAndSettle();
    expect(find.text('price'), findsOneWidget);
    expect(
      find.text('manager'),
      findsNothing,
      reason: 'no visible row uses it',
    );
    await cleanUp(tester);
  });

  testWidgets('search narrows the rows', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('table-search')), 'ivan');
    await tester.pumpAndSettle();
    expect(countText(tester), startsWith('1 note'));
    expect(find.text('Report Ivan'), findsOneWidget);
    expect(find.text('Report Oleg'), findsNothing);
    await cleanUp(tester);
  });

  testWidgets('clicking a cell edits the value and writes it to the note', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('needs fixes'));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('cell-Report Oleg-status'));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'fixed');
    // Real file I/O only completes outside the test's fake clock, so the
    // action that starts the write runs in runAsync as well.
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
    expect(find.text('fixed'), findsOneWidget);
    final onDisk = await tester.runAsync(
      () => File('${dir.path}/Report Oleg.md').readAsString(),
    );
    expect(onDisk, contains('status: fixed'));
    expect(onDisk, contains('# Report'));
    await cleanUp(tester);
  });

  testWidgets('right-click a value to filter by it, chip removes the filter', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Oleg'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show only manager = Oleg'));
    await tester.pumpAndSettle();
    expect(countText(tester), startsWith('1 note'));
    expect(find.byType(InputChip), findsOneWidget);

    await tester.tap(
      find
          .descendant(of: find.byType(InputChip), matching: find.byType(Icon))
          .last,
    );
    await tester.pumpAndSettle();
    expect(countText(tester), startsWith('2 notes'));
    await cleanUp(tester);
  });

  testWidgets('sorting a numeric column orders by value', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('score'));
    await tester.pumpAndSettle();
    final oleg = tester.getTopLeft(find.text('Report Oleg')).dy;
    final ivan = tester.getTopLeft(find.text('Report Ivan')).dy;
    expect(oleg, lessThan(ivan), reason: 'ascending: 3 before 5');

    await tester.tap(find.text('score'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Report Ivan')).dy,
      lessThan(tester.getTopLeft(find.text('Report Oleg')).dy),
    );
    await cleanUp(tester);
  });

  testWidgets('the note title opens the note in the editor', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Report Ivan'));
    await tester.pumpAndSettle();
    expect(controller.current?.title, 'Report Ivan');
    expect(find.byKey(const Key('note-table')), findsNothing);
    await cleanUp(tester);
  });
}
