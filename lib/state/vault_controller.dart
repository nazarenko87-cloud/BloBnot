import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../services/password_store.dart';
import '../services/reminder_store.dart';
import '../services/settings_store.dart';
import '../services/vault_storage.dart';

/// Single source of truth for the open vault: notes, selection, theme,
/// reminders and the launch-password lock.
///
/// Disk writes for the current note are debounced (800ms) so typing does not
/// hit the file system on every keystroke.
class VaultController extends ChangeNotifier {
  VaultController({PasswordStore? passwordStore})
      : passwordStore = passwordStore ?? PasswordStore();

  final PasswordStore passwordStore;

  VaultStorage? _storage;
  SettingsStore? _settingsStore;
  ReminderStore? _reminderStore;

  List<Note> _notes = [];
  Note? _current;
  VaultSettings _settings = const VaultSettings();
  bool _loading = false;
  bool _locked = false;
  Map<String, DateTime> _reminders = {};

  /// Title of a reminder that just came due — the UI shows it and calls
  /// [dismissDueReminder]. Null when nothing is due.
  String? _dueTitle;

  List<Note> get notes => List.unmodifiable(_notes);
  Note? get current => _current;
  VaultSettings get settings => _settings;
  bool get loading => _loading;
  bool get hasVault => _storage != null;
  String? get vaultRoot => _storage?.root;
  bool get locked => _locked;
  String? get dueReminderTitle => _dueTitle;

  DateTime? reminderFor(String title) => _reminders[title];

  Timer? _saveTimer;
  Timer? _reminderTimer;

  /// On launch: engage the lock if a password is set, then reopen the
  /// last-used vault if it still exists.
  Future<void> bootstrap() async {
    await refreshLock();
    final last = await AppSettings.lastVault();
    if (last != null && VaultStorage(last).exists) {
      await openVault(last);
    }
  }

  ({String salt, String hash})? _pwRecord;

  /// Engage the lock when a password is currently set. Caches the salt+hash
  /// so [unlock] can verify synchronously (no disk I/O per attempt).
  Future<void> refreshLock() async {
    _pwRecord = await passwordStore.load();
    _locked = _pwRecord != null;
    notifyListeners();
  }

  bool unlock(String password) {
    final rec = _pwRecord;
    if (rec != null && PasswordStore.hashOf(password, rec.salt) != rec.hash) {
      return false;
    }
    _locked = false;
    notifyListeners();
    return true;
  }

  Future<void> openVault(String root) async {
    _loading = true;
    notifyListeners();
    _storage = VaultStorage(root);
    _settingsStore = SettingsStore(root);
    _reminderStore = ReminderStore(root);
    _settings = await _settingsStore!.load();
    _reminders = await _reminderStore!.load();
    _notes = await _storage!.loadNotes();
    _current = _notes.isNotEmpty ? _notes.first : null;
    await AppSettings.setLastVault(root);
    _loading = false;
    _reminderTimer?.cancel();
    _reminderTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkDueReminders(),
    );
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
    // v1.3 behaviour: opening a note after its reminder passed clears it.
    final due = _reminders[note.title];
    if (due != null && due.isBefore(DateTime.now())) {
      _reminders.remove(note.title);
      unawaited(_reminderStore?.save(_reminders));
    }
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
    _notes.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    _current = note;
    notifyListeners();
    return note;
  }

  Future<void> deleteNote(Note note) async {
    await _storage!.delete(note);
    _notes.removeWhere((n) => n.path == note.path);
    if (_reminders.remove(note.title) != null) {
      await _reminderStore?.save(_reminders);
    }
    if (_current?.path == note.path) {
      _current = _notes.isNotEmpty ? _notes.first : null;
    }
    notifyListeners();
  }

  Future<void> setReminder(String title, DateTime when) async {
    _reminders[title] = when;
    notifyListeners();
    await _reminderStore?.save(_reminders);
  }

  Future<void> clearReminder(String title) async {
    if (_reminders.remove(title) != null) {
      notifyListeners();
      await _reminderStore?.save(_reminders);
    }
  }

  void _checkDueReminders() {
    if (_dueTitle != null) return; // one alert at a time
    final now = DateTime.now();
    for (final e in _reminders.entries) {
      if (e.value.isBefore(now)) {
        _dueTitle = e.key;
        notifyListeners();
        return;
      }
    }
  }

  /// Called by the UI after showing the due alert: clears the fired reminder.
  Future<void> dismissDueReminder() async {
    final title = _dueTitle;
    _dueTitle = null;
    if (title != null && _reminders.remove(title) != null) {
      await _reminderStore?.save(_reminders);
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
    _reminderTimer?.cancel();
    super.dispose();
  }
}
