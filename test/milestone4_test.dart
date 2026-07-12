import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/services/vault_storage.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/utils/editor_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Checklist', () {
    const body = 'intro\n- [ ] task one\n- [x] done\nplain';

    test('toggleLine checks an unchecked item', () {
      expect(
        Checklist.toggleLine(body, 1),
        'intro\n- [x] task one\n- [x] done\nplain',
      );
    });

    test('toggleLine unchecks a checked item', () {
      expect(
        Checklist.toggleLine(body, 2),
        'intro\n- [ ] task one\n- [ ] done\nplain',
      );
    });

    test('toggleLine returns null for non-checklist lines', () {
      expect(Checklist.toggleLine(body, 0), isNull);
      expect(Checklist.toggleLine(body, 3), isNull);
      expect(Checklist.toggleLine(body, 99), isNull);
    });

    test('linkify rewrites boxes as checkbox: links with line numbers', () {
      expect(
        Checklist.linkify(body),
        'intro\n- [☐](checkbox:1) task one\n- [☑](checkbox:2) done\nplain',
      );
    });
  });

  group('EditorOps', () {
    test('wrapSelection wraps the selected range', () {
      final c = TextEditingController(text: 'hello world');
      c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      EditorOps.wrapSelection(c, '**', '**');
      expect(c.text, 'hello **world**');
    });

    test('prefixLine inserts at line start', () {
      final c = TextEditingController(text: 'one\ntwo');
      c.selection = const TextSelection.collapsed(offset: 5);
      EditorOps.prefixLine(c, '- ');
      expect(c.text, 'one\n- two');
    });
  });

  group('Projects', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_m4');
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

    test('listProjects skips reserved folders; projectOf resolves', () async {
      Directory('${tmp.path}/Work').createSync();
      Directory('${tmp.path}/_archive').createSync();
      Directory('${tmp.path}/attachments').createSync();
      File('${tmp.path}/Root.md').writeAsStringSync('r');
      File('${tmp.path}/Work/Task.md').writeAsStringSync('t');

      final storage = VaultStorage(tmp.path);
      expect(await storage.listProjects(), ['Work']);

      final notes = await storage.loadNotes();
      final root = notes.firstWhere((n) => n.title == 'Root');
      final task = notes.firstWhere((n) => n.title == 'Task');
      expect(storage.projectOf(root), '');
      expect(storage.projectOf(task), 'Work');
    });

    test('controller createProject + createNote in project', () async {
      final controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
      await controller.openVault(tmp.path);

      await controller.createProject('Ideas');
      expect(controller.projects, ['Ideas']);

      final note = await controller.createNote('Spark', subfolder: 'Ideas');
      expect(controller.projectOf(note), 'Ideas');
      expect(File('${tmp.path}/Ideas/Spark.md').existsSync(), isTrue);

      controller.dispose();
    });
  });
}
