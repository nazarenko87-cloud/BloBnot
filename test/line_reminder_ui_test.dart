import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Drives the actual bell-menu → "Reminder on line" → date/time picker flow
/// end to end, the same path a user clicks through.
void main() {
  testWidgets(
      'bell menu "Reminder on line" inserts a {{remind:}} tag via the '
      'date+time pickers', (tester) async {
    late final Directory tmp;
    late final VaultController controller;

    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_linerem_ui');
      AppSettings.overrideFile = File('${tmp.path}/app.json');
      File('${tmp.path}/Alpha.md').writeAsStringSync('# Alpha\nbody text');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    // Open the merged reminder bell menu in the editor header.
    await tester.tap(find.byTooltip('Reminders'));
    await tester.pumpAndSettle();
    expect(find.text('Reminder on line (at cursor)'), findsOneWidget);

    await tester.tap(find.text('Reminder on line (at cursor)'));
    await tester.pumpAndSettle();

    // The date picker should now be showing — confirm with its default OK.
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The time picker should now be showing — confirm with its default OK.
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    // Not pumpAndSettle: the note now has an active reminder, so its glyph
    // starts a repeating pulse animation that never "settles" — bounded
    // pumps only, same as production frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final note = controller.notes.firstWhere((n) => n.title == 'Alpha');
    expect(note.body, contains('{{remind:'));

    // Dashboard reflects the new reminder in its stats and the note's badge.
    await tester.tap(find.byTooltip('Dashboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('1'), findsWidgets); // Reminders stat = 1
    expect(find.byIcon(Icons.notifications_active), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    AppSettings.overrideFile = null;
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        try {
          await tmp.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}
