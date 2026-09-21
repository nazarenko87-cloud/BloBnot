import 'dart:io';

import 'package:blobnot/services/backup_service.dart';
import 'package:blobnot/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultSettings back-compat', () {
    test('migrates old preset ids stored in themeMode', () {
      final s = VaultSettings.fromJson({
        'themeMode': 'amber',
        'accentIndex': 2,
      });
      expect(s.themeMode, 'light');
      expect(s.themeStyle, 'honey');
      expect(s.accentIndex, 2);
    });

    test('round-trips new fields', () {
      const s = VaultSettings(
        themeMode: 'dark',
        themeStyle: 'sage',
        accentIndex: 3,
        glyphStyle: 'tint',
        editorScale: 1.2,
      );
      final r = VaultSettings.fromJson(s.toJson());
      expect(r.themeStyle, 'sage');
      expect(r.glyphStyle, 'tint');
      expect(r.editorScale, 1.2);
    });
  });

  group('BackupService', () {
    test('zips the vault into Downloads', () async {
      final tmp = await Directory.systemTemp.createTemp('blobnot_bak');
      File('${tmp.path}/A.md').writeAsStringSync('# A');
      Directory('${tmp.path}/proj').createSync();
      File('${tmp.path}/proj/B.md').writeAsStringSync('# B');

      final out = await BackupService.backupVault(tmp.path);
      final f = File(out);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(0));

      f.deleteSync();
      await tmp.delete(recursive: true);
    });
  });
}
