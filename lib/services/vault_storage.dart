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

  static const _reservedDirs = {'_archive', 'attachments', '.history'};

  /// Project = first-level subfolder of the vault (minus reserved ones).
  Future<List<String>> listProjects() async {
    if (!exists) return [];
    final names = <String>[];
    await for (final e in _dir.list(followLinks: false)) {
      if (e is! Directory) continue;
      final name = p.basename(e.path);
      if (name.startsWith('.') || _reservedDirs.contains(name)) continue;
      names.add(name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<void> createProject(String name) async {
    await Directory(p.join(root, name)).create(recursive: true);
  }

  /// Project folder a note belongs to ('' when at the vault root).
  String projectOf(Note note) {
    final rel = p.relative(note.path, from: root);
    final parts = p.split(rel);
    return parts.length > 1 ? parts.first : '';
  }

  Directory get _archiveDir => Directory(p.join(root, '_archive'));

  /// Soft delete: move the note file into `{vault}/_archive/`.
  Future<void> archive(Note note) async {
    await _archiveDir.create(recursive: true);
    var dest = p.join(_archiveDir.path, p.basename(note.path));
    var i = 1;
    while (await File(dest).exists()) {
      dest = p.join(_archiveDir.path, '${note.title} ($i).md');
      i++;
    }
    await File(note.path).rename(dest);
  }

  /// Archived notes (loaded shallowly from `_archive/`).
  Future<List<Note>> loadArchived() async {
    if (!_archiveDir.existsSync()) return [];
    final notes = <Note>[];
    await for (final e in _archiveDir.list(followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.md')) {
        notes.add(await _readFile(e));
      }
    }
    notes.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return notes;
  }

  /// Move an archived note back to the vault root.
  Future<void> restore(Note note) async {
    var dest = p.join(root, p.basename(note.path));
    var i = 1;
    while (await File(dest).exists()) {
      dest = p.join(root, '${note.title} ($i).md');
      i++;
    }
    await File(note.path).rename(dest);
  }
}
