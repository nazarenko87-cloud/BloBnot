import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/note.dart';
import 'vault_backend.dart';
import 'safe_file.dart';

/// File-system backed vault: notes are plain `.md` files inside [root].
///
/// Desktop (dart:io). Sub-folders are treated as "projects"; the top level
/// plus each folder are scanned one level deep. See [SafVaultStorage] for the
/// Android (SAF) implementation of the same [VaultBackend] contract.
class VaultStorage implements VaultBackend {
  final String root;
  VaultStorage(this.root);

  @override
  String get id => root;

  Directory get _dir => Directory(root);

  bool get exists => _dir.existsSync();

  @override
  Future<bool> available() async => exists;

  /// All `.md` files in the vault, recursively, skipping dot-folders and
  /// the reserved `_archive` folder. Files are read in parallel batches so
  /// opening a cloud-synced vault does not stall on file-at-a-time I/O.
  @override
  Future<List<Note>> loadNotes() async {
    if (!exists) return [];
    final files = <File>[];
    // Walk by hand so reserved folders are never entered: a recursive
    // listing would enumerate every attachment and archived note first and
    // only then throw them away — slow on a cloud-synced drive.
    Future<void> walk(Directory dir) async {
      final subdirs = <Directory>[];
      await for (final entity in dir.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is File) {
          if (!name.startsWith('.') && name.toLowerCase().endsWith('.md')) {
            files.add(entity);
          }
        } else if (entity is Directory) {
          if (!name.startsWith('.') && !_reservedDirs.contains(name)) {
            subdirs.add(entity);
          }
        }
      }
      await Future.wait(subdirs.map(walk));
    }

    await walk(_dir);
    final notes = <Note>[];
    final unreadable = <String>[];
    // One file that cannot be read (locked by the sync client, damaged) is
    // skipped and reported; it must not stop the whole vault from opening.
    Future<Note?> readOrSkip(File f) async {
      try {
        return await _readFile(f);
      } on IOException {
        unreadable.add(Note.titleFromPath(f.path));
        return null;
      }
    }

