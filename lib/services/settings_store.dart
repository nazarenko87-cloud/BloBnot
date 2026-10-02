import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'app_paths.dart';

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

  /// Edit mode shows formatted text and hides the Markdown marks on every
  /// line except the one being edited.
  final bool livePreview;

  /// Keeps lines at a readable length, centred, on a wide window.
  final bool readableWidth;

  final bool lineNumbers;

  const VaultSettings({
    this.themeMode = 'system',
    this.themeStyle = 'petrol',
    this.accentIndex = 0,
    this.glyphStyle = 'ring',
    this.editorScale = 1.0,
    this.livePreview = true,
    this.readableWidth = true,
    this.lineNumbers = true,
  });

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'themeStyle': themeStyle,
    'accentIndex': accentIndex,
    'glyphStyle': glyphStyle,
    'editorScale': editorScale,
    'livePreview': livePreview,
    'readableWidth': readableWidth,
    'lineNumbers': lineNumbers,
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
      livePreview: (j['livePreview'] as bool?) ?? true,
      readableWidth: (j['readableWidth'] as bool?) ?? true,
      lineNumbers: (j['lineNumbers'] as bool?) ?? true,
    );
  }

  VaultSettings copyWith({
    String? themeMode,
    String? themeStyle,
    int? accentIndex,
    String? glyphStyle,
    double? editorScale,
    bool? livePreview,
    bool? readableWidth,
    bool? lineNumbers,
  }) => VaultSettings(
    themeMode: themeMode ?? this.themeMode,
    themeStyle: themeStyle ?? this.themeStyle,
    accentIndex: accentIndex ?? this.accentIndex,
    glyphStyle: glyphStyle ?? this.glyphStyle,
    editorScale: editorScale ?? this.editorScale,
    livePreview: livePreview ?? this.livePreview,
    readableWidth: readableWidth ?? this.readableWidth,
    lineNumbers: lineNumbers ?? this.lineNumbers,
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

/// App-local settings (they do NOT travel with the vault): the last opened
/// vault. Desktop keeps them in `~/.bloknot/settings.json`; Android and iOS
/// have no home directory to write to, so they use the app's own support
/// folder instead.
class AppSettings {
  /// Test seam: when set, reads/writes go to this file instead of the real
  /// settings file. Tests MUST set this to avoid clobbering the user's own.
  static File? overrideFile;

  static Future<File> _resolve() async =>
      overrideFile ?? await AppPaths.settingsFile();

  static Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _resolve();
      if (!await file.exists()) return {};
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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
    final file = await _resolve();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }
}

/// Small app-local JSON files kept next to [AppSettings] — window placement,
/// open tabs. Each lives in its own file, so two of them saving at the same
/// moment cannot overwrite each other.
class AppState {
  static Future<File> _file(String name) async {
    final settings = await AppSettings._resolve();
    return File(p.join(settings.parent.path, '$name.json'));
  }

  static Future<Object?> read(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    } on IOException {
      return null;
    }
  }

  static Future<void> write(String name, Object? value) async {
    try {
      final file = await _file(name);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(value));
    } on IOException {
      // Losing remembered tabs or window placement is not worth an error.
    }
  }
}
