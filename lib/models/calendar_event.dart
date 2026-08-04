/// A reminder created directly from the dashboard calendar — not tied to
/// any note. Contrast with per-note reminders and `{{remind:}}` line tags,
/// which live on a [Note].
class CalendarEvent {
  final String id;
  final String title;
  final DateTime when;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.when,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'when': when.toIso8601String(),
  };

  static CalendarEvent? fromJson(Map<String, dynamic> j) {
    final when = DateTime.tryParse(j['when'] as String? ?? '');
    final id = j['id'] as String?;
    final title = j['title'] as String?;
    if (when == null || id == null || title == null) return null;
    return CalendarEvent(id: id, title: title, when: when);
  }
}
