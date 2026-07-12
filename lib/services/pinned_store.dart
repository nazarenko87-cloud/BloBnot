import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Pinned note titles persisted to `{vault}/pinned.json` (a JSON array),
/// matching the original v1.1 format.
class PinnedStore {
  PinnedStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'pinned.json'));

  Future<Set<String>> load() async {
    try {
      if (!await _file.exists()) return {};
      final raw = jsonDecode(await _file.readAsString());
      return (raw as List).whereType<String>().toSet();
    } on FormatException {
      return {};
    } on IOException {
      return {};
    }
  }

  Future<void> save(Set<String> titles) async {
    await _file.writeAsString(jsonEncode(titles.toList()..sort()));
  }
}
