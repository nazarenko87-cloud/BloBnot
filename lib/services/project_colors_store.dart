import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Project → colour index, persisted to `{vault}/project_colors.json`
/// (v1.1 feature). Index refers to [kProjectColors] in the UI layer.
class ProjectColorsStore {
  ProjectColorsStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'project_colors.json'));

  Future<Map<String, int>> load() async {
    try {
      if (!await _file.exists()) return {};
      final raw = jsonDecode(await _file.readAsString());
      return <String, int>{
        for (final e in (raw as Map<String, dynamic>).entries)
          if (e.value is int) e.key: e.value as int,
      };
    } on FormatException {
      return {};
    } on IOException {
      return {};
    }
  }

  Future<void> save(Map<String, int> colors) async {
    await _file.writeAsString(jsonEncode(colors));
  }
}
