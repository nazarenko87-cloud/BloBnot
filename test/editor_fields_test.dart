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
  late Directory dir;
  late VaultController controller;

  Future<void> pumpWith(WidgetTester tester, String body) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_fields');
      AppSettings.overrideFile = File('${dir.path}/app.json');
      File('${dir.path}/Report.md').writeAsStringSync(body);
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
      // Let the pending save land before the folder is deleted — dispose()
      // alone starts it without waiting.
      await controller.reload();
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

  testWidgets('the Fields button opens a block at the top of the note', (
    tester,
  ) async {
    await pumpWith(tester, '# Report\ntext');
    await tester.tap(find.byTooltip('Add a field (shows in Table)'));
    await tester.pump();
    expect(controller.current!.body, '---\n\n---\n# Report\ntext');

    // A second press adds another line inside the same block.
    await tester.tap(find.byTooltip('Add a field (shows in Table)'));
    await tester.pump();
    expect(controller.current!.body, '---\n\n\n---\n# Report\ntext');
    await cleanUp(tester);
  });

  testWidgets('the preview shows fields as a card, not raw lines', (
    tester,
  ) async {
    await pumpWith(
      tester,
      '---\nmanager: Oleg\nstatus: needs fixes\n---\n# Report\n- [ ] item',
    );
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('properties-card')), findsOneWidget);
    expect(find.text('manager'), findsOneWidget);
    expect(find.text('needs fixes'), findsOneWidget);
    // The fence lines are not rendered as text.
    expect(find.textContaining('status: needs fixes'), findsNothing);
    await cleanUp(tester);
  });
}
