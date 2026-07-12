import 'package:blobnot/utils/line_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final past = DateTime(2026, 7, 1, 9, 0);
  final future = DateTime(2026, 12, 31, 18, 30);
  final now = DateTime(2026, 7, 12);

  String tag(DateTime t) => LineReminders.buildTag(t);

  group('LineReminders', () {
    test('parseAll finds valid tags and skips broken ones', () {
      final body = 'a ${tag(past)}\nb {{remind:garbage}}\nc ${tag(future)}';
      expect(LineReminders.parseAll(body), [past, future]);
    });

    test('firstDue returns earliest due tag or null', () {
      expect(
        LineReminders.firstDue('x ${tag(past)} y ${tag(future)}', now),
        past,
      );
      expect(LineReminders.firstDue('x ${tag(future)}', now), isNull);
      expect(LineReminders.firstDue('no tags', now), isNull);
    });

    test('stripDue removes only due tags', () {
      final body = 'do ${tag(past)} later ${tag(future)}';
      final stripped = LineReminders.stripDue(body, now);
      expect(stripped, 'do  later ${tag(future)}');
      // Nothing due → null (no rewrite).
      expect(LineReminders.stripDue('x ${tag(future)}', now), isNull);
    });

    test('linkify renders a chip label with date and time', () {
      final body = 'call mom ${tag(DateTime(2026, 7, 13, 10, 5))}';
      expect(
        LineReminders.linkify(body),
        'call mom [🔔 13.07 10:05](linereminder:0)',
      );
    });
  });
}
