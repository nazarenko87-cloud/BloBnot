import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vault_backend.dart';

/// Where per-vault metadata (settings.json, reminders.json, pinned, glyphs, …)
/// is stored.
///
/// On desktop the vault [id] is a real folder, so metadata lives alongside the
/// notes and travels with the vault. On Android the vault is a SAF `content://`
/// tree that `dart:io` cannot touch, so metadata is kept app-private under a
/// per-vault subfolder keyed by a hash of the tree URI.
Future<String> vaultMetaRoot(String id) async {
  if (!isSafId(id)) return id;
  final base = await getApplicationSupportDirectory();
  final key = sha1.convert(utf8.encode(id)).toString().substring(0, 16);
  final dir = Directory(p.join(base.path, 'vaults', key));
  await dir.create(recursive: true);
  return dir.path;
}
