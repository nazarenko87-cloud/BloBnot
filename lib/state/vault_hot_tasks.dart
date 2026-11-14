part of 'vault_controller.dart';

/// Hot tasks (`_hot/tasks.md`): loading, the queued read-modify-write
/// and the task actions. The state itself lives in [VaultController];
/// this part only keeps the 1000-line controller readable.
extension VaultHotTasks on VaultController {
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
    _hot = [
      HotTask(id: _hotSeq++, text: clean, created: toMinute(DateTime.now())),
      ..._hot,
    ];
    return _hotChanged();
  }

  /// Rewrite a task's text, keeping its stamps and its place in the list.
  Future<void> editHotTask(int id, String text) {
    final clean = cleanHotText(text);
    final task = _hotById(id);
    if (clean.isEmpty || task == null || task.text == clean) {
      return Future.value();
    }
    _hot = [for (final t in _hot) t.id == id ? t.withText(clean) : t];
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
    _notifyIfAlive();
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
