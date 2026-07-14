import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../services/password_store.dart';
import '../services/glyph_store.dart';
import '../services/pinned_store.dart';
import '../services/project_colors_store.dart';
import '../services/project_order_store.dart';
import '../services/recent_store.dart';
import '../services/reminder_store.dart';
import '../services/settings_store.dart';
import '../services/vault_storage.dart';
import '../utils/line_reminders.dart';

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
  PinnedStore? _pinnedStore;

  List<Note> _notes = [];
  Note? _current;
  VaultSettings _settings = const VaultSettings();
  bool _loading = false;
  bool _locked = false;
  Map<String, DateTime> _reminders = {};
  Set<String> _pinned = {};
  List<String> _projects = [];
  Map<String, int> _projectColors = {};
  ProjectColorsStore? _projectColorsStore;
  GlyphStore? _glyphStore;
  Map<String, String> _tagGlyphs = {};
  Map<String, String> _glyphOverrides = {};
  ProjectOrderStore? _projectOrderStore;
  List<String> _projectOrder = [];
  RecentStore? _recentStore;
  List<String> _recent = [];

  /// Paths of notes open as tabs, in tab order.
  final List<String> _openPaths = [];

  /// Title of a reminder that just came due — the UI shows it and calls
  /// [dismissDueReminder]. Null when nothing is due.
  String? _dueTitle;

  /// When the due alert came from a `{{remind:}}` tag, the note it lives in
  /// (dismissing strips the due tags from that note's body).
  Note? _dueLineNote;

  List<Note> get notes => List.unmodifiable(_notes);
  Note? get current => _current;
  VaultSettings get settings => _settings;
  bool get loading => _loading;
  bool get hasVault => _storage != null;
  String? get vaultRoot => _storage?.root;
  bool get locked => _locked;
  String? get dueReminderTitle => _dueTitle;

  DateTime? reminderFor(String title) => _reminders[title];
  bool isPinned(String title) => _pinned.contains(title);
  List<String> get projects =>
      List.unmodifiable(ProjectOrderStore.applyOrder(_projects, _projectOrder));

  /// Recently opened notes (most-recent first) that still exist.
  List<Note> get recentNotes {
    final byTitle = {for (final n in _notes) n.title: n};
    return [
      for (final t in _recent)
        if (byTitle[t] != null) byTitle[t]!,
    ];
  }

  /// Notes currently open as tabs, in tab order.
  List<Note> get openTabs {
    final byPath = {for (final n in _notes) n.path: n};
    return [
      for (final p in _openPaths)
        if (byPath[p] != null) byPath[p]!,
    ];
  }

  void closeTab(String path) {
    if (!_openPaths.remove(path)) return;
    if (_current?.path == path) {
      final next = _openPaths.isNotEmpty ? _openPaths.last : null;
      Note? found;
      if (next != null) {
        for (final n in _notes) {
          if (n.path == next) {
            found = n;
            break;
          }
        }
      }
      // _notes.first as a fallback would throw StateError on an empty vault.
      _current = found ?? (_notes.isNotEmpty ? _notes.first : null);
    }
    notifyListeners();
  }

  String projectOf(Note note) => _storage?.projectOf(note) ?? '';
  int? colorOf(String project) => _projectColors[project];

  /// Glyph medallion for a note: manual override wins, then the first
  /// body tag that has a mapped glyph, else null (letter fallback in UI).
  String? glyphFor(Note note) {
    final manual = _glyphOverrides[note.title];
    if (manual != null) return manual;
    for (final tag in note.tags) {
      final g = _tagGlyphs[tag];
      if (g != null) return g;
    }
    return null;
  }

  Future<void> setNoteGlyph(String title, String? glyph) async {
    if (glyph == null || glyph.isEmpty) {
      _glyphOverrides.remove(title);
    } else {
      _glyphOverrides[title] = glyph;
    }
    notifyListeners();
    await _glyphStore?.saveOverrides(_glyphOverrides);
  }

  Future<void> setTagGlyph(String tag, String? glyph) async {
    if (glyph == null || glyph.isEmpty) {
      _tagGlyphs.remove(tag.toLowerCase());
    } else {
      _tagGlyphs[tag.toLowerCase()] = glyph;
    }
    notifyListeners();
    await _glyphStore?.saveTagGlyphs(_tagGlyphs);
  }

  /// [newIndex] is already adjusted for the removed item (onReorderItem).
  Future<void> reorderProjects(int oldIndex, int newIndex) async {
    final ordered = [...projects];
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIndex, moved);
    _projectOrder = ordered;
    notifyListeners();
    await _projectOrderStore?.save(_projectOrder);
  }

  Future<void> setProjectColor(String project, int? colorIndex) async {
    if (colorIndex == null) {
      _projectColors.remove(project);
    } else {
      _projectColors[project] = colorIndex;
    }
    notifyListeners();
    await _projectColorsStore?.save(_projectColors);
  }

  /// Notes whose body wiki-links to [title] (case-insensitive).
  List<Note> backlinksTo(String title) {
    final target = title.toLowerCase();
    return _notes
        .where(
          (n) =>
              n.title.toLowerCase() != target &&
              n.outgoingLinks.any((l) => l.toLowerCase() == target),
        )
        .toList();
  }

  Timer? _saveTimer;
  Timer? _reminderTimer;

  /// True while an edit is buffered but not yet written to disk.
  bool _dirty = false;
  bool get isDirty => _dirty;

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

  /// Re-engage the lock (e.g. when hiding to tray) if a password is set.
  void lockNow() {
    if (_pwRecord == null) return;
    _locked = true;
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
    _pinnedStore = PinnedStore(root);
    _projectColorsStore = ProjectColorsStore(root);
    _recentStore = RecentStore(root);
    _openPaths.clear();
    _glyphStore = GlyphStore(root);
    _projectOrderStore = ProjectOrderStore(root);
    _settings = await _settingsStore!.load();
    _reminders = await _reminderStore!.load();
    _pinned = await _pinnedStore!.load();
    _projectColors = await _projectColorsStore!.load();
    _tagGlyphs = await _glyphStore!.loadTagGlyphs();
    _glyphOverrides = await _glyphStore!.loadOverrides();
    _projectOrder = await _projectOrderStore!.load();
    _recent = await _recentStore!.load();
    _projects = await _storage!.listProjects();
    _notes = await _storage!.loadNotes();
    _current = _notes.isNotEmpty ? _notes.first : null;
    if (_current != null) _openPaths.add(_current!.path);
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
    _projects = await _storage!.listProjects();
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
    _touchRecent(note);
    if (!_openPaths.contains(note.path)) _openPaths.add(note.path);
    final now = DateTime.now();
    // v1.3 behaviour: opening a note after its reminder passed clears it —
    // both the note-level reminder and any overdue {{remind:}} line tags.
    final due = _reminders[note.title];
    if (due != null && due.isBefore(now)) {
      _reminders.remove(note.title);
      unawaited(_reminderStore?.save(_reminders));
    }
    final stripped = LineReminders.stripDue(note.body, now);
    if (stripped != null) {
      _current = note.copyWith(body: stripped);
      final idx = _notes.indexWhere((n) => n.path == note.path);
      if (idx >= 0) _notes[idx] = _current!;
      unawaited(_storage?.write(_current!));
    }
    notifyListeners();
  }

  /// Update the current note's body in memory and schedule a debounced save.
  void editCurrentBody(String body) {
    if (_current == null) return;
    _current = _current!.copyWith(body: body);
    final idx = _notes.indexWhere((n) => n.path == _current!.path);
    if (idx >= 0) _notes[idx] = _current!;
    _dirty = true;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushPendingSave);
  }

  Future<void> _flushPendingSave() async {
    _saveTimer?.cancel();
    if (!_dirty || _storage == null || _current == null) return;
    _dirty = false;
    final saved = await _storage!.write(_current!);
    _current = saved;
    final idx = _notes.indexWhere((n) => n.path == saved.path);
    if (idx >= 0) _notes[idx] = saved;
    notifyListeners(); // flip the save indicator back to "Saved"
  }

  /// Templates are `.md` files in `{vault}/_templates/`.
  Future<List<Note>> loadTemplates() => _storage!.loadTemplates();

  Future<Note> createNote(
    String title, {
    String? subfolder,
    String? body,
  }) async {
    final note = await _storage!.create(
      title,
      subfolder: subfolder,
      body: body,
    );
    _notes.add(note);
    _notes.sort((a, b) => a.titleLower.compareTo(b.titleLower));
    _current = note;
    _openPaths.add(note.path);
    _touchRecent(note);
    notifyListeners();
    return note;
  }

  Future<void> deleteNote(Note note) async {
    await _storage!.delete(note);
    _notes.removeWhere((n) => n.path == note.path);
    await _forgetNoteBookkeeping(note);
    if (_current?.path == note.path) {
      _current = _notes.isNotEmpty ? _notes.first : null;
    }
    notifyListeners();
  }

  /// Drop every title/path-keyed record for a note that is leaving the vault
  /// (deleted or archived): open tabs, recents, pin, note-level reminder,
  /// manual glyph override. Without this a note recreated with the same
  /// title would silently inherit stale pin/glyph/reminder state.
  Future<void> _forgetNoteBookkeeping(Note note) async {
    _openPaths.remove(note.path);
    _recent.remove(note.title);
    if (_pinned.remove(note.title)) await _pinnedStore?.save(_pinned);
    if (_reminders.remove(note.title) != null) {
      await _reminderStore?.save(_reminders);
    }
    if (_glyphOverrides.remove(note.title) != null) {
      await _glyphStore?.saveOverrides(_glyphOverrides);
    }
  }

  Future<void> createProject(String name) async {
    await _storage!.createProject(name);
    _projects = await _storage!.listProjects();
    notifyListeners();
  }

  /// Delete a project folder; its notes go to the archive first.
  Future<void> deleteProject(String name) async {
    await _flushPendingSave();
    await _storage!.deleteProject(name);
    _projectColors.remove(name);
    _projectOrder.remove(name);
    await _projectColorsStore?.save(_projectColors);
    await _projectOrderStore?.save(_projectOrder);
    await reload();
    if (_current != null && !_notes.any((n) => n.path == _current!.path)) {
      _current = _notes.isNotEmpty ? _notes.first : null;
      notifyListeners();
    }
  }

  /// True when the note has an active note-level or line reminder.
  bool hasAnyReminder(Note note) =>
      _reminders.containsKey(note.title) ||
      LineReminders.parseAll(note.body).isNotEmpty;

  Future<void> togglePin(String title) async {
    if (!_pinned.remove(title)) _pinned.add(title);
    notifyListeners();
    await _pinnedStore?.save(_pinned);
  }

  /// Soft delete: move to `_archive/` and drop pin/reminder/glyph bookkeeping.
  Future<void> archiveNote(Note note) async {
    await _flushPendingSave();
    await _storage!.archive(note);
    _notes.removeWhere((n) => n.path == note.path);
    await _forgetNoteBookkeeping(note);
    if (_current?.path == note.path) {
      _current = _notes.isNotEmpty ? _notes.first : null;
    }
    notifyListeners();
  }

  Future<List<Note>> loadArchived() => _storage!.loadArchived();

  Future<void> restoreArchived(Note note) async {
    await _storage!.restore(note);
    await reload();
  }

  Future<void> deleteArchivedForever(Note note) => _storage!.delete(note);

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

  void _touchRecent(Note note) {
    _recent
      ..remove(note.title)
      ..insert(0, note.title);
    if (_recent.length > RecentStore.max) {
      _recent = _recent.sublist(0, RecentStore.max);
    }
    unawaited(_recentStore?.save(_recent));
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
    for (final note in _notes) {
      if (LineReminders.firstDue(note.body, now) != null) {
        _dueTitle = note.title;
        _dueLineNote = note;
        notifyListeners();
        return;
      }
    }
  }

  /// Called by the UI after showing the due alert: clears the fired reminder.
  Future<void> dismissDueReminder() async {
    final title = _dueTitle;
    final lineNote = _dueLineNote;
    _dueTitle = null;
    _dueLineNote = null;
    if (lineNote != null) {
      final stripped = LineReminders.stripDue(lineNote.body, DateTime.now());
      if (stripped != null) {
        final updated = lineNote.copyWith(body: stripped);
        final idx = _notes.indexWhere((n) => n.path == lineNote.path);
        if (idx >= 0) _notes[idx] = updated;
        if (_current?.path == lineNote.path) _current = updated;
        await _storage?.write(updated);
      }
    } else if (title != null && _reminders.remove(title) != null) {
      await _reminderStore?.save(_reminders);
    }
    notifyListeners();
  }

  Future<void> setTheme({
    String? mode,
    String? style,
    int? accent,
    String? glyphStyle,
    double? editorScale,
  }) async {
    _settings = _settings.copyWith(
      themeMode: mode,
      themeStyle: style,
      accentIndex: accent,
      glyphStyle: glyphStyle,
      editorScale: editorScale,
    );
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
