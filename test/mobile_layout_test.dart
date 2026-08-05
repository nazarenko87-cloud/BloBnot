import 'dart:io';

import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// On a phone-width viewport, HomePage should switch to the single-pane
/// layout: full-screen editor, a drawer for nav+notes (no cramped side
/// panels), and tapping a note in the drawer both selects it and closes
/// the drawer.
void main() {
  testWidgets('phone-width viewport shows the drawer layout, not the desktop shell',
      (tester) async {
    late final Directory dir;
    late final VaultController controller;

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_mobile');
      AppSettings.overrideFile = File('${dir.path}/app_settings.json');
      File('${dir.path}/Alpha.md').writeAsStringSync('# Alpha\nbody text');
      File('${dir.path}/Beta.md').writeAsStringSync('# Beta\nother text');
      controller = VaultController();
      await controller.openVault(dir.path);
    });

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
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

    // Single-pane: the editor fills the screen, no side-by-side note list
    // or graph card competing for space, and the note title is in the
    // AppBar rather than a cramped header.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Drawer), findsNothing); // closed by default
    expect(find.text('Alpha'), findsOneWidget); // AppBar title

    // Open the drawer and switch notes from it.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    // Drawer closed itself, and the AppBar now shows the newly opened note.
    expect(find.byType(Drawer), findsNothing);
    expect(controller.current?.title, 'Beta');
    expect(find.widgetWithText(AppBar, 'Beta'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    AppSettings.overrideFile = null;
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        try {
          await dir.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}
