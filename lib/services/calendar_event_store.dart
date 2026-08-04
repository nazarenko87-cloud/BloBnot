import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/calendar_event.dart';

/// Standalone (not note-linked) reminders created from the dashboard
/// calendar, persisted to `{vault}/calendar_events.json`.
class CalendarEventStore {
  CalendarEventStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'calendar_events.json'));

  Future<List<CalendarEvent>> load() async {
    try {
      if (!await _file.exists()) return [];
      final raw = jsonDecode(await _file.readAsString()) as List<dynamic>;
      return raw
          .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
          .whereType<CalendarEvent>()
          .toList();
    } on FormatException {
      return [];
    } on IOException {
      return [];
    }
  }

  Future<void> save(List<CalendarEvent> events) async {
    await _file.writeAsString(jsonEncode(events.map((e) => e.toJson()).toList()));
  }
}
