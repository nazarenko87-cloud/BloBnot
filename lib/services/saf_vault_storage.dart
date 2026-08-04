import '../models/note.dart';
import 'saf_channel.dart';
import 'vault_backend.dart';

/// Android Storage Access Framework vault: notes are `.md` files inside a
/// user-picked, persisted tree URI (so the vault can live in a cloud-synced
/// folder like Google Drive). Note paths are encoded `treeUri<sep>relPath`
/// (see [encodeSafPath] / [safRelPath]); [relPath] segments use '/'.
class SafVaultStorage implements VaultBackend {
  SafVaultStorage(this.treeUri);

  /// The persisted `content://` tree URI.
  final String treeUri;

  @override
  String get id => treeUri;

  @override
  Future<bool> available() => SafChannel.hasPermission(treeUri);

  static const _archive = '_archive';
  static const _templates = '_templates';

  String _basename(String rel) => rel.split('/').last;
  String _titleOf(String rel) {
    final name = _basename(rel);
    return name.toLowerCase().endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
  }

  Note _note(String rel, String body, int modifiedMs) => Note(
    path: encodeSafPath(treeUri, rel),
    title: _titleOf(rel),
    body: body,
    modified: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
  );

  /// Read many notes in bounded-parallel batches so a large vault does not
  /// fire hundreds of channel calls at once.
  Future<List<Note>> _readAll(List<Map<String, dynamic>> entries) async {
    final notes = <Note>[];
    const batch = 16;
    for (var i = 0; i < entries.length; i += batch) {
      final chunk = entries.skip(i).take(batch);
      notes.addAll(
        await Future.wait(
          chunk.map((e) async {
            final rel = e['relPath'] as String;
            final body = await SafChannel.readFile(treeUri, rel);
            return _note(rel, body, (e['modified'] as num?)?.toInt() ?? 0);
          }),
        ),
      );
    }
    return notes;
  }

  @override
  Future<List<Note>> loadNotes() async {
    final entries = await SafChannel.listMarkdown(treeUri);
    final notes = await _readAll(entries);
    notes.sort((a, b) => a.titleLower.compareTo(b.titleLower));
    return notes;
  }

  @override
  Future<Note> write(Note note) async {
    final rel = safRelPath(note.path);
    await SafChannel.writeFile(treeUri, rel, note.body);
    return note.copyWith(modified: DateTime.now());
  }

  @override
  Future<Note> create(String title, {String? subfolder, String? body}) async {
    final rel = (subfolder == null || subfolder.isEmpty)
        ? '$title.md'
        : '$subfolder/$title.md';
    final text = body ?? '# $title\n\n';
    await SafChannel.writeFile(treeUri, rel, text);
    return _note(rel, text, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Future<Note> rename(Note note, String newTitle) async {
    final rel = safRelPath(note.path);
    final slash = rel.lastIndexOf('/');
    final dir = slash < 0 ? '' : rel.substring(0, slash + 1);
    final newRel = '$dir$newTitle.md';
    await SafChannel.rename(treeUri, rel, newRel);
    return note.copyWith(path: encodeSafPath(treeUri, newRel), title: newTitle);
  }

  @override
  Future<void> delete(Note note) =>
      SafChannel.delete(treeUri, safRelPath(note.path));

  @override
  Future<List<Note>> loadTemplates() async {
    final entries = await SafChannel.listFolder(treeUri, _templates);
    final notes = await _readAll(
      entries
          .map((e) => {...e, 'relPath': '$_templates/${e['relPath']}'})
          .toList(),
    );
    notes.sort((a, b) => a.titleLower.compareTo(b.titleLower));
    return notes;
  }

  @override
  Future<List<String>> listProjects() async {
    final dirs = await SafChannel.listDirs(treeUri);
    dirs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return dirs;
  }

  @override
  Future<void> createProject(String name) => SafChannel.mkdir(treeUri, name);

  @override
  Future<void> deleteProject(String name) async {
    // Archive the project's notes first (soft delete), then drop the folder.
    final all = await SafChannel.listMarkdown(treeUri);
    for (final e in all) {
      final rel = e['relPath'] as String;
      if (rel == '$name/${_basename(rel)}' || rel.startsWith('$name/')) {
        final body = await SafChannel.readFile(treeUri, rel);
        await archive(_note(rel, body, 0));
      }
    }
    await SafChannel.delete(treeUri, name);
  }

  @override
  String projectOf(Note note) {
    final rel = safRelPath(note.path);
    final i = rel.indexOf('/');
    return i < 0 ? '' : rel.substring(0, i);
  }

  @override
  Future<void> archive(Note note) async {
    final rel = safRelPath(note.path);
    final body = await SafChannel.readFile(treeUri, rel);
    final dest = await _uniqueName(_archive, note.title);
    await SafChannel.writeFile(treeUri, '$_archive/$dest', body);
    await SafChannel.delete(treeUri, rel);
  }

  @override
  Future<List<Note>> loadArchived() async {
    final entries = await SafChannel.listFolder(treeUri, _archive);
    final notes = await _readAll(
      entries.map((e) => {...e, 'relPath': '$_archive/${e['relPath']}'}).toList(),
    );
    notes.sort((a, b) => a.titleLower.compareTo(b.titleLower));
    return notes;
  }

  @override
  Future<void> restore(Note note) async {
    final rel = safRelPath(note.path);
    final body = await SafChannel.readFile(treeUri, rel);
    final dest = await _uniqueName('', note.title);
    await SafChannel.writeFile(treeUri, dest, body);
    await SafChannel.delete(treeUri, rel);
  }

  /// A `<title>.md` name in [relDir] that doesn't collide, appending ` (n)`.
  Future<String> _uniqueName(String relDir, String title) async {
    final existing = (await SafChannel.listFolder(treeUri, relDir))
        .map((e) => (e['relPath'] as String).toLowerCase())
        .toSet();
    var name = '$title.md';
    var i = 1;
    while (existing.contains(name.toLowerCase())) {
      name = '$title ($i).md';
      i++;
    }
    return name;
  }
}
