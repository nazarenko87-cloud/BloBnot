import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'safe_file.dart';

/// Pinned note titles persisted to `{vault}/pinned.json` (a JSON array),
/// matching the original v1.1 format.
class PinnedStore {
  PinnedStore(this.vaultRoot);

  final String vaultRoot;

  File get _file => File(p.join(vaultRoot, 'pinned.json'));

  Future<Set<String>> load() async {
    final raw = await readJsonFile(_file);
    return raw is List ? raw.whereType<String>().toSet() : {};
  }

  Future<void> save(Set<String> titles) async {
    await writeFileAtomic(_file, jsonEncode(titles.toList()..sort()));
  }
}
