import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/calendar_event.dart';
import 'safe_file.dart';

/// Standalone (not note-linked) reminders created from the dashboard
/// calendar, persisted to `{vault}/calendar_events.json`.
class CalendarEventStore {
  CalendarEventStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'calendar_events.json'));

  Future<List<CalendarEvent>> load() async {
    final raw = await readJsonFile(_file);
    if (raw is! List) return [];
    final events = <CalendarEvent>[];
    for (final item in raw.whereType<Map<String, dynamic>>()) {
      try {
        final event = CalendarEvent.fromJson(item);
        if (event != null) events.add(event);
      } on TypeError {
        // One malformed entry must not hide the rest.
      }
    }
    return events;
  }

  Future<void> save(List<CalendarEvent> events) async {
    await writeFileAtomic(
      _file,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }
}
