import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Per-vault settings persisted to `{vault}/settings.json` so they travel with
/// the vault (e.g. through Google Drive): theme mode + accent index.
class VaultSettings {
  final String themeMode; // 'dark' | 'light'
  final int accentIndex;

  const VaultSettings({this.themeMode = 'dark', this.accentIndex = 0});

  Map<String, dynamic> toJson() =>
      {'themeMode': themeMode, 'accentIndex': accentIndex};

  factory VaultSettings.fromJson(Map<String, dynamic> j) => VaultSettings(
        themeMode: (j['themeMode'] as String?) ?? 'dark',
        accentIndex: (j['accentIndex'] as int?) ?? 0,
      );

  VaultSettings copyWith({String? themeMode, int? accentIndex}) => VaultSettings(
        themeMode: themeMode ?? this.themeMode,
        accentIndex: accentIndex ?? this.accentIndex,
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
    } catch (_) {
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
  static File get _file {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return File(p.join(home, '.bloknot', 'settings.json'));
  }

  static Future<Map<String, dynamic>> _read() async {
    try {
      if (!await _file.exists()) return {};
      return jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<String?> lastVault() async => (await _read())['vault'] as String?;

  static Future<void> setLastVault(String path) async {
    final data = await _read();
    data['vault'] = path;
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(data));
  }
}
