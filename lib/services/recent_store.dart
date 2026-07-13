import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Recently opened note titles, most-recent first, persisted to
/// `{vault}/recent.json` (v1.1 feature). Capped at [max] entries.
class RecentStore {
  RecentStore(this.vaultRoot);

  final String vaultRoot;
  static const max = 12;

  File get _file => File(p.join(vaultRoot, 'recent.json'));

  Future<List<String>> load() async {
    try {
      if (!await _file.exists()) return [];
      final raw = jsonDecode(await _file.readAsString());
      return (raw as List).whereType<String>().toList();
    } on FormatException {
      return [];
    } on IOException {
      return [];
    }
  }

  Future<void> save(List<String> titles) async {
    await _file.writeAsString(jsonEncode(titles.take(max).toList()));
  }
}
