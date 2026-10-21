import 'dart:io';

import 'package:blobnot/models/note.dart';
import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/note_list.dart';
import 'package:blobnot/ui/open_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;
  late VaultController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_open_tabs');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    controller = VaultController(
      passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
    );
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

  Future<void> seed(WidgetTester tester, int count) => tester.runAsync(() async {
    for (var i = 1; i <= count; i++) {
      File('${tmp.path}/Note number $i.md').writeAsStringSync('# $i');
    }
    await controller.openVault(tmp.path);
  });

  Widget host(Widget child, {double width = 500}) => ChangeNotifierProvider.value(
    value: controller,
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: 600, child: child),
        ),
      ),
    ),
  );

  testWidgets('many tabs: overflow button lists them all and jumps to one', (
    tester,
  ) async {
    await seed(tester, 14);
    for (final n in controller.notes) {
      controller.select(n);
    }
    await tester.pumpWidget(host(const OpenTabs()));
    await tester.pumpAndSettle();

    // 14 tabs cannot fit in 500px, so the "all open notes" button appears.
    final menu = find.byTooltip('All open notes (14)');
    expect(menu, findsOneWidget);

    // Pick the first tab in the list: it becomes the current note.
    final first = controller.openTabs.first;
    await tester.tap(menu);
    await tester.pumpAndSettle();
    // Menu items follow tab order, so the first one is `first`.
    await tester.tap(find.byType(CheckedPopupMenuItem<Note>).first);
    await tester.pumpAndSettle();
    expect(controller.current?.path, first.path);
  });

  testWidgets('few tabs: no overflow button', (tester) async {
    await seed(tester, 3);
    for (final n in controller.notes) {
      controller.select(n);
    }
    await tester.pumpWidget(host(const OpenTabs(), width: 900));
    await tester.pumpAndSettle();
    expect(find.byTooltip('All open notes (3)'), findsNothing);
  });

  testWidgets('mouse wheel scrolls the tab row sideways', (tester) async {
    await seed(tester, 14);
    for (final n in controller.notes) {
      controller.select(n);
    }
    await tester.pumpWidget(host(const OpenTabs()));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(OpenTabs),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(OpenTabs))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('Recent lists only notes that are not open as tabs', (
    tester,
  ) async {
    await seed(tester, 4);
    final notes = controller.notes.toList();
    // Visit all four, then close two tabs: those two are "recent, not open".
    for (final n in notes) {
      controller.select(n);
    }
    controller.closeTab(notes[0].path);
    controller.closeTab(notes[1].path);

    await tester.pumpWidget(
      host(NoteList(onNew: () {}, onNewInProject: (_) {}), width: 300),
    );
    await tester.pumpAndSettle();

    expect(find.text('RECENT'), findsOneWidget);
    expect(
      find.widgetWithText(ActionChip, notes[0].title),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ActionChip, notes[1].title),
      findsOneWidget,
    );
    // Still-open notes get no chip.
    expect(find.widgetWithText(ActionChip, notes[3].title), findsNothing);
  });
}
