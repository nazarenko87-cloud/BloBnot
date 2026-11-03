import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('preview text copies across paragraphs; checkboxes still tick', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpWith(tester, '# Report\nFirst part.\n\nSecond part.\n- [ ] item');
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview-selection')), findsOneWidget);

    // The box is the first glyph of the item's line ("☐ item").
    final box = find.textContaining('☐', findRichText: true);
    await tester.tapAt(tester.getTopLeft(box) + const Offset(5, 8));
    await tester.pumpAndSettle();
    expect(controller.current!.body, endsWith('- [x] item'));

    await tester.tapAt(
      tester.getCenter(find.textContaining('First', findRichText: true)),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied, contains('First part.'));
    expect(copied, contains('Second part.'));
    await cleanUp(tester);
  });
}
