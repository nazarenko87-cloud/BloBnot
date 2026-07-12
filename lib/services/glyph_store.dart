import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

  static bool _usable(Object? v) => v is String && v.isNotEmpty && v.length <= 4;

  Future<Map<String, String>> _load(File f, {bool lowercaseKeys = false}) async {
    try {
      if (!await f.exists()) return {};
      final raw = jsonDecode(await f.readAsString());
      return <String, String>{
        for (final e in (raw as Map<String, dynamic>).entries)
          if (_usable(e.value))
            (lowercaseKeys ? e.key.toLowerCase() : e.key): e.value as String,
      };
    } on FormatException {
      return {};
    } on IOException {
      return {};
    }
  }

  Future<Map<String, String>> loadTagGlyphs() =>
      _load(_tagsFile, lowercaseKeys: true);
  Future<Map<String, String>> loadOverrides() => _load(_overridesFile);

  Future<void> saveTagGlyphs(Map<String, String> glyphs) =>
      _tagsFile.writeAsString(jsonEncode(glyphs));

  Future<void> saveOverrides(Map<String, String> overrides) =>
      _overridesFile.writeAsString(jsonEncode(overrides));
}
