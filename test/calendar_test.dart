import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Drives the dashboard calendar's "add a standalone reminder" flow end to
/// end: tap today's cell, add a reminder, confirm the time picker, and see
/// it show up both in the day dialog and in [VaultController.events].
void main() {
  testWidgets('calendar adds a standalone reminder for the tapped day',
      (tester) async {
    late final Directory tmp;
    late final VaultController controller;

    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_calendar');
      AppSettings.overrideFile = File('${tmp.path}/app.json');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: DashboardView(onOpenNote: () {})),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Calendar'), findsOneWidget);

    // Today's cell is bordered/bold; find it by day number.
    final today = DateTime.now();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();

    expect(find.text('No reminders on this day.'), findsOneWidget);

    await tester.tap(find.text('Add reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Call the plumber');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Time picker's default OK.
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(controller.events, hasLength(1));
    expect(controller.events.single.title, 'Call the plumber');
    expect(find.text('Call the plumber'), findsOneWidget);
    expect(find.text('No reminders on this day.'), findsNothing);

    // Deleting it from the day dialog clears it.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(controller.events, isEmpty);

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
