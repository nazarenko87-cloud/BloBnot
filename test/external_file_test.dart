import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/external_file_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Drives "Open file…" → view → "Save to notes" for a .txt file living
/// outside the vault, the same path a user goes through (minus the native
/// file-picker dialog itself, which ExternalFilesController.open() replaces
/// here with a direct path).
void main() {
  testWidgets('opens an external file, shows its path, and saves it as a note',
      (tester) async {
    late final Directory vaultDir;
    late final Directory outsideDir;
    late final VaultController controller;
    late final ExternalFilesController files;

    await tester.runAsync(() async {
      vaultDir = await Directory.systemTemp.createTemp('blobnot_extfile_vault');
      outsideDir = await Directory.systemTemp.createTemp('blobnot_extfile_out');
      AppSettings.overrideFile = File('${vaultDir.path}/app.json');
      File('${outsideDir.path}/notes.txt')
          .writeAsStringSync('Some external text.');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${vaultDir.path}/pw.json')),
      );
      await controller.openVault(vaultDir.path);
      files = ExternalFilesController();
      await files.open('${outsideDir.path}/notes.txt');
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: files),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ExternalFileTabs(),
                Expanded(child: ExternalFileViewer()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Tab + viewer show the file name and full external path.
    expect(find.text('notes.txt'), findsWidgets);
    expect(find.text('${outsideDir.path}/notes.txt'), findsOneWidget);
    expect(find.text('Some external text.'), findsOneWidget);

    // Editing here does not touch the original file — only the vault note
    // created by "Save to notes" should carry the new text. The tap
    // triggers real file I/O (VaultStorage.create), which never resolves in
    // the fake-async test zone — the tap itself must run inside runAsync so
    // its awaited chain executes on the real zone throughout.
    await tester.enterText(find.byType(TextField), 'Edited in BloBnot.');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save to notes'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(controller.notes.map((n) => n.title), contains('notes'));
    final saved = controller.notes.firstWhere((n) => n.title == 'notes');
    expect(saved.body, 'Edited in BloBnot.');
    expect(
      File('${outsideDir.path}/notes.txt').readAsStringSync(),
      'Some external text.',
    );

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    AppSettings.overrideFile = null;
    await tester.runAsync(() async {
      for (final dir in [vaultDir, outsideDir]) {
        for (var i = 0; i < 10; i++) {
          try {
            await dir.delete(recursive: true);
            break;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    });
  }, timeout: const Timeout(Duration(seconds: 60)));
}
