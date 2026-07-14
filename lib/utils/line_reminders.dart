/// Inline (per-line) reminders: a `{{remind:2026-07-13T10:00}}` tag lives
/// right in the note text, so it travels with the note (v1.3 behaviour).
class LineReminders {
  static final tagPattern = RegExp(r'\{\{remind:([^}]+)\}\}');

  static String buildTag(DateTime when) =>
      '{{remind:${when.toIso8601String()}}}';

  /// All valid reminder times found in [body].
  static List<DateTime> parseAll(String body) => tagPattern
      .allMatches(body)
      .map((m) => DateTime.tryParse(m.group(1)!.trim()))
      .whereType<DateTime>()
      .toList();

  /// The earliest tag that is due at [now], or null.
  static DateTime? firstDue(String body, DateTime now) {
    DateTime? due;
    for (final t in parseAll(body)) {
      if (!t.isAfter(now) && (due == null || t.isBefore(due))) due = t;
    }
    return due;
  }

  /// Remove all tags that are due at [now]. Returns null when nothing to do.
  static String? stripDue(String body, DateTime now) {
    var changed = false;
    final result = body.replaceAllMapped(tagPattern, (m) {
      final t = DateTime.tryParse(m.group(1)!.trim());
      if (t != null && !t.isAfter(now)) {
        changed = true;
        return '';
      }
      return m.group(0)!;
    });
    return changed ? result : null;
  }

  /// Rewrite tags as markdown links so the preview shows a themed chip:
  /// `{{remind:...}}` → `[🔔 13.07 10:00](linereminder:0)`.
  static String linkify(String body) {
    var i = 0;
    return body.replaceAllMapped(tagPattern, (m) {
      final t = DateTime.tryParse(m.group(1)!.trim());
      if (t == null) return m.group(0)!;
      final label =
          '🔔 ${_two(t.day)}.${_two(t.month)} '
          '${_two(t.hour)}:${_two(t.minute)}';
      return '[$label](linereminder:${i++})';
    });
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
