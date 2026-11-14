import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'safe_file.dart';

/// Per-note reminders persisted to `{vault}/reminders.json` so they travel
/// with the vault. Keyed by note title, value is an ISO-8601 timestamp.
class ReminderStore {
  ReminderStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'reminders.json'));

  /// Throws [UnreadableFileException] when the file exists but cannot be
  /// read — never returns "no reminders" for a file that is merely locked.
  Future<Map<String, DateTime>> load() async {
    final raw = await readJsonFile(_file);
    if (raw is! Map) return {};
    final out = <String, DateTime>{};
    for (final e in raw.entries) {
      final key = e.key;
      final value = e.value;
      if (key is! String || value is! String) continue;
      final when = DateTime.tryParse(value);
      if (when != null) out[key] = when;
    }
    return out;
  }

  Future<void> save(Map<String, DateTime> reminders) async {
    final data = {
      for (final e in reminders.entries) e.key: e.value.toIso8601String(),
    };
    await writeFileAtomic(_file, jsonEncode(data));
  }
}
