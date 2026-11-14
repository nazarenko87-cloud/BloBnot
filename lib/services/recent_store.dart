import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'safe_file.dart';

/// Recently opened note titles, most-recent first, persisted to
/// `{vault}/recent.json` (v1.1 feature). Capped at [max] entries.
class RecentStore {
  RecentStore(this.vaultRoot);

  final String vaultRoot;
  static const max = 12;

  File get _file => File(p.join(vaultRoot, 'recent.json'));

  Future<List<String>> load() async {
    final raw = await readJsonFile(_file);
    return raw is List ? raw.whereType<String>().toList() : [];
  }

  Future<void> save(List<String> titles) async {
    await writeFileAtomic(_file, jsonEncode(titles.take(max).toList()));
  }
}
