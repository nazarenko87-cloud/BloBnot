import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(VaultController c) => ChangeNotifierProvider.value(
      value: c,
      child: const MaterialApp(home: HomePage()),
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_lock');
  });

  tearDown(() async {
    // Retry: debounced/unawaited writes may briefly hold files on Windows.
    for (var i = 0; i < 10; i++) {
      try {
        await tmp.delete(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  /// Let real async work (file I/O started from UI handlers) finish.
  Future<void> settle(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );

  testWidgets('lock screen gates the app and unlocks with the right password',
      (tester) async {
    late final VaultController controller;
    await tester.runAsync(() async {
      final store = PasswordStore(file: File('${tmp.path}/settings.json'));
      await store.setPassword('1234');
      controller = VaultController(passwordStore: store);
      await controller.refreshLock();
    });

    await tester.pumpWidget(_app(controller));
    await tester.pump();

    expect(find.text('BloBnot is locked'), findsOneWidget);

    // Wrong password → error stays locked.
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('BloBnot is locked'), findsOneWidget);
    expect(find.text('Wrong password'), findsOneWidget);

    // Correct password → unlocked.
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    await tester.pump();
    expect(find.text('BloBnot is locked'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('overdue reminder is auto-cleared when the note is opened',
      (tester) async {
    late final VaultController controller;
    await tester.runAsync(() async {
      File('${tmp.path}/Alpha.md').writeAsStringSync('# Alpha');
      File('${tmp.path}/Beta.md').writeAsStringSync('# Beta');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/s.json')),
      );
      await controller.openVault(tmp.path);
      await controller.setReminder(
        'Beta',
        DateTime.now().subtract(const Duration(hours: 1)),
      );
    });

    expect(controller.reminderFor('Beta'), isNotNull);

    // Opening the overdue note clears its reminder (v1.3 behaviour).
    final beta = controller.notes.firstWhere((n) => n.title == 'Beta');
    controller.select(beta);
    expect(controller.reminderFor('Beta'), isNull);

    await settle(tester); // let the unawaited reminders.json save finish
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
