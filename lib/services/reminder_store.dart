import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Per-note reminders persisted to `{vault}/reminders.json` so they travel
/// with the vault. Keyed by note title, value is an ISO-8601 timestamp.
class ReminderStore {
  ReminderStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'reminders.json'));

  Future<Map<String, DateTime>> load() async {
    try {
      if (!await _file.exists()) return {};
      final raw = jsonDecode(await _file.readAsString());
      return <String, DateTime>{
        for (final e in (raw as Map<String, dynamic>).entries)
          if (DateTime.tryParse(e.value as String) != null)
            e.key: DateTime.parse(e.value as String),
      };
    } on FormatException {
      return {};
    } on IOException {
      return {};
    }
  }

  Future<void> save(Map<String, DateTime> reminders) async {
    final data = {
      for (final e in reminders.entries) e.key: e.value.toIso8601String(),
    };
    await _file.writeAsString(jsonEncode(data));
  }
}
