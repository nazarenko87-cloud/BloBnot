import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('dashboard shows stats and note cards; tap opens note',
      (tester) async {
    late final Directory tmp;
    late final VaultController controller;

    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_dash');
      AppSettings.overrideFile = File('${tmp.path}/app.json');
      Directory('${tmp.path}/Work').createSync();
      File('${tmp.path}/Alpha.md')
          .writeAsStringSync('# Alpha\nsome body text');
      File('${tmp.path}/Work/Beta.md').writeAsStringSync('# Beta\nmore text');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);
    });

    var opened = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: DashboardView(onOpenNote: () => opened = true),
          ),
        ),
      ),
    );
    await tester.pump();

    // Stats: 2 notes, 1 project, 0 reminders.
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);

    // Cards for both notes; Beta carries its project chip.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('WORK'), findsOneWidget); // project chip is upper-cased

    // Tapping a card selects the note and fires the callback.
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(opened, isTrue);
    expect(controller.current?.title, 'Beta');

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    AppSettings.overrideFile = null;
    // select() writes recent.json asynchronously; retry the delete until the
    // handle is released (Windows).
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