    const batch = 24;
    for (var i = 0; i < files.length; i += batch) {
      final chunk = files.skip(i).take(batch);
      notes.addAll((await Future.wait(chunk.map(readOrSkip))).nonNulls);
    }
    skipped = unreadable..sort();
    notes.sort((a, b) => a.titleLower.compareTo(b.titleLower));
    return notes;
  }

  /// Titles of notes the last [loadNotes] could not read.
  List<String> skipped = const [];

  Future<Note> _readFile(File f) async {
    final stat = await f.stat();
    return Note(
      path: f.path,
      title: Note.titleFromPath(f.path),
      // Retries a briefly locked file and tolerates a stray invalid byte.
      body: await readTextFile(f) ?? '',
      modified: stat.modified,
    );
  }

  @override
  Future<Note> write(Note note) async {
    final f = File(note.path);
    await _replaceFile(f, note.body);
    final stat = await f.stat();
    return note.copyWith(modified: stat.modified);
  }

  @override
  Future<Note?> readIfChanged(Note note) async {
    final f = File(note.path);
    if (!await f.exists()) return null;
    final stat = await f.stat();
    // Any difference counts, not only "newer": a sync client may keep the
    // other device's (earlier) time on the file it brings down.
    if (stat.modified == note.modified) return null;
    return note.copyWith(body: await f.readAsString(), modified: stat.modified);
  }

  /// Writes [content] to a temp file beside [f] and renames it over [f], so
  /// a crash or a sync client reading mid-write sees the old file or the new
  /// one — never half of it.
  static Future<void> _replaceFile(File f, String content) async {
    await f.parent.create(recursive: true);
    final tmp = File(p.join(f.parent.path, '.${p.basename(f.path)}.tmp'));
    await tmp.writeAsString(content, flush: true);
    try {
      await tmp.rename(f.path);
      return;
    } on FileSystemException {
      // Some file systems will not rename over an existing file; fall back
      // to writing in place rather than failing the save.
    }
    try {
      await f.writeAsString(content, flush: true);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
  }

  @override
  Future<Note> create(String title, {String? subfolder, String? body}) async {
    final dir = subfolder == null ? root : p.join(root, subfolder);
    final path = p.join(dir, '$title.md');
    final note = Note(
      path: path,
      title: title,
      body: body ?? '# $title\n\n',
      modified: DateTime.now(),
    );
    return write(note);
  }

  @override
  Future<Note> rename(Note note, String newTitle) async {
    final newPath = p.join(p.dirname(note.path), '$newTitle.md');
    // A plain rename would silently replace a same-named note on POSIX.
    // Case-only renames are fine: on Windows it is the same file.
    if (newPath.toLowerCase() != note.path.toLowerCase() &&
        File(newPath).existsSync()) {
      throw FileSystemException('A note with this name exists', newPath);
    }
    await File(note.path).rename(newPath);
    return note.copyWith(path: newPath, title: newTitle);
  }

  @override
  Future<void> delete(Note note) async {
    final f = File(note.path);
    if (await f.exists()) await f.delete();
  }

  static const _reservedDirs = {
    '_archive',
    '_templates',
    '_hot',
    'attachments',
    '.history',
  };

  Directory get _templatesDir => Directory(p.join(root, '_templates'));

  /// Template notes from `{vault}/_templates/` (shallow).
  @override
  Future<List<Note>> loadTemplates() async {
    if (!_templatesDir.existsSync()) return [];
    final notes = <Note>[];
    await for (final e in _templatesDir.list(followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.md')) {
        notes.add(await _readFile(e));
      }
    }
    notes.sort((a, b) => a.titleLower.compareTo(b.titleLower));
    return notes;
  }

  /// Project = first-level subfolder of the vault (minus reserved ones).
  @override
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

  @override
  Future<void> createProject(String name) async {
    await Directory(p.join(root, name)).create(recursive: true);
  }

  /// Delete a project folder. Its notes are archived first (soft delete),
  /// then the folder with any leftovers is removed.
  @override
  Future<void> deleteProject(String name) async {
    final dir = Directory(p.join(root, name));
    if (!dir.existsSync()) return;
    // List first, then move: renaming files out of a folder while it is
    // still being listed can skip entries.
    final notes = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.md')) notes.add(e);
    }
    for (final file in notes) {
      await archive(await _readFile(file));
    }
    // Only reached when every note is safely in the archive; a failure
    // above leaves the folder (and the notes not yet moved) in place.
    await dir.delete(recursive: true);
  }

  @override
  Future<void> renameProject(String name, String newName) async {
    final dest = Directory(p.join(root, newName));
    if (dest.existsSync()) {
      throw FileSystemException('A project with this name exists', dest.path);
    }
    await Directory(p.join(root, name)).rename(dest.path);
  }

  /// Project folder a note belongs to ('' when at the vault root).
  @override
  String projectOf(Note note) {
    final rel = p.relative(note.path, from: root);
    final parts = p.split(rel);
    return parts.length > 1 ? parts.first : '';
  }

  Directory get _archiveDir => Directory(p.join(root, '_archive'));

  /// Soft delete: move the note file into `{vault}/_archive/`.
  @override
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
  @override
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
  @override
  Future<void> restore(Note note) async {
    var dest = p.join(root, p.basename(note.path));
    var i = 1;
    while (await File(dest).exists()) {
      dest = p.join(root, '${note.title} ($i).md');
      i++;
    }
    await File(note.path).rename(dest);
  }

  File _fileAt(String relPath) =>
      File(p.joinAll([root, ...relPath.split('/')]));

  @override
  Future<String> readText(String relPath) async {
    final f = _fileAt(relPath);
    return await f.exists() ? f.readAsString() : '';
  }

  @override
  Future<void> writeText(String relPath, String content) =>
      _replaceFile(_fileAt(relPath), content);
}
