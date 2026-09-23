import 'package:blobnot/models/note.dart';
import 'package:blobnot/utils/note_table.dart';
import 'package:blobnot/utils/properties.dart';
import 'package:flutter_test/flutter_test.dart';

Note note(String title, String body, {String dir = 'v', int minute = 0}) =>
    Note(
      path: '$dir/$title.md',
      title: title,
      body: body,
      modified: DateTime(2026, 9, 23, 10, minute),
    );

void main() {
  group('parseFrontMatter', () {
    test('reads key: value pairs from the top block', () {
      final fm = parseFrontMatter(
        '---\nmanager: Олег\nstatus: needs fixes\nscore: 4\n---\n# Report\n',
      );
      expect(fm.hasBlock, isTrue);
      expect(fm.lineCount, 5);
      expect(fm.properties, {
        'manager': 'Олег',
        'status': 'needs fixes',
        'score': '4',
      });
    });

    test('a note without the block has no fields', () {
      expect(
        parseFrontMatter('# Just a note\n---\nhr later').hasBlock,
        isFalse,
      );
      expect(parseFrontMatter('').properties, isEmpty);
    });

    test('an unclosed block is not front matter', () {
      expect(parseFrontMatter('---\nkey: v\n# no end').hasBlock, isFalse);
    });

    test('quotes are removed and odd lines ignored', () {
      final fm = parseFrontMatter(
        '---\ntitle: "  spaced "\n# comment\n- list item\nok: yes\n---',
      );
      expect(fm.properties, {'title': '  spaced ', 'ok': 'yes'});
    });

    test('Windows line endings work', () {
      final fm = parseFrontMatter('---\r\nstatus: done\r\n---\r\nbody');
      expect(fm.properties, {'status': 'done'});
    });
  });

  group('setProperty', () {
    test('creates the block when there is none', () {
      expect(
        setProperty('# Note\ntext', 'status', 'open'),
        '---\nstatus: open\n---\n# Note\ntext',
      );
    });

    test('replaces a value in place, keeping the key spelling', () {
      final out = setProperty(
        '---\nStatus: open\nscore: 3\n---\n# N',
        'status',
        'done',
      );
      expect(out, '---\nStatus: done\nscore: 3\n---\n# N');
    });

    test('adds a new key at the end of the block', () {
      expect(
        setProperty('---\na: 1\n---\nbody', 'b', '2'),
        '---\na: 1\nb: 2\n---\nbody',
      );
    });

    test('an empty value removes the field, then the empty block', () {
      final one = setProperty('---\na: 1\nb: 2\n---\nbody', 'a', '');
      expect(one, '---\nb: 2\n---\nbody');
      expect(setProperty(one, 'b', ' '), 'body');
    });

    test('never touches lines it does not understand', () {
      final out = setProperty(
        '---\n# keep me\ntags: [a, b]\nx: 1\n---\n',
        'x',
        '2',
      );
      expect(out, '---\n# keep me\ntags: [a, b]\nx: 2\n---\n');
    });

    test('multi-line and comment-like values stay on one safe line', () {
      final out = setProperty('', 'note', 'two\nlines');
      expect(parseFrontMatter(out).properties['note'], 'two lines');
      final hash = setProperty('', 'tag', '#urgent');
      expect(parseFrontMatter(hash).properties['tag'], '#urgent');
    });

    test('stripFrontMatter leaves only the text', () {
      expect(stripFrontMatter('---\na: 1\n---\n# Hi'), '# Hi');
      expect(stripFrontMatter('# Hi'), '# Hi');
    });

    test('Note exposes its fields', () {
      expect(note('R', '---\nmanager: Oleg\n---\n').properties, {
        'manager': 'Oleg',
      });
    });
  });

  group('compareFieldValues', () {
    test('numbers by value, text alphabetically, empty last', () {
      final values = ['10', '9', '', 'b', 'A', '2,5', null];
      values.sort(compareFieldValues);
      expect(values, ['2,5', '9', '10', 'A', 'b', '', null]);
    });
  });

  group('queryNotes', () {
    String project(Note n) =>
        n.path.split('/').length > 2 ? n.path.split('/')[1] : '';
    final notes = [
      note(
        'Report Oleg',
        '---\nmanager: Oleg\nstatus: needs fixes\nscore: 3\n---\n',
        minute: 1,
      ),
      note(
        'Report Ivan',
        '---\nmanager: Ivan\nstatus: ok\nscore: 5\n---\n',
        minute: 2,
      ),
      note(
        'Strip 24V',
        '---\nproduct: LED strip\nprice: 120\n---\n',
        dir: 'v/Products',
        minute: 3,
      ),
      note('Plain', '# no fields', minute: 4),
    ];

    test('only notes with fields by default, newest first', () {
      final rows = queryNotes(notes, const TableQuery(), project);
      expect(rows.map((n) => n.title), [
        'Strip 24V',
        'Report Ivan',
        'Report Oleg',
      ]);
    });

    test('all notes when asked', () {
      final rows = queryNotes(
        notes,
        const TableQuery(onlyWithFields: false),
        project,
      );
      expect(rows, hasLength(4));
    });

    test('filters by exact value, case-insensitively', () {
      final rows = queryNotes(
        notes,
        const TableQuery(filters: {'status': 'NEEDS FIXES'}),
        project,
      );
      expect(rows.single.title, 'Report Oleg');
    });

    test('free text searches titles and values', () {
      expect(
        queryNotes(notes, const TableQuery(text: 'ivan'), project).single.title,
        'Report Ivan',
      );
      expect(
        queryNotes(notes, const TableQuery(text: 'led'), project).single.title,
        'Strip 24V',
      );
    });

    test('sorts a field numerically, notes without it last', () {
      final asc = queryNotes(
        notes,
        const TableQuery(sortBy: 'score', ascending: true),
        project,
      );
      expect(asc.map((n) => n.title), [
        'Report Oleg',
        'Report Ivan',
        'Strip 24V',
      ]);
      final desc = queryNotes(
        notes,
        const TableQuery(sortBy: 'score', ascending: false),
        project,
      );
      expect(desc.map((n) => n.title), [
        'Report Ivan',
        'Report Oleg',
        'Strip 24V',
      ]);
    });

    test('filters by project folder', () {
      final rows = queryNotes(
        notes,
        const TableQuery(project: 'Products'),
        project,
      );
      expect(rows.single.title, 'Strip 24V');
    });
  });
}
