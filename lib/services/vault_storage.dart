import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/note.dart';

/// File-system backed vault: notes are plain `.md` files inside [root].
///
/// Windows/desktop only for now (dart:io). Sub-folders are treated as
/// "projects"; the top level plus each folder are scanned one level deep.
class VaultStorage {
  final String root;
  VaultStorage(this.root);

  Directory get _dir => Directory(root);

  bool get exists => _dir.existsSync();

  /// All `.md` files in the vault, recursively, skipping dot-folders and
  /// the reserved `_archive` folder.
  Future<List<Note>> loadNotes() async {
    if (!exists) return [];
    final notes = <Note>[];
    await for (final entity in _dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.md')) continue;
      final rel = p.relative(entity.path, from: root);
      if (rel.split(p.separator).any((seg) => seg.startsWith('.') || seg == '_archive')) {
        continue;
      }
      notes.add(await _readFile(entity));
    }
    notes.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return notes;
  }

  Future<Note> _readFile(File f) async {
    final stat = await f.stat();
    return Note(
      path: f.path,
      title: Note.titleFromPath(f.path),
      body: await f.readAsString(),
      modified: stat.modified,
    );
  }

  Future<Note> write(Note note) async {
    final f = File(note.path);
    await f.parent.create(recursive: true);
    await f.writeAsString(note.body);
    final stat = await f.stat();
    return note.copyWith(modified: stat.modified);
  }

  Future<Note> create(String title, {String? subfolder}) async {
    final dir = subfolder == null ? root : p.join(root, subfolder);
    final path = p.join(dir, '$title.md');
    final note = Note(
      path: path,
      title: title,
      body: '# $title\n\n',
      modified: DateTime.now(),
    );
    return write(note);
  }

  Future<Note> rename(Note note, String newTitle) async {
    final newPath = p.join(p.dirname(note.path), '$newTitle.md');
    await File(note.path).rename(newPath);
    return note.copyWith(path: newPath, title: newTitle);
  }

  Future<void> delete(Note note) async {
    final f = File(note.path);
    if (await f.exists()) await f.delete();
  }
}
