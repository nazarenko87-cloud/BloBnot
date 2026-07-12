import 'package:flutter_test/flutter_test.dart';

import 'package:blobnot/models/note.dart';

Note _note(String body) => Note(
      path: '/vault/x.md',
      title: 'x',
      body: body,
      modified: DateTime(2026),
    );

void main() {
  group('Note.outgoingLinks', () {
    test('extracts plain wiki-links', () {
      expect(_note('see [[Alpha]] and [[Beta]]').outgoingLinks,
          {'Alpha', 'Beta'});
    });

    test('uses target, not alias, for [[Target|alias]]', () {
      expect(_note('[[Target|nice name]]').outgoingLinks, {'Target'});
    });

    test('strips heading anchors [[Note#Heading]]', () {
      expect(_note('[[Note#Section]]').outgoingLinks, {'Note'});
    });

    test('returns empty when there are no links', () {
      expect(_note('plain text').outgoingLinks, isEmpty);
    });
  });

  group('Note.wordCount', () {
    test('counts words and is zero for blank', () {
      expect(_note('one two three').wordCount, 3);
      expect(_note('   ').wordCount, 0);
    });
  });
}
