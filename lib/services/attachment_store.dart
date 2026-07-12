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

  String pathOf(String name) => p.join(_dir.path, name);

  Future<bool> exists(String name) => File(pathOf(name)).exists();

  Future<void> delete(String name) async {
    final f = File(pathOf(name));
    if (await f.exists()) await f.delete();
  }

  /// Open the attachment with the default system application (Windows).
  Future<void> open(String name) async {
    await Process.start(
      'cmd',
      ['/c', 'start', '', pathOf(name)],
      runInShell: false,
    );
  }
}
