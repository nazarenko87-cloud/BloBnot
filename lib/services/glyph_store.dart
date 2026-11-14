import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'safe_file.dart';

/// Glyph medallions:
/// - `{vault}/glyphs.json` maps tag → glyph (emoji);
/// - `{vault}/glyph_overrides.json` maps note title → glyph (manual pick,
///   wins over tags — v1.3 behaviour).
///
/// Values longer than 4 code units are ignored (protects against the old
/// build's icon-name format in an existing vault).
class GlyphStore {
  GlyphStore(this.vaultRoot);

  final String vaultRoot;

  File get _tagsFile => File(p.join(vaultRoot, 'glyphs.json'));
  File get _overridesFile => File(p.join(vaultRoot, 'glyph_overrides.json'));

  static bool _usable(Object? v) =>
      v is String && v.isNotEmpty && v.length <= 4;

  Future<Map<String, String>> _load(
    File f, {
    bool lowercaseKeys = false,
  }) async {
    final raw = await readJsonFile(f);
    if (raw is! Map) return {};
    final out = <String, String>{};
    for (final e in raw.entries) {
      final key = e.key;
      final value = e.value;
      if (key is! String || !_usable(value)) continue;
      out[lowercaseKeys ? key.toLowerCase() : key] = value as String;
    }
    return out;
  }

  Future<Map<String, String>> loadTagGlyphs() =>
      _load(_tagsFile, lowercaseKeys: true);
  Future<Map<String, String>> loadOverrides() => _load(_overridesFile);

  Future<void> saveTagGlyphs(Map<String, String> glyphs) =>
      writeFileAtomic(_tagsFile, jsonEncode(glyphs));

  Future<void> saveOverrides(Map<String, String> overrides) =>
      writeFileAtomic(_overridesFile, jsonEncode(overrides));
}
