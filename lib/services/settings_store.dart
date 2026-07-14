import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Per-vault settings persisted to `{vault}/settings.json` so they travel
/// with the vault (e.g. through Google Drive).
class VaultSettings {
  /// 'system' | 'light' | 'dark'.
  final String themeMode;

  /// Background style: 'petrol' | 'honey' | 'sky' | 'sage'.
  final String themeStyle;

  final int accentIndex;

  /// Medallion look: 'ring' | 'fill' | 'tint'.
  final String glyphStyle;

  /// Editor font scale, 1.0 = 100%.
  final double editorScale;

  const VaultSettings({
    this.themeMode = 'system',
    this.themeStyle = 'petrol',
    this.accentIndex = 0,
    this.glyphStyle = 'ring',
    this.editorScale = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'themeStyle': themeStyle,
    'accentIndex': accentIndex,
    'glyphStyle': glyphStyle,
    'editorScale': editorScale,
  };

  factory VaultSettings.fromJson(Map<String, dynamic> j) {
    var mode = (j['themeMode'] as String?) ?? 'system';
    var style = (j['themeStyle'] as String?) ?? 'petrol';
    // Back-compat: earlier builds stored a single preset id in themeMode.
    switch (mode) {
      case 'petrol' || 'neon':
        style = 'petrol';
        mode = 'dark';
      case 'paper':
        style = 'petrol';
        mode = 'light';
      case 'amber':
        style = 'honey';
        mode = 'light';
      case 'mist':
        style = 'sky';
        mode = 'light';
    }
    return VaultSettings(
      themeMode: mode,
      themeStyle: style,
      accentIndex: (j['accentIndex'] as int?) ?? 0,
      glyphStyle: (j['glyphStyle'] as String?) ?? 'ring',
      editorScale: ((j['editorScale'] as num?) ?? 1.0).toDouble(),
    );
  }

  VaultSettings copyWith({
    String? themeMode,
    String? themeStyle,
    int? accentIndex,
    String? glyphStyle,
    double? editorScale,
  }) => VaultSettings(
    themeMode: themeMode ?? this.themeMode,
    themeStyle: themeStyle ?? this.themeStyle,
    accentIndex: accentIndex ?? this.accentIndex,
    glyphStyle: glyphStyle ?? this.glyphStyle,
    editorScale: editorScale ?? this.editorScale,
  );
}

class SettingsStore {
  final String vaultRoot;
  SettingsStore(this.vaultRoot);

  File get _file => File(p.join(vaultRoot, 'settings.json'));

  Future<VaultSettings> load() async {
    try {
      if (!await _file.exists()) return const VaultSettings();
      final data = jsonDecode(await _file.readAsString());
      return VaultSettings.fromJson(data as Map<String, dynamic>);
    } on FormatException {
      return const VaultSettings();
    } on IOException {
      return const VaultSettings();
    }
  }

  Future<void> save(VaultSettings s) async {
    await _file.writeAsString(jsonEncode(s.toJson()));
  }
}

/// App-local settings kept in `~/.bloknot/settings.json` (do NOT travel with
/// the vault): last opened vault path.
class AppSettings {
  /// Test seam: when set, reads/writes go to this file instead of the real
  /// `~/.bloknot/settings.json`. Tests MUST set this to avoid clobbering the
  /// user's actual settings.
  static File? overrideFile;

  static File get _file {
    if (overrideFile != null) return overrideFile!;
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return File(p.join(home, '.bloknot', 'settings.json'));
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      if (!await _file.exists()) return {};
      return jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return {};
    } on IOException {
      return {};
    }
  }

  static Future<String?> lastVault() async =>
      (await _read())['vault'] as String?;

  static Future<void> setLastVault(String path) async {
    final data = await _read();
    data['vault'] = path;
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(data));
  }
}
