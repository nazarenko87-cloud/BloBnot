import 'package:flutter/services.dart';

/// Dart wrapper over the native Android Storage Access Framework channel
/// (`bloknot/saf`). A "saf vault" is identified by a tree URI string that
/// starts with `content://`; all note paths under it are `treeUri||relPath`.
class SafChannel {
  static const _ch = MethodChannel('bloknot/saf');

  /// Prompt the user to pick a folder tree; returns the persisted tree URI or
  /// null if cancelled. The permission survives app restarts.
  static Future<String?> pickTree() async {
    return _ch.invokeMethod<String>('pickTree');
  }

  /// Whether we still hold read/write permission for [treeUri].
  static Future<bool> hasPermission(String treeUri) async {
    return await _ch.invokeMethod<bool>('hasPermission', {'tree': treeUri}) ??
        false;
  }

  /// List markdown files under the tree, recursively. Returns a list of
  /// `{relPath, modified}` maps (relPath uses '/' separators).
  static Future<List<Map<String, dynamic>>> listMarkdown(String treeUri) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listMarkdown', {
      'tree': treeUri,
    });
    return (raw ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Shallow list of `.md` files in one folder (e.g. `_archive`,
  /// `_templates`) that [listMarkdown] skips. Empty [relDir] = vault root.
  static Future<List<Map<String, dynamic>>> listFolder(
    String treeUri,
    String relDir,
  ) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listFolder', {
      'tree': treeUri,
      'path': relDir,
    });
    return (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// First-level subfolder names (projects), minus reserved/dot folders.
  static Future<List<String>> listDirs(String treeUri) async {
    final raw = await _ch.invokeMethod<List<dynamic>>('listDirs', {
      'tree': treeUri,
    });
    return (raw ?? []).map((e) => e as String).toList();
  }

  static Future<String> readFile(String treeUri, String relPath) async {
    return await _ch.invokeMethod<String>('readFile', {
          'tree': treeUri,
          'path': relPath,
        }) ??
        '';
  }

  static Future<void> writeFile(
    String treeUri,
    String relPath,
    String content,
  ) async {
    await _ch.invokeMethod('writeFile', {
      'tree': treeUri,
      'path': relPath,
      'content': content,
    });
  }

  static Future<void> writeBytes(
    String treeUri,
    String relPath,
    Uint8List bytes,
  ) async {
    await _ch.invokeMethod('writeBytes', {
      'tree': treeUri,
      'path': relPath,
      'bytes': bytes,
    });
  }

  static Future<void> delete(String treeUri, String relPath) async {
    await _ch.invokeMethod('delete', {'tree': treeUri, 'path': relPath});
  }

  static Future<void> rename(
    String treeUri,
    String relPath,
    String newRelPath,
  ) async {
    await _ch.invokeMethod('rename', {
      'tree': treeUri,
      'path': relPath,
      'newPath': newRelPath,
    });
  }

  /// Create an (empty) folder at [relPath].
  static Future<void> mkdir(String treeUri, String relPath) async {
    await _ch.invokeMethod('mkdir', {'tree': treeUri, 'path': relPath});
  }
}
