part of 'vault_controller.dart';

/// Open tabs and the recent list: what is open, closing a tab, and
/// remembering the tabs between sessions (`tabs.json`).
extension VaultTabs on VaultController {
  /// Recently opened notes that are not open as a tab right now.
  List<Note> get recentNotClosed {
    final open = _openPaths.toSet();
    return [
      for (final n in recentNotes)
        if (!open.contains(n.path)) n,
    ];
  }

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
    _notifyIfAlive();
  }

  void _touchRecent(Note note) {
    _recent
      ..remove(note.title)
      ..insert(0, note.title);
    if (_recent.length > RecentStore.max) {
      _recent = _recent.sublist(0, RecentStore.max);
    }
    _background(_recentStore?.save(_recent));
  }

  Future<void> _restoreTabs(String root) async {
    final all = await AppState.read(VaultController._tabsFile);
    final saved = all is Map ? all[root] : null;
    if (saved is! Map) return;
    final byPath = {for (final n in _notes) n.path: n};
    final open = [
      for (final path in (saved['open'] as List?) ?? const [])
        if (byPath.containsKey(path)) path as String,
    ];
    if (open.isEmpty) return;
    _openPaths
      ..clear()
      ..addAll(open);
    _current = byPath[saved['current']] ?? byPath[open.last];
    _savedTabs = _tabsSnapshot();
  }

  String _tabsSnapshot() => [..._openPaths, '>', _current?.path].join('\n');

  /// Called on every change; writes only when the tabs actually moved, so
  /// typing in a note costs nothing here.
  void _saveTabsIfChanged() {
    final root = _storage?.id;
    if (root == null || _disposed || _loading) return;
    final snapshot = _tabsSnapshot();
    if (snapshot == _savedTabs) return;
    _savedTabs = snapshot;
    final open = List<String>.of(_openPaths);
    final current = _current?.path;
    // Queued, so a quick run of tab switches is written in order.
    _tabsWrite = _tabsWrite
        .then((_) async {
          // Strict read: if the file cannot be read right now, skip this
          // write instead of dropping every other vault's remembered tabs.
          final all = await AppState.readStrict(VaultController._tabsFile);
          final map = all is Map
              ? Map<String, Object?>.from(all)
              : <String, Object?>{};
          map[root] = {'open': open, 'current': current};
          await AppState.write(VaultController._tabsFile, map);
        })
        .catchError((Object _) {
          _savedTabs = null; // try again on the next change
        });
  }
}
