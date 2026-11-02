import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/focus_mode.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;
  late VaultController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_rail');
    AppSettings.overrideFile = File('${tmp.path}/app.json');
    File('${tmp.path}/Alpha.md').writeAsStringSync('# Alpha');
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

  Finder rail(String text) =>
      find.descendant(of: find.byKey(const Key('rail')), matching: find.text(text));

  testWidgets('icons only by default; the chevron brings the names', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(rail('Settings'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rail-labels-toggle')));
    await tester.pump();
    for (final name in [
      'Hot tasks',
      'Notes',
      'Dashboard',
      'Table',
      'Quick switcher',
      'Graph',
      'Settings',
      'More',
    ]) {
      expect(rail(name), findsOneWidget, reason: name);
    }
    // Rarely used commands moved into the More menu.
    for (final gone in ['Notes list', 'Refresh', 'Calculator', 'About']) {
      expect(rail(gone), findsNothing, reason: gone);
    }
    // And the rail still fits without scrolling.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('rail')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);

    await tester.tap(find.byKey(const Key('rail-labels-toggle')));
    await tester.pump();
    expect(rail('Settings'), findsNothing);
  });

  testWidgets('a remembered "names on" choice is read back on start', (
    tester,
  ) async {
    // Real file I/O: the fake-async zone would never finish it.
    await tester.runAsync(() => AppState.write('rail', {'labels': true}));
    await pumpApp(tester, const Size(1280, 800));
    // The read is a chain of awaited I/O calls: each needs real time to
    // finish and a pump to resume in the fake-async zone.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(rail('Settings'), findsOneWidget);
    expect(find.byTooltip('Hide labels'), findsOneWidget);
  });

  testWidgets('narrow window keeps icons only, with no labels switch', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1000, 700));
    expect(rail('Settings'), findsNothing);
    expect(find.byKey(const Key('rail-labels-toggle')), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('Notes on the notes view shows and hides the list', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.text('Search notes…'), findsOneWidget);

    await tester.tap(find.byTooltip('Notes — hide the list'));
    await tester.pump();
    expect(find.text('Search notes…'), findsNothing);

    await tester.tap(find.byTooltip('Notes — show the list'));
    await tester.pump();
    expect(find.text('Search notes…'), findsOneWidget);
  });

  testWidgets('More holds the rarely used commands', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final name in [
      'Focus mode',
      'Refresh from disk',
      'Open file (.txt / .md)',
      'Calculator',
      'Fullscreen',
      'About',
    ]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('focus mode leaves only the note; Esc brings the rest back', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.byKey(const Key('rail')), findsOneWidget);
    expect(find.byTooltip('Bold'), findsWidgets);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.period);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const Key('rail')), findsNothing);
    expect(find.text('Search notes…'), findsNothing);
    expect(find.byTooltip('Bold'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget); // the note's title stays

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('rail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('focus-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('rail')), findsNothing);
    await tester.tap(find.byKey(const Key('focus-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('rail')), findsOneWidget);
  });

  testWidgets('Ctrl+. works on a Cyrillic layout, where that key types "ю"', (
    tester,
  ) async {
    // The test key simulator cannot send a Cyrillic key, so ask the activator.
    KeyDownEvent press(LogicalKeyboardKey logical, PhysicalKeyboardKey key) =>
        KeyDownEvent(
          physicalKey: key,
          logicalKey: logical,
          timeStamp: Duration.zero,
        );
    const activator = CtrlPeriodKeyActivator();
    final keyboard = HardwareKeyboard.instance;
    final yu = press(const LogicalKeyboardKey(0x44e), PhysicalKeyboardKey.period);
    final dot = press(LogicalKeyboardKey.period, PhysicalKeyboardKey.slash);

    expect(activator.accepts(yu, keyboard), isFalse); // no Ctrl held
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(activator.accepts(yu, keyboard), isTrue);
    expect(activator.accepts(dot, keyboard), isTrue); // "." on another key
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });
}
