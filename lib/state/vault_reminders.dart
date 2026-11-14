part of 'vault_controller.dart';

/// Reminders: per-note, per-line (`{{remind:}}` tags) and the stand-alone
/// calendar events, plus the check that raises the "due" alert. The maps
/// themselves live in [VaultController].
extension VaultReminders on VaultController {
  /// True when the note has an active note-level or line reminder.
  bool hasAnyReminder(Note note) =>
      _reminders.containsKey(note.title) ||
      LineReminders.parseAll(note.body).isNotEmpty;

  Future<void> setReminder(String title, DateTime when) async {
    _reminders[title] = when;
    _notifyIfAlive();
    await _reminderStore?.save(_reminders);
  }

  Future<void> clearReminder(String title) async {
    if (_reminders.remove(title) != null) {
      _notifyIfAlive();
      await _reminderStore?.save(_reminders);
    }
  }

  /// Create a standalone reminder for [when] that isn't tied to any note
  /// (set from the dashboard calendar).
  Future<void> addEvent(String title, DateTime when) async {
    _events.add(
      CalendarEvent(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        when: when,
      ),
    );
    _notifyIfAlive();
    await _calendarStore?.save(_events);
  }

  Future<void> deleteEvent(String id) async {
    if (_events.isEmpty) return;
    final before = _events.length;
    _events = _events.where((e) => e.id != id).toList();
    if (_events.length == before) return;
    _notifyIfAlive();
    await _calendarStore?.save(_events);
  }

  void _checkDueReminders() {
    if (_dueTitle != null) return; // one alert at a time
    final now = DateTime.now();
    for (final e in _reminders.entries) {
      if (e.value.isBefore(now)) {
        _dueTitle = e.key;
        _notifyIfAlive();
        return;
      }
    }
    for (final note in _notes) {
      if (LineReminders.firstDue(note.body, now) != null) {
        _dueTitle = note.title;
        _dueLineNote = note;
        _notifyIfAlive();
        return;
      }
    }
    for (final ev in _events) {
      if (ev.when.isBefore(now)) {
        _dueTitle = ev.title;
        _dueEventId = ev.id;
        _notifyIfAlive();
        return;
      }
    }
  }

  /// Called by the UI after showing the due alert: clears the fired reminder.
  Future<void> dismissDueReminder() async {
    final title = _dueTitle;
    final lineNote = _dueLineNote;
    final eventId = _dueEventId;
    _dueTitle = null;
    _dueLineNote = null;
    _dueEventId = null;
    if (lineNote != null) {
      // The note may have been edited since the alert fired; strip from now.
      final latest = _notes.firstWhere(
        (n) => n.path == lineNote.path,
        orElse: () => lineNote,
      );
      final stripped = LineReminders.stripDue(latest.body, DateTime.now());
      if (stripped != null) {
        _bufferEdit(latest.copyWith(body: stripped));
        await _flushPendingSave();
      }
    } else if (eventId != null) {
      _events.removeWhere((e) => e.id == eventId);
      await _calendarStore?.save(_events);
    } else if (title != null && _reminders.remove(title) != null) {
      await _reminderStore?.save(_reminders);
    }
    _notifyIfAlive();
  }
}
