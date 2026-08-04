import 'dart:io';

import 'package:path/path.dart' as p;

/// Files copied into `{vault}/attachments/` and referenced from note bodies
/// as standard markdown links: `[name](attachments/name.ext)`.
class AttachmentStore {
  AttachmentStore(this.vaultRoot);

  final String vaultRoot;

  static final linkPattern = RegExp(r'\]\(attachments/([^)]+)\)');

  Directory get _dir => Directory(p.join(vaultRoot, 'attachments'));

  /// Copy [sourcePath] into the attachments folder, de-duplicating the file
  /// name if needed. Returns the stored file name.
  Future<String> add(String sourcePath) async {
    await _dir.create(recursive: true);
    final base = p.basenameWithoutExtension(sourcePath);
    final ext = p.extension(sourcePath);
    var name = p.basename(sourcePath);
    var i = 1;
    while (await File(p.join(_dir.path, name)).exists()) {
      name = '$base (${i++})$ext';
    }
    await File(sourcePath).copy(p.join(_dir.path, name));
    return name;
  }

  /// Attachment file names referenced by [body], in order of appearance.
  static List<String> referencedIn(String body) => linkPattern
      .allMatches(body)
      .map((m) => Uri.decodeComponent(m.group(1)!))
      .toList();

  /// Removes the whole markdown reference (`![name](attachments/name)` or
  /// `[name](attachments/name)`) for [name] from [body], so a deleted
  /// attachment doesn't linger as a broken "missing" entry.
  static String stripLink(String body, String name) {
    final encoded = RegExp.escape(Uri.encodeComponent(name));
    final pattern = RegExp('!?\\[[^\\]]*\\]\\(attachments/$encoded\\)\\n?');
    return body.replaceAll(pattern, '');
  }

  String pathOf(String name) => p.join(_dir.path, name);

  Future<bool> exists(String name) => File(pathOf(name)).exists();

  Future<void> delete(String name) async {
    final f = File(pathOf(name));
    if (await f.exists()) await f.delete();
  }

  /// Open the attachment with the default system application (Windows).
  Future<void> open(String name) async {
    await Process.start('cmd', [
      '/c',
      'start',
      '',
      pathOf(name),
    ], runInShell: false);
  }

  /// Copy the attachment to a user-chosen [destPath] (from a save-location
  /// picker). Returns the saved path.
  Future<String> saveAs(String name, String destPath) async {
    await File(pathOf(name)).copy(destPath);
    return destPath;
  }
}
