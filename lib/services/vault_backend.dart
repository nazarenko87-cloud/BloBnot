import '../models/note.dart';
import 'saf_vault_storage.dart';
import 'vault_storage.dart';

/// Storage abstraction the [VaultController] talks to. Two implementations:
///
/// * [VaultStorage] — `dart:io` files, used on desktop (Windows/Linux/macOS).
/// * [SafVaultStorage] — Android Storage Access Framework, so the vault can
///   live in a user-picked, cloud-synced folder (e.g. Google Drive).
///
/// A vault is identified by [id]: a filesystem path on desktop, or a `content://`
/// tree URI on Android. [openBackend] picks the right implementation from [id].
abstract interface class VaultBackend {
  /// Vault identifier: a filesystem path or a `content://` tree URI.
  String get id;

  /// Whether the vault is reachable (exists on disk / permission still held).
  Future<bool> available();

  Future<List<Note>> loadNotes();
  Future<Note> write(Note note);
  Future<Note> create(String title, {String? subfolder, String? body});
  Future<Note> rename(Note note, String newTitle);
  Future<void> delete(Note note);
  Future<List<Note>> loadTemplates();
  Future<List<String>> listProjects();
  Future<void> createProject(String name);
  Future<void> deleteProject(String name);

  /// Project folder a note belongs to ('' when at the vault root).
  String projectOf(Note note);

  Future<void> archive(Note note);
  Future<List<Note>> loadArchived();
  Future<void> restore(Note note);
}

/// True when [id] points at an Android SAF tree rather than a local path.
bool isSafId(String id) => id.startsWith('content://');

/// Pick the storage implementation for a vault [id].
VaultBackend openBackend(String id) =>
    isSafId(id) ? SafVaultStorage(id) : VaultStorage(id);

/// SAF note paths are encoded as `treeUri<sep>relPath` so a [Note] keeps a
/// single [Note.path] string while still carrying its tree URI. The separator
/// is a control char (U+0001) that never appears in a URI or a file path.
final String kSafSep = String.fromCharCode(1);

String encodeSafPath(String treeUri, String relPath) =>
    '$treeUri$kSafSep$relPath';

/// The relative path portion of a SAF [Note.path].
String safRelPath(String path) {
  final i = path.indexOf(kSafSep);
  return i < 0 ? path : path.substring(i + 1);
}
