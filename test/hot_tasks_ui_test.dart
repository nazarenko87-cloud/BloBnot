import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:blobnot/ui/hot_tasks_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late VaultController controller;

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_hot_ui');
      AppSettings.overrideFile = File('${dir.path}/app.json');
      File('${dir.path}/Note.md').writeAsStringSync('# Note\n');
      Directory('${dir.path}/_hot').createSync();
      File(
        '${dir.path}/_hot/tasks.md',
      ).writeAsStringSync('# Hot tasks\n\n- [ ] Call the supplier\n');
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
        // Windows may still hold a handle; the temp dir is cleaned up later.
      }
    });
  }

  testWidgets('desktop: rail flame opens the view, add, complete, reopen', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1280, 800));

    // The badge on the flame shows the one open task.
    expect(
      find.descendant(of: find.byType(HotBadge), matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('rail-hot')));
    await tester.pump();
    expect(find.text('Hot tasks'), findsWidgets);
    expect(find.text('Call the supplier'), findsOneWidget);

    // Without hover the delete button is hidden and cannot be hit.
    expect(find.byTooltip('Delete task').hitTestable(), findsNothing);

    // Enter adds to the top of In progress.
    await tester.enterText(find.byKey(const Key('hot-input')), 'Order profile');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.hotInProgress.map((t) => t.text), [
      'Order profile',
      'Call the supplier',
    ]);
    expect(find.byKey(const Key('hot-count-In progress')), findsOneWidget);

    // Tap completes after the strike-through animation.
    await tester.tap(find.text('Call the supplier'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.hotDone, isEmpty, reason: 'still animating');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(controller.hotDone.single.text, 'Call the supplier');
    expect(find.text('Today'), findsOneWidget);

    // Tap a done task: back to in progress.
    await tester.tap(find.text('Call the supplier'));
    await tester.pump(const Duration(milliseconds: 1300));
    expect(controller.hotDone, isEmpty);
    expect(controller.hotInProgress.first.text, 'Call the supplier');

    // Right-click opens the menu; Edit rewrites the task.
    await tester.tap(
      find.text('Order profile'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    // Edited in place — no dialog opens.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('hot-edit-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('hot-edit-field')),
      'Order profile 2 m',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hot-edit-field')), findsNothing);
    final edited = controller.hotInProgress.firstWhere(
      (t) => t.text == 'Order profile 2 m',
    );
    expect(find.text('Order profile 2 m'), findsOneWidget);

    // Esc cancels an edit and keeps the old text.
    await tester.tap(
      find.text('Order profile 2 m'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('hot-edit-field')), 'nope');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hot-edit-field')), findsNothing);
    expect(find.text('Order profile 2 m'), findsOneWidget);
    expect(controller.hotInProgress.any((t) => t.text == 'nope'), isFalse);

    // The time it was added is shown on the task.
    expect(
      find.text(hotAddedLabel(edited.created!, DateTime.now())),
      findsWidgets,
    );

    // Notes on the rail goes back to the editor.
    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    expect(find.byKey(const Key('hot-input')), findsNothing);

    await cleanUp(tester);
  });

  testWidgets('phone: drawer entry opens the view with two tabs', (
    tester,
  ) async {
    await pumpApp(tester, const Size(390, 844));

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('drawer-hot')));
    await tester.pumpAndSettle();

    expect(find.text('In progress · 1'), findsOneWidget);
    expect(find.text('Done · 0'), findsOneWidget);
    expect(find.text('Call the supplier'), findsOneWidget);

    // No hover on a phone: the delete button is shown and works.
    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    expect(controller.hotInProgress, isEmpty);
    expect(find.text('In progress · 0'), findsOneWidget);

    await tester.tap(find.text('Done · 0'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing done yet.'), findsOneWidget);

    await cleanUp(tester);
  });

  test(
    'the added label always carries the date, and the year only when older',
    () {
      final now = DateTime(2026, 9, 23, 18);
      expect(hotAddedLabel(DateTime(2026, 9, 23, 9, 5), now), 'Sep 23, 09:05');
      expect(
        hotAddedLabel(DateTime(2026, 9, 22, 21, 40), now),
        'Sep 22, 21:40',
      );
      expect(
        hotAddedLabel(DateTime(2025, 12, 31, 8, 0), now),
        'Dec 31 2025, 08:00',
      );
    },
  );

  test('dayLabel names today, yesterday and older days', () {
    final now = DateTime(2026, 9, 21, 9);
    expect(dayLabel(DateTime(2026, 9, 21, 0, 5), now), 'Today');
    expect(dayLabel(DateTime(2026, 9, 20, 23, 59), now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 9, 18, 12), now), 'Fri, Sep 18');
    // Across the DST change at the end of October.
    expect(
      dayLabel(DateTime(2026, 10, 25, 12), DateTime(2026, 10, 26, 1)),
      'Yesterday',
    );
  });
}
