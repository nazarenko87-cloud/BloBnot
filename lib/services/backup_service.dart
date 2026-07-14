import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Zips the whole vault (notes, attachments, service jsons) into
/// `~/Downloads/BloknotVault-backup-<stamp>.zip`. Returns the archive path.
class BackupService {
  static Future<String> backupVault(String vaultRoot) async {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}';
    final out = p.join(
      home,
      'Downloads',
      '${p.basename(vaultRoot)}-backup-$stamp.zip',
    );

    final encoder = ZipFileEncoder()..create(out);
    final dir = Directory(vaultRoot);
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: vaultRoot);
      await encoder.addFile(e, rel.replaceAll('\\', '/'));
    }
    encoder.closeSync();
    return out;
  }
}
