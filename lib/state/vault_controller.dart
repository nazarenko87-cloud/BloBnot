import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/calendar_event.dart';
import '../models/note.dart';
import '../services/calendar_event_store.dart';
import '../services/password_store.dart';
import '../services/glyph_store.dart';
import '../services/pinned_store.dart';
import '../services/project_colors_store.dart';
import '../services/project_order_store.dart';
import '../services/recent_store.dart';
import '../services/reminder_store.dart';
import '../services/settings_store.dart';
import '../services/meta_paths.dart';
import '../services/vault_backend.dart';
import '../utils/hot_tasks.dart';
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

  VaultBackend? _storage;
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
  CalendarEventStore? _calendarStore;
  List<CalendarEvent> _events = [];

  /// Message from the last failed [openVault]/[reload], or null if the last
  /// attempt succeeded. The UI shows this instead of leaving [loading] stuck
  /// forever — a real risk for a SAF tree backed by a cloud provider (e.g.
  /// Google Drive), whose reads can throw on transient network errors.
  String? _openError;

  List<HotTask> _hot = [];
  int _hotSeq = 0;
  int? _lastCompletedHotId;

  /// Writes of `_hot/tasks.md` run one after another, so a fast run of
  /// clicks can never land an older snapshot on top of a newer one.
  Future<void> _hotWrites = Future.value();

  /// Text inserted into the open editor from outside it (the calculator's
  /// "Insert into note"). The editor listens; see [insertIntoNote].
  final _insertRequests = StreamController<String>.broadcast();

  /// Queued hot-task saves can finish after the app shut the controller down.
  bool _disposed = false;

  /// Paths of notes open as tabs, in tab order.
  final List<String> _openPaths = [];

  /// Title of a reminder that just came due — the UI shows it and calls
  /// [dismissDueReminder]. Null when nothing is due.
  String? _dueTitle;

  /// When the due alert came from a `{{remind:}}` tag, the note it lives in
  /// (dismissing strips the due tags from that note's body).
  Note? _dueLineNote;

  /// When the due alert came from a standalone calendar event (not tied to
  /// any note), its id (dismissing removes that event).
  String? _dueEventId;

  List<Note> get notes => List.unmodifiable(_notes);
  Note? get current => _current;
  VaultSettings get settings => _settings;
  bool get loading => _loading;
  bool get hasVault => _storage != null;
  String? get vaultRoot => _storage?.id;
  bool get locked => _locked;
  String? get dueReminderTitle => _dueTitle;
  String? get openError => _openError;

  /// In-progress hot tasks, newest first.
  List<HotTask> get hotInProgress =>
      List.unmodifiable(_hot.where((t) => !t.isDone));

  /// Done hot tasks, most recently completed first.
  List<HotTask> get hotDone =>
      List.unmodifiable(sortDone(_hot.where((t) => t.isDone)));

  int get hotInProgressCount => _hot.where((t) => !t.isDone).length;

  /// The task completed last in this session, so the UI can highlight it.
  int? get lastCompletedHotId => _lastCompletedHotId;

  Stream<String> get insertRequests => _insertRequests.stream;

  DateTime? reminderFor(String title) => _reminders[title];
  bool isPinned(String title) => _pinned.contains(title);

  /// All note-level reminders, keyed by note title (for calendar display).
  Map<String, DateTime> get reminders => Map.unmodifiable(_reminders);

  /// Standalone reminders not tied to any note (for calendar display).
  List<CalendarEvent> get events => List.unmodifiable(_events);
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
    if (last != null && await openBackend(last).available()) {
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
    _openError = null;
    notifyListeners();
    // Let queued hot-task saves reach the vault they were made in first.
    await _hotWrites;
    try {
      _storage = openBackend(root);
      // Metadata lives alongside the vault on desktop, but app-private on
      // Android (a SAF content:// tree is not reachable via dart:io).
      final meta = await vaultMetaRoot(root);
      _settingsStore = SettingsStore(meta);
      _reminderStore = ReminderStore(meta);
      _pinnedStore = PinnedStore(meta);
      _projectColorsStore = ProjectColorsStore(meta);
      _recentStore = RecentStore(meta);
      _openPaths.clear();
      _glyphStore = GlyphStore(meta);
      _projectOrderStore = ProjectOrderStore(meta);
      _calendarStore = CalendarEventStore(meta);
      _settings = await _settingsStore!.load();
      _reminders = await _reminderStore!.load();
      _events = await _calendarStore!.load();
      _pinned = await _pinnedStore!.load();
      _projectColors = await _projectColorsStore!.load();
      _tagGlyphs = await _glyphStore!.loadTagGlyphs();
      _glyphOverrides = await _glyphStore!.loadOverrides();
      _projectOrder = await _projectOrderStore!.load();
      _recent = await _recentStore!.load();
      _projects = await _storage!.listProjects();
      _notes = await _storage!.loadNotes();
      _hot = [];
      _hotBaseline = {};
      _lastCompletedHotId = null;
      await _loadHot();
      _current = _notes.isNotEmpty ? _notes.first : null;
      if (_current != null) _openPaths.add(_current!.path);
      await AppSettings.setLastVault(root);
      _reminderTimer?.cancel();
      _reminderTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkDueReminders(),
      );
    } catch (e) {
      _storage = null;
      _openError = 'Could not open vault: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-reads the vault from disk — picks up notes changed outside the app
  /// (e.g. edited directly on disk) without restarting BloBnot. Flushes any
  /// pending debounced save first so in-progress typing isn't discarded.
  Future<void> reload() async {
    if (_storage == null) return;
    await _flushPendingSave();
    try {
      _projects = await _storage!.listProjects();
      _notes = await _storage!.loadNotes();
      await _loadHot();
      if (_current != null) {
        _current = _notes.firstWhere(
          (n) => n.path == _current!.path,
          orElse: () => _notes.isNotEmpty ? _notes.first : _current!,
        );
      }
      _openError = null;
    } catch (e) {
      _openError = 'Could not refresh vault: $e';
    } finally {
      notifyListeners();
    }
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

  /// Create a standalone reminder for [when] that isn't tied to any note
  /// (set from the dashboard calendar).
  Future<void> addEvent(String title, DateTime when) async {
    _events.add(
      CalendarEvent(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        when: when,
      ),
    );
    notifyListeners();
    await _calendarStore?.save(_events);
  }

  Future<void> deleteEvent(String id) async {
    if (_events.isEmpty) return;
    final before = _events.length;
    _events = _events.where((e) => e.id != id).toList();
    if (_events.length == before) return;
    notifyListeners();
    await _calendarStore?.save(_events);
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
    for (final ev in _events) {
      if (ev.when.isBefore(now)) {
        _dueTitle = ev.title;
        _dueEventId = ev.id;
        notifyListeners();
        return;
      }
    }
  }

  /// Called by the UI after showing the due alert: clears the fired reminder.
  Future<void> dismissDueReminder() async {
    final title = _dueTitle;
    final lineNote = _dueLineNote;
    final eventId = _dueEventId;
    _dueTitle = null;
    _dueLineNote = null;
    _dueEventId = null;
    if (lineNote != null) {
      final stripped = LineReminders.stripDue(lineNote.body, DateTime.now());
      if (stripped != null) {
        final updated = lineNote.copyWith(body: stripped);
        final idx = _notes.indexWhere((n) => n.path == lineNote.path);
        if (idx >= 0) _notes[idx] = updated;
        if (_current?.path == lineNote.path) _current = updated;
        await _storage?.write(updated);
      }
    } else if (eventId != null) {
      _events.removeWhere((e) => e.id == eventId);
      await _calendarStore?.save(_events);
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
    _insertRequests.close();
    _disposed = true;
    super.dispose();
  }

  // --- insert from outside the editor ---

  /// Put [text] into the current note: at the caret when the editor is on
  /// screen, otherwise on a new line at the end. False when no note is open.
  bool insertIntoNote(String text) {
    final note = _current;
    if (note == null) return false;
    if (_insertRequests.hasListener) {
      _insertRequests.add(text);
    } else {
      final body = note.body;
      final sep = body.isEmpty || body.endsWith('\n') ? '' : '\n';
      editCurrentBody('$body$sep$text');
    }
    return true;
  }

  // --- hot tasks ---

  String? _hotError;

  /// Why `_hot/tasks.md` could not be read, if it could not. Notes still
  /// open — the hot tasks file is never allowed to block the vault.
  String? get hotError => _hotError;

  /// Lines of `tasks.md` as this app last read or wrote them — anything else
  /// found there on the next save was changed by someone else.
  Set<String> _hotBaseline = {};

  /// Bumped on every in-app change, so a load that finishes after the user
  /// already changed something does not overwrite that change.
  int _hotGeneration = 0;

  /// Every read-modify-write of the hot files goes through this one queue:
  /// loading, archiving and saving can then never interleave.
  Future<void> _queueHot(Future<void> Function() job) {
    final run = _hotWrites.then((_) => job());
    // Keep the queue alive after a failure; the caller still sees it.
    _hotWrites = run.catchError((Object _) {});
    return run;
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadHot() {
    final storage = _storage;
    if (storage == null) return Future.value();
    final generation = _hotGeneration;
    return _queueHot(() async {
      try {
        final now = DateTime.now();
        final parsed = parseHotTasks(
          await storage.readText(kHotTasksPath),
          now: now,
          nextId: () => _hotSeq++,
        );
        if (!identical(_storage, storage) || _hotGeneration != generation) {
          return; // vault switched, or the user changed tasks meanwhile
        }
        final split = splitForArchive(parsed, now);
        _hot = split.keep;
        _hotBaseline = parsed.map(hotTaskLine).toSet();
        if (split.archive.isNotEmpty) {
          final existing = await storage.readText(kHotArchivePath);
          await storage.writeText(
            kHotArchivePath,
            appendToArchive(existing, split.archive, now),
          );
          final kept = split.keep;
          await storage.writeText(kHotTasksPath, serializeHotTasks(kept));
          _hotBaseline = kept.map(hotTaskLine).toSet();
        }
        _hotError = null;
      } on Exception catch (e) {
        _hotError = 'Could not load hot tasks: $e';
      }
    });
  }

  /// Writes the current list — after folding in anything someone else wrote
  /// to the file since this app last touched it (see [mergeExternal]).
  Future<void> _saveHot() {
    final storage = _storage;
    if (storage == null) return Future.value();
    return _queueHot(() async {
      if (!identical(_storage, storage)) return;
      final disk = parseHotTasks(
        await storage.readText(kHotTasksPath),
        now: DateTime.now(),
      );
      if (!identical(_storage, storage)) return;
      final merged = mergeExternal(
        memory: _hot,
        baseline: _hotBaseline,
        disk: disk,
        nextId: () => _hotSeq++,
      );
      if (serializeHotTasks(merged) != serializeHotTasks(_hot)) {
        _hot = merged;
        _notifyIfAlive();
      }
      final written = _hot;
      await storage.writeText(kHotTasksPath, serializeHotTasks(written));
      _hotBaseline = written.map(hotTaskLine).toSet();
    });
  }

  HotTask? _hotById(int id) {
    for (final t in _hot) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> addHotTask(String text) {
    final clean = cleanHotText(text);
    if (clean.isEmpty || _storage == null) return Future.value();
    _hot = [HotTask(id: _hotSeq++, text: clean), ..._hot];
    return _hotChanged();
  }

  Future<void> completeHotTask(int id) {
    final task = _hotById(id);
    if (task == null || task.isDone) return Future.value();
    final now = toMinute(DateTime.now());
    _hot = [for (final t in _hot) t.id == id ? t.withDone(now) : t];
    _lastCompletedHotId = id;
    return _hotChanged();
  }

  /// Back to in progress, at the top — for undoing a mis-click.
  Future<void> reopenHotTask(int id) {
    final task = _hotById(id);
    if (task == null || !task.isDone) return Future.value();
    _hot = [task.withDone(null), ..._hot.where((t) => t.id != id)];
    if (_lastCompletedHotId == id) _lastCompletedHotId = null;
    return _hotChanged();
  }

  Future<void> deleteHotTask(int id) {
    if (_hotById(id) == null) return Future.value();
    _hot = _hot.where((t) => t.id != id).toList();
    return _hotChanged();
  }

  Future<void> _hotChanged() {
    _hotGeneration++;
    notifyListeners();
    return _saveHot();
  }

  /// Archived hot tasks, most recently completed first. Lines someone left
  /// unchecked in the archive file by hand are not archived tasks; skip them.
  Future<List<HotTask>> loadHotArchive() async {
    final storage = _storage;
    if (storage == null) return const [];
    final text = await storage.readText(kHotArchivePath);
    return sortDone(
      parseHotTasks(text, now: DateTime.now()).where((t) => t.isDone),
    );
  }
}
