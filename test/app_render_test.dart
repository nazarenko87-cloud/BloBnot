import 'dart:io';

import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// End-to-end render test: seed a temp vault, open it, and pump the full app.
/// Exercises NoteList, EditorPane (split markdown), and GraphView build paths
/// without needing a native Windows build.
///
/// Real file I/O must run via [WidgetTester.runAsync] because the default
/// testWidgets zone uses fake async and never completes real I/O futures.
void main() {
  testWidgets('renders list, editor and graph from a real vault',
      (tester) async {
    late final Directory dir;
    late final VaultController controller;

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_test');
      File('${dir.path}/Alpha.md')
          .writeAsStringSync('# Alpha\n\nLinks to [[Beta]].');
      File('${dir.path}/Beta.md').writeAsStringSync('# Beta\n\nPlain note.');
      controller = VaultController();
      await controller.openVault(dir.path);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    // Note list shows both notes.
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);

    // Editor header shows a word count for the selected (first) note.
    expect(find.textContaining('words'), findsOneWidget);

    // Graph reflects 2 nodes and 1 edge (Alpha -> Beta).
    expect(find.text('Graph  2 · 1'), findsOneWidget);

    // Dispose the widget tree (stops the graph ticker) before the controller.
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
