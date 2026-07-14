import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/utils/editor_ops.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorOps.prefixLine', () {
    test('does not throw when the caret is at offset 0', () {
      final ctrl = TextEditingController(text: 'hello world')
        ..selection = const TextSelection.collapsed(offset: 0);
      expect(() => EditorOps.prefixLine(ctrl, '# '), returnsNormally);
      expect(ctrl.text, '# hello world');
    });

    test('still finds the correct line when caret is mid-document', () {
      final ctrl = TextEditingController(text: 'first\nsecond\nthird')
        ..selection = const TextSelection.collapsed(offset: 9); // in "second"
      EditorOps.prefixLine(ctrl, '- ');
      expect(ctrl.text, 'first\n- second\nthird');
    });
  });

  group('VaultController note-removal bookkeeping', () {
    late Directory tmp;
    late VaultController controller;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_bugfix');
      AppSettings.overrideFile = File('${tmp.path}/app.json');
      File('${tmp.path}/Alpha.md').writeAsStringSync('# Alpha');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);
    });

    tearDown(() async {
      controller.dispose();
      AppSettings.overrideFile = null;
      for (var i = 0; i < 10; i++) {
        try {
          await tmp.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    test(
        'deleteNote clears pin and glyph override so a recreated note with '
        'the same title starts clean', () async {
      final alpha = controller.notes.first;
      await controller.togglePin('Alpha');
      await controller.setNoteGlyph('Alpha', '🔥');
      expect(controller.isPinned('Alpha'), isTrue);
      expect(controller.glyphFor(alpha), '🔥');

      await controller.deleteNote(alpha);
      expect(controller.isPinned('Alpha'), isFalse);

      final recreated = await controller.createNote('Alpha');
      expect(controller.isPinned('Alpha'), isFalse);
      expect(controller.glyphFor(recreated), isNull);
    });

    test('archiveNote also clears the glyph override', () async {
      final alpha = controller.notes.first;
      await controller.setNoteGlyph('Alpha', '⭐');
      await controller.archiveNote(alpha);

      final recreated = await controller.createNote('Alpha');
      expect(controller.glyphFor(recreated), isNull);
    });

    test('closeTab on the last remaining note does not throw', () async {
      final alpha = controller.notes.first;
      controller.select(alpha); // ensures it is in openTabs and current
      await controller.deleteNote(alpha); // vault is now empty
      expect(() => controller.closeTab(alpha.path), returnsNormally);
      expect(controller.current, isNull);
    });
  });
}
