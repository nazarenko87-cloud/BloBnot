import 'dart:io';

import 'package:blobnot/models/note.dart';
import 'package:blobnot/services/glyph_store.dart';
import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/project_order_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Note _note(String title, String body) => Note(
      path: '/v/$title.md',
      title: title,
      body: body,
      modified: DateTime(2026),
    );

void main() {
  group('Note tags & checklist progress', () {
    test('tags parses lowercase unique #tags incl cyrillic', () {
      expect(
        _note('x', 'text #Work more #работа and #work again').tags,
        ['work', 'работа'],
      );
    });

    test('checklistProgress is done/total or null', () {
      expect(_note('x', 'no boxes').checklistProgress, isNull);
      expect(
        _note('x', '- [x] a\n- [ ] b\n- [X] c\n- [ ] d').checklistProgress,
        0.5,
      );
    });
  });

  group('ProjectOrderStore.applyOrder', () {
    test('saved order first, unknown keep relative order at end', () {
      expect(
        ProjectOrderStore.applyOrder(
          ['Alpha', 'Beta', 'Gamma', 'Delta'],
          ['Gamma', 'Alpha'],
        ),
        ['Gamma', 'Alpha', 'Beta', 'Delta'],
      );
    });
  });

  group('Glyphs end to end', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_glyph');
      AppSettings.overrideFile = File('${tmp.path}/app.json');
    });

    tearDown(() async {
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

    test('override wins over tag glyph; long legacy values ignored',
        () async {
      File('${tmp.path}/A.md').writeAsStringSync('body #work');
      // Legacy icon-name value must be ignored, emoji accepted.
      File('${tmp.path}/glyphs.json')
          .writeAsStringSync('{"work":"💼","old":"briefcaseIconName"}');
      final controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);

      final a = controller.notes.first;
      expect(controller.glyphFor(a), '💼');

      await controller.setNoteGlyph('A', '🚀');
      expect(controller.glyphFor(a), '🚀');
      expect(
        File('${tmp.path}/glyph_overrides.json').existsSync(),
        isTrue,
      );

      await controller.setNoteGlyph('A', null);
      expect(controller.glyphFor(a), '💼');

      controller.dispose();
    });

    test('reorderProjects persists projectorder.json', () async {
      Directory('${tmp.path}/One').createSync();
      Directory('${tmp.path}/Two').createSync();
      Directory('${tmp.path}/Three').createSync();
      final controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);
      expect(controller.projects, ['One', 'Three', 'Two']); // alphabetical

      await controller.reorderProjects(2, 0); // move Two first
      expect(controller.projects, ['Two', 'One', 'Three']);
      expect(
        await ProjectOrderStore(tmp.path).load(),
        ['Two', 'One', 'Three'],
      );

      controller.dispose();
    });

    test('GlyphStore keeps override key case, lowercases tag keys', () async {
      final store = GlyphStore(tmp.path);
      await store.saveOverrides({'MyNote': '⭐'});
      await store.saveTagGlyphs({'Работа'.toLowerCase(): '🔥'});
      expect(await store.loadOverrides(), {'MyNote': '⭐'});
      expect(await store.loadTagGlyphs(), {'работа': '🔥'});
    });
  });
}
