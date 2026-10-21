import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
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

  testWidgets('wide window: every rail icon has a name beside it', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1280, 800));
    for (final name in [
      'Hot tasks',
      'Notes',
      'Notes list',
      'Dashboard',
      'Table',
      'Quick switcher',
      'Graph',
      'Refresh',
      'Open file',
      'Calculator',
      'Fullscreen',
      'Settings',
      'About',
    ]) {
      expect(rail(name), findsOneWidget, reason: name);
    }
    // And the rail still fits without scrolling.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('rail')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);
  });

  testWidgets('the chevron collapses the labels and brings them back', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const Key('rail-labels-toggle')));
    await tester.pump();
    expect(rail('Settings'), findsNothing);
    // Icons stay, with their tooltips.
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rail-labels-toggle')));
    await tester.pump();
    expect(rail('Settings'), findsOneWidget);
  });

  testWidgets('a remembered "icons only" choice is read back on start', (
    tester,
  ) async {
    // Real file I/O: the fake-async zone would never finish it.
    await tester.runAsync(() => AppState.write('rail', {'labels': false}));
    await pumpApp(tester, const Size(1280, 800));
    // The read is a chain of awaited I/O calls: each needs real time to
    // finish and a pump to resume in the fake-async zone.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(rail('Settings'), findsNothing);
    expect(find.byTooltip('Show labels'), findsOneWidget);
  });

  testWidgets('narrow window keeps icons only, with no labels switch', (
    tester,
  ) async {
    await pumpApp(tester, const Size(1000, 700));
    expect(rail('Settings'), findsNothing);
    expect(find.byKey(const Key('rail-labels-toggle')), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
