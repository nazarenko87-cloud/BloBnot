import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/calculator_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late VaultController controller;

  Future<void> open(WidgetTester tester, {bool withNote = true}) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_calc_ui');
      AppSettings.overrideFile = File('${dir.path}/app.json');
      if (withNote) File('${dir.path}/Note.md').writeAsStringSync('# Note\n');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${dir.path}/pw.json')),
      );
      await controller.openVault(dir.path);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCalculatorDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
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
        // Windows may still hold a handle.
      }
    });
  }

  Finder key(String label) =>
      find.descendant(of: find.byType(InkWell), matching: find.text(label));

  String display(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('calc-display'))).data!;

  testWidgets('keypad clicks compute with the expression line', (tester) async {
    await open(tester);
    for (final k in ['1', '2', '+', '7', '=']) {
      await tester.tap(key(k));
      await tester.pump();
    }
    expect(display(tester), '19');
    expect(
      tester.widget<Text>(find.byKey(const Key('calc-expression'))).data,
      '12 + 7 =',
    );
    await cleanUp(tester);
  });

  testWidgets('keyboard input works', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadMultiply);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(display(tester), '27');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadDivide);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();
    expect(display(tester), '9');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorDialog), findsNothing);
    await cleanUp(tester);
  });

  testWidgets('memory keys enable once something is stored', (tester) async {
    await open(tester);
    final mr = find.widgetWithText(TextButton, 'MR');
    expect(tester.widget<TextButton>(mr).onPressed, isNull);
    await tester.tap(key('5'));
    await tester.tap(find.widgetWithText(TextButton, 'MS'));
    await tester.pump();
    expect(tester.widget<TextButton>(mr).onPressed, isNotNull);
    expect(find.text('M = 5'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('converter: length shows metres in feet and swaps', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Modes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Length'));
    await tester.pumpAndSettle();

    String text(String k) => tester.widget<Text>(find.byKey(Key(k))).data!;
    expect(text('conv-from'), '5');
    expect(text('conv-to'), '16.40419948');

    // Swapping twice returns exactly the typed 5, not a drifted float.
    await tester.tap(find.text('Swap'));
    await tester.pump();
    expect(text('conv-from'), '16.4041994751');
    expect(text('conv-to'), '5');
    await tester.tap(find.text('Swap'));
    await tester.pump();
    expect(text('conv-from'), '5');
    expect(text('conv-to'), '16.40419948');

    await tester.tap(key('CE'));
    await tester.tap(key('1'));
    await tester.tap(key('0'));
    await tester.pump();
    expect(text('conv-from'), '10');
    expect(text('conv-to'), '32.80839895');
    await cleanUp(tester);
  });

  testWidgets('insert into note puts the result into the open note', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(key('4'));
    await tester.tap(key('2'));
    await tester.tap(find.byTooltip('Insert into note'));
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorDialog), findsNothing);
    expect(controller.current!.body, '# Note\n42');
    expect(find.text('Inserted 42'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await cleanUp(tester);
  });

  testWidgets('insert with no note open explains and stays open', (
    tester,
  ) async {
    await open(tester, withNote: false);
    await tester.tap(key('7'));
    await tester.tap(find.byTooltip('Insert into note'));
    await tester.pump();
    expect(find.byType(CalculatorDialog), findsOneWidget);
    expect(find.text('Open a note first, then insert'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await cleanUp(tester);
  });
}
