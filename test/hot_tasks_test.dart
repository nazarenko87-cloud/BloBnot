import 'dart:io';

import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/utils/hot_tasks.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 21, 15, 0);

void main() {
  group('format', () {
    test('parses open and done tasks with their stamps', () {
      final tasks = parseHotTasks(
        '# Hot tasks\n\n- [ ] Call the supplier\n'
        '- [x] Send the invoice ✓ 2026-09-21 14:30\n',
        now: now,
      );
      expect(tasks.map((t) => t.text), [
        'Call the supplier',
        'Send the invoice',
      ]);
      expect(tasks[0].isDone, isFalse);
      expect(tasks[1].done, DateTime(2026, 9, 21, 14, 30));
    });

    test('ignores anything that is not a checklist line', () {
      final tasks = parseHotTasks(
        '# Title\nsome prose\n* [ ] star bullet\n-[ ] broken\n',
        now: now,
      );
      expect(tasks.map((t) => t.text), ['star bullet']);
    });

    test('a [x] without a stamp counts as done now', () {
      final t = parseHotTasks('- [X] Hand-ticked', now: now).single;
      expect(t.done, now);
    });

    test('skips empty task text', () {
      expect(parseHotTasks('- [ ] \n- [ ]   ', now: now), isEmpty);
    });

    test('handles Windows line endings', () {
      final tasks = parseHotTasks(
        '- [ ] a\r\n- [x] b ✓ 2026-09-20 09:05\r\n',
        now: now,
      );
      expect(tasks.map((t) => t.text), ['a', 'b']);
      expect(tasks[1].done, DateTime(2026, 9, 20, 9, 5));
    });

    test('round-trips: open first in order, then done newest first', () {
      final tasks = [
        const HotTask(id: 0, text: 'first'),
        HotTask(id: 1, text: 'older', done: DateTime(2026, 9, 20, 10, 0)),
        const HotTask(id: 2, text: 'second'),
        HotTask(id: 3, text: 'newer', done: DateTime(2026, 9, 21, 9, 0)),
      ];
      final text = serializeHotTasks(tasks);
      expect(
        text,
        '# Hot tasks\n\n- [ ] first\n- [ ] second\n'
        '- [x] newer ✓ 2026-09-21 09:00\n- [x] older ✓ 2026-09-20 10:00\n',
      );
      final again = parseHotTasks(text, now: now);
      expect(serializeHotTasks(again), text);
    });

    test('round-trips the added stamp, and lines without one still parse', () {
      final t = HotTask(
        id: 0,
        text: 'call',
        created: DateTime(2026, 9, 22, 9, 15),
        done: DateTime(2026, 9, 22, 14, 30),
      );
      expect(
        hotTaskLine(t),
        '- [x] call + 2026-09-22 09:15 ✓ 2026-09-22 14:30',
      );
      final back = parseHotTasks(hotTaskLine(t), now: now).single;
      expect(back.created, t.created);
      expect(back.done, t.done);
      expect(back.text, 'call');

      final old = parseHotTasks('- [ ] no stamps\n', now: now).single;
      expect(old.created, isNull);
      expect(hotTaskLine(old), '- [ ] no stamps');
    });

    test('a + inside the text is not mistaken for a stamp', () {
      final t = parseHotTasks('- [ ] buy 2 + 2 adapters\n', now: now).single;
      expect(t.text, 'buy 2 + 2 adapters');
      expect(t.created, isNull);
    });

    test('cleans text to a single line', () {
      expect(cleanHotText('  two\nlines\t here '), 'two lines here');
    });
  });

  group('mergeExternal', () {
    var next = 100;
    int ids() => next++;

    test('adds unknown tasks and applies outside completions', () {
      final memory = [
        const HotTask(id: 1, text: 'a'),
        const HotTask(id: 2, text: 'b'),
      ];
      final baseline = {'- [ ] a', '- [ ] b'};
      final disk = parseHotTasks(
        '- [ ] new\n- [ ] a\n- [x] b ✓ 2026-09-21 10:00\n',
        now: now,
      );
      final merged = mergeExternal(
        memory: memory,
        baseline: baseline,
        disk: disk,
        nextId: ids,
      );
      expect(merged.map(hotTaskLine), [
        '- [ ] new',
        '- [ ] a',
        '- [x] b ✓ 2026-09-21 10:00',
      ]);
    });

    test('does not replay outside deletions or duplicate known lines', () {
      final memory = [const HotTask(id: 1, text: 'keep me')];
      final merged = mergeExternal(
        memory: memory,
        baseline: {'- [ ] keep me'},
        disk: const [],
        nextId: ids,
      );
      expect(merged.map((t) => t.text), ['keep me']);
    });

    test('an app deletion is not undone by the stale line on disk', () {
      final merged = mergeExternal(
        memory: const [],
        baseline: {'- [ ] deleted in app'},
        disk: parseHotTasks('- [ ] deleted in app\n', now: now),
        nextId: ids,
      );
      expect(merged, isEmpty);
    });
  });

  group('archive', () {
    test('moves done tasks older than 30 days, keeps the rest', () {
      final tasks = [
        const HotTask(id: 0, text: 'open'),
        HotTask(
          id: 1,
          text: 'recent',
          done: now.subtract(const Duration(days: 29)),
        ),
        HotTask(
          id: 2,
          text: 'old',
          done: now.subtract(const Duration(days: 31)),
        ),
      ];
      final split = splitForArchive(tasks, now);
      expect(split.keep.map((t) => t.text), ['open', 'recent']);
      expect(split.archive.map((t) => t.text), ['old']);
    });

    test('never archives an open task, however old the file', () {
      final split = splitForArchive([const HotTask(id: 0, text: 'open')], now);
      expect(split.archive, isEmpty);
    });

    test('appending does not duplicate a task already archived', () {
      final old = HotTask(id: 5, text: 'old', done: DateTime(2026, 7, 1, 8, 0));
      final first = appendToArchive('', [old], now);
      final second = appendToArchive(first, [old], now);
      expect(second, first);
      expect(parseHotTasks(second, now: now).single.text, 'old');
    });
  });

  group('VaultController', () {
    late Directory tmp;
    late VaultController controller;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('blobnot_hot');
      AppSettings.overrideFile = File('${tmp.path}/app.json');
      File('${tmp.path}/Note.md').writeAsStringSync('# Note\n');
      controller = VaultController(
        passwordStore: PasswordStore(file: File('${tmp.path}/pw.json')),
      );
    });

    tearDown(() async {
      controller.dispose();
      for (var i = 0; i < 5; i++) {
        try {
          await tmp.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    File hotFile() => File('${tmp.path}/_hot/tasks.md');

    test('add, complete, reopen and delete persist to _hot/tasks.md', () async {
      await controller.openVault(tmp.path);
      await controller.addHotTask('Call Oleg');
      await controller.addHotTask('Order profile');
      expect(controller.hotInProgress.map((t) => t.text), [
        'Order profile',
        'Call Oleg',
      ]);
      expect(controller.hotInProgressCount, 2);

      final call = controller.hotInProgress.last;
      await controller.completeHotTask(call.id);
      expect(controller.hotInProgress.single.text, 'Order profile');
      expect(controller.hotDone.single.text, 'Call Oleg');
      expect(controller.lastCompletedHotId, call.id);
      // The line carries both stamps: when it was added and when it was done.
      expect(
        hotFile().readAsStringSync(),
        matches(RegExp(r'- \[x\] Call Oleg \+ [\d-]+ [\d:]+ ✓ [\d-]+ [\d:]+')),
      );
      expect(controller.hotDone.single.created, isNotNull);

      await controller.reopenHotTask(call.id);
      expect(controller.hotInProgress.first.text, 'Call Oleg');
      expect(controller.hotDone, isEmpty);

      await controller.deleteHotTask(call.id);
      expect(hotFile().readAsStringSync(), isNot(contains('Call Oleg')));
    });

    test('a new task is stamped with when it was added', () async {
      await controller.openVault(tmp.path);
      final before = DateTime.now().subtract(const Duration(minutes: 1));
      await controller.addHotTask('Call Oleg');
      final created = controller.hotInProgress.single.created;
      expect(created, isNotNull);
      expect(created!.isAfter(before), isTrue);
      expect(hotFile().readAsStringSync(), contains('- [ ] Call Oleg + '));
    });

    test('editing changes the text and keeps the stamps', () async {
      await controller.openVault(tmp.path);
      await controller.addHotTask('Call Olge');
      final task = controller.hotInProgress.single;
      await controller.editHotTask(task.id, '  Call Oleg\nabout the office ');
      final edited = controller.hotInProgress.single;
      expect(edited.text, 'Call Oleg about the office');
      expect(edited.created, task.created);
      expect(edited.id, task.id);
      expect(
        hotFile().readAsStringSync(),
        contains('Call Oleg about the office'),
      );

      // Empty text and unknown ids change nothing.
      await controller.editHotTask(task.id, '   ');
      await controller.editHotTask(-1, 'ghost');
      expect(
        controller.hotInProgress.single.text,
        'Call Oleg about the office',
      );
    });

    test('blank input adds nothing', () async {
      await controller.openVault(tmp.path);
      await controller.addHotTask('   ');
      expect(controller.hotInProgress, isEmpty);
      expect(hotFile().existsSync(), isFalse);
    });

    test(
      'the hot folder is not a project and its file is not a note',
      () async {
        Directory('${tmp.path}/_hot').createSync();
        hotFile().writeAsStringSync('- [ ] hidden\n');
        await controller.openVault(tmp.path);
        expect(controller.projects, isNot(contains('_hot')));
        expect(controller.notes.map((n) => n.title), ['Note']);
        expect(controller.hotInProgress.single.text, 'hidden');
      },
    );

    test('opening the vault archives done tasks older than 30 days', () async {
      Directory('${tmp.path}/_hot').createSync();
      final old = DateTime.now().subtract(const Duration(days: 40));
      hotFile().writeAsStringSync(
        '- [ ] keep\n- [x] ancient ✓ ${formatHotStamp(old)}\n',
      );
      await controller.openVault(tmp.path);
      expect(controller.hotDone, isEmpty);
      expect(hotFile().readAsStringSync(), isNot(contains('ancient')));
      final archive = await controller.loadHotArchive();
      expect(archive.single.text, 'ancient');
    });

    test(
      'rapid changes land in order: the file ends with the last state',
      () async {
        await controller.openVault(tmp.path);
        final writes = <Future<void>>[
          for (var i = 0; i < 20; i++) controller.addHotTask('task $i'),
        ];
        await Future.wait(writes);
        final saved = parseHotTasks(
          hotFile().readAsStringSync(),
          now: DateTime.now(),
        );
        expect(saved, hasLength(20));
        expect(saved.first.text, 'task 19');
      },
    );

    test('refresh picks up the file edited outside the app', () async {
      await controller.openVault(tmp.path);
      await controller.addHotTask('from app');
      hotFile().writeAsStringSync('- [ ] from app\n- [ ] from MCP\n');
      await controller.reload();
      expect(controller.hotInProgress.map((t) => t.text), [
        'from app',
        'from MCP',
      ]);
    });

    test(
      'a task added outside the app survives the app\'s next save',
      () async {
        await controller.openVault(tmp.path);
        await controller.addHotTask('from app');
        // The MCP server adds a task while the app is open, without a refresh.
        hotFile().writeAsStringSync(
          '# Hot tasks\n\n- [ ] from MCP\n- [ ] from app\n',
        );
        await controller.addHotTask('second from app');
        expect(controller.hotInProgress.map((t) => t.text), [
          'from MCP',
          'second from app',
          'from app',
        ]);
        final saved = parseHotTasks(
          hotFile().readAsStringSync(),
          now: DateTime.now(),
        );
        expect(
          saved.map((t) => t.text),
          containsAll(['from MCP', 'from app', 'second from app']),
        );
      },
    );

    test(
      'a task completed outside the app is completed in the app too',
      () async {
        await controller.openVault(tmp.path);
        await controller.addHotTask('Call Oleg');
        await controller.addHotTask('Order profile');
        hotFile().writeAsStringSync(
          '- [ ] Order profile\n- [x] Call Oleg ✓ 2026-09-21 10:00\n',
        );
        await controller.addHotTask('third');
        expect(controller.hotDone.single.text, 'Call Oleg');
        expect(controller.hotDone.single.done, DateTime(2026, 9, 21, 10, 0));
        expect(controller.hotInProgress.map((t) => t.text), [
          'third',
          'Order profile',
        ]);
      },
    );

    test('the app\'s own saves are not mistaken for outside changes', () async {
      await controller.openVault(tmp.path);
      await controller.addHotTask('one');
      await controller.completeHotTask(controller.hotInProgress.single.id);
      await controller.addHotTask('two');
      await controller.addHotTask('three');
      expect(controller.hotDone, hasLength(1));
      expect(controller.hotInProgress, hasLength(2));
      final saved = parseHotTasks(
        hotFile().readAsStringSync(),
        now: DateTime.now(),
      );
      expect(saved, hasLength(3));
    });

    test(
      'refresh while archiving cannot lose a task completed meanwhile',
      () async {
        Directory('${tmp.path}/_hot').createSync();
        final old = DateTime.now().subtract(const Duration(days: 40));
        hotFile().writeAsStringSync(
          '- [ ] open\n- [x] ancient ✓ ${formatHotStamp(old)}\n',
        );
        await controller.openVault(tmp.path);
        hotFile().writeAsStringSync(
          '- [ ] open\n- [x] ancient again ✓ ${formatHotStamp(old)}\n',
        );
        // Reload (which archives) and a completion race each other.
        final reload = controller.reload();
        final complete = controller.completeHotTask(
          controller.hotInProgress.single.id,
        );
        await Future.wait([reload, complete]);
        await controller.reload();
        expect(controller.hotDone.map((t) => t.text), ['open']);
        final onDisk = hotFile().readAsStringSync();
        expect(onDisk, contains('- [x] open ✓'));
        expect(onDisk, isNot(contains('ancient')));
      },
    );

    test(
      'the archive dialog skips unchecked lines left in archive.md',
      () async {
        Directory('${tmp.path}/_hot').createSync();
        File('${tmp.path}/_hot/archive.md').writeAsStringSync(
          '- [x] real ✓ 2026-07-01 09:00\n- [ ] typed here by hand\n',
        );
        await controller.openVault(tmp.path);
        final archive = await controller.loadHotArchive();
        expect(archive.map((t) => t.text), ['real']);
      },
    );

    test('insertIntoNote appends when no editor is listening', () async {
      await controller.openVault(tmp.path);
      expect(controller.insertIntoNote('42'), isTrue);
      expect(controller.current!.body, '# Note\n42');
      // Flush the debounced save (reload does) and check it reached disk.
      await controller.reload();
      expect(File('${tmp.path}/Note.md').readAsStringSync(), '# Note\n42');
    });

    test('insertIntoNote reports false with no note open', () async {
      File('${tmp.path}/Note.md').deleteSync();
      await controller.openVault(tmp.path);
      expect(controller.insertIntoNote('42'), isFalse);
    });
  });
}
