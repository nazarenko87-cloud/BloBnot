import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'safe_file.dart';

/// Manual project ordering persisted to `{vault}/projectorder.json`
/// (a JSON array of folder names, original v1.0 format).
class ProjectOrderStore {
  ProjectOrderStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'projectorder.json'));

  Future<List<String>> load() async {
    final raw = await readJsonFile(_file);
    return raw is List ? raw.whereType<String>().toList() : [];
  }

  Future<void> save(List<String> order) async {
    await writeFileAtomic(_file, jsonEncode(order));
  }

  /// Sort [projects] by the saved [order]; unknown names keep their
  /// (alphabetical) relative order at the end.
  static List<String> applyOrder(List<String> projects, List<String> order) {
    final indexed = {for (var i = 0; i < order.length; i++) order[i]: i};
    final sorted = [...projects];
    sorted.sort((a, b) {
      final ia = indexed[a] ?? (order.length + projects.indexOf(a));
      final ib = indexed[b] ?? (order.length + projects.indexOf(b));
      return ia.compareTo(ib);
    });
    return sorted;
  }
}
