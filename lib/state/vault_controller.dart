import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/note.dart';
import '../services/vault_storage.dart';
import '../services/settings_store.dart';

/// Single source of truth for the open vault: notes, selection, theme.
///
/// Disk writes for the current note are debounced (800ms) so typing does not
/// hit the file system on every keystroke.
class VaultController extends ChangeNotifier {
  VaultStorage? _storage;
  SettingsStore? _settingsStore;

  List<Note> _notes = [];
  Note? _current;
  VaultSettings _settings = const VaultSettings();
  bool _loading = false;

  List<Note> get notes => List.unmodifiable(_notes);
  Note? get current => _current;
  VaultSettings get settings => _settings;
  bool get loading => _loading;
  bool get hasVault => _storage != null;
  String? get vaultRoot => _storage?.root;

  Timer? _saveTimer;

  /// On launch, reopen the last-used vault if it still exists.
  Future<void> bootstrap() async {
    final last = await AppSettings.lastVault();
    if (last != null && VaultStorage(last).exists) {
      await openVault(last);
    }
  }

  Future<void> openVault(String root) async {
    _loading = true;
    notifyListeners();
    _storage = VaultStorage(root);
    _settingsStore = SettingsStore(root);
    _settings = await _settingsStore!.load();
    _notes = await _storage!.loadNotes();
    _current = _notes.isNotEmpty ? _notes.first : null;
    await AppSettings.setLastVault(root);
    _loading = false;
    notifyListeners();
  }

  Future<void> reload() async {
    if (_storage == null) return;
    _notes = await _storage!.loadNotes();
    if (_current != null) {
      _current = _notes.firstWhere(
        (n) => n.path == _current!.path,
        orElse: () => _notes.isNotEmpty ? _notes.first : _current!,
      );
    }
    notifyListeners();
  }

  void select(Note note) {
    _flushPendingSave();
    _current = note;
    notifyListeners();
  }

  /// Update the current note's body in memory and schedule a debounced save.
  void editCurrentBody(String body) {
    if (_current == null) return;
    _current = _current!.copyWith(body: body);
    final idx = _notes.indexWhere((n) => n.path == _current!.path);
    if (idx >= 0) _notes[idx] = _current!;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushPendingSave);
  }

  Future<void> _flushPendingSave() async {
    _saveTimer?.cancel();
    if (_storage == null || _current == null) return;
    final saved = await _storage!.write(_current!);
    _current = saved;
    final idx = _notes.indexWhere((n) => n.path == saved.path);
    if (idx >= 0) _notes[idx] = saved;
  }

  Future<Note> createNote(String title, {String? subfolder}) async {
    final note = await _storage!.create(title, subfolder: subfolder);
    _notes.add(note);
    _notes.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _current = note;
    notifyListeners();
    return note;
  }

  Future<void> deleteNote(Note note) async {
    await _storage!.delete(note);
    _notes.removeWhere((n) => n.path == note.path);
    if (_current?.path == note.path) {
      _current = _notes.isNotEmpty ? _notes.first : null;
    }
    notifyListeners();
  }

  Future<void> setTheme({String? mode, int? accent}) async {
    _settings = _settings.copyWith(themeMode: mode, accentIndex: accent);
    notifyListeners();
    await _settingsStore?.save(_settings);
  }

  @override
  void dispose() {
    _flushPendingSave();
    _saveTimer?.cancel();
    super.dispose();
  }
}
