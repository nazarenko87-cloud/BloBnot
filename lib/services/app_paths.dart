import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the app keeps its own settings, and where exports land. One place,
/// because each platform answers differently:
///
/// * desktop has a home folder (`USERPROFILE` on Windows, `HOME` elsewhere);
/// * Android and iOS have none — `HOME` is unset, and the fallback `.` is the
///   read-only filesystem root, so writing there failed outright.
class AppPaths {
  static String? get _home {
    if (Platform.isAndroid || Platform.isIOS) return null;
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    return home == null || home.isEmpty ? null : home;
  }

  /// The app's own settings file (last vault, launch password). Does not
  /// travel with the vault.
  static Future<File> settingsFile() async {
    final home = _home;
    if (home != null) return File(p.join(home, '.bloknot', 'settings.json'));
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'settings.json'));
  }

  /// The user's downloads folder, for exports and backups. Uses the system's
  /// answer where there is one — on Linux that is the XDG folder, which is
  /// "Завантаження" or "Загрузки" rather than "Downloads" on a Ukrainian or
  /// Russian desktop. Created if missing.
  static Future<String> downloads() async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } on UnsupportedError {
      dir = null;
    } on MissingPlatformDirectoryException {
      dir = null;
    }
    final path =
        dir?.path ??
        p.join(
          _home ?? (await getApplicationDocumentsDirectory()).path,
          'Downloads',
        );
    await Directory(path).create(recursive: true);
    return path;
  }
}
