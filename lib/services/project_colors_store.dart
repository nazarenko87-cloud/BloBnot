import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'safe_file.dart';

/// Project → colour index, persisted to `{vault}/project_colors.json`
/// (v1.1 feature). Index refers to [kProjectColors] in the UI layer.
class ProjectColorsStore {
  ProjectColorsStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'project_colors.json'));

  Future<Map<String, int>> load() async {
    final raw = await readJsonFile(_file);
    if (raw is! Map) return {};
    final out = <String, int>{};
    for (final e in raw.entries) {
      final key = e.key;
      final value = e.value;
      if (key is String && value is int) out[key] = value;
    }
    return out;
  }

  Future<void> save(Map<String, int> colors) async {
    await writeFileAtomic(_file, jsonEncode(colors));
  }
}
