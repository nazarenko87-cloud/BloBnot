/// Hot tasks: short to-dos kept in `{vault}/_hot/tasks.md` as a plain
/// Markdown checklist, so the file syncs with the vault and stays readable
/// in any editor (and to the MCP server):
///
/// ```markdown
/// # Hot tasks
///
/// - [ ] Call the supplier + 2026-09-22 09:15
/// - [x] Send the invoice + 2026-09-21 11:00 ✓ 2026-09-21 14:30
/// ```
///
/// `+` is when the task was added, `✓` when it was done. Both are optional:
/// a line written by hand still parses.
///
/// Done tasks older than [kHotArchiveAfter] move to `_hot/archive.md`.
library;

const String kHotDir = '_hot';
const String kHotTasksPath = '$kHotDir/tasks.md';
const String kHotArchivePath = '$kHotDir/archive.md';
const Duration kHotArchiveAfter = Duration(days: 30);

class HotTask {
  const HotTask({
    required this.id,
    required this.text,
    this.done,
    this.created,
  });

  /// Session-local identity; not persisted.
  final int id;
  final String text;

  /// When it was completed, or null while in progress.
  final DateTime? done;

  /// When it was added. Null for tasks written before stamps existed, or by
  /// hand — the UI simply shows no "added" time for those.
  final DateTime? created;

  bool get isDone => done != null;

  HotTask withDone(DateTime? when) =>
      HotTask(id: id, text: text, done: when, created: created);

  HotTask withText(String newText) =>
      HotTask(id: id, text: newText, done: done, created: created);
}

final _taskLine = RegExp(r'^\s*[-*] \[( |x|X)\]\s?(.*)$');
final _stamp = RegExp(r'\s*✓\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2})?)\s*$');
final _createdStamp = RegExp(
  r'\s*\+\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2})?)\s*$',
);

/// Task text as it can be stored: one line, trimmed.
String cleanHotText(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Parse checklist lines; everything else in the file is ignored. A `[x]`
/// line without a date stamp is treated as done at [now].
List<HotTask> parseHotTasks(
  String source, {
  required DateTime now,
  int Function()? nextId,
}) {
  var counter = 0;
  final ids = nextId ?? () => counter++;
  final tasks = <HotTask>[];
  for (final line in source.split('\n')) {
    final m = _taskLine.firstMatch(line.trimRight());
    if (m == null) continue;
    final checked = m.group(1)!.toLowerCase() == 'x';
    var text = m.group(2)!;
    DateTime? done;
    if (checked) {
      final s = _stamp.firstMatch(text);
      if (s != null) {
        done = DateTime.tryParse(s.group(1)!.replaceFirst(' ', 'T'));
        text = text.substring(0, s.start);
      }
      done ??= now;
    }
    // The added-stamp sits before the done-stamp, so it is at the end now.
    DateTime? created;
    final c = _createdStamp.firstMatch(text);
    if (c != null) {
      created = DateTime.tryParse(c.group(1)!.replaceFirst(' ', 'T'));
      if (created != null) text = text.substring(0, c.start);
    }
    text = cleanHotText(text);
    if (text.isEmpty) continue;
    tasks.add(HotTask(id: ids(), text: text, done: done, created: created));
  }
  return tasks;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// [d] truncated to the minute — the precision the file stores, so a task in
/// memory and the same task read back from disk compare equal.
DateTime toMinute(DateTime d) =>
    DateTime(d.year, d.month, d.day, d.hour, d.minute);

String formatHotStamp(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

String hotTaskLine(HotTask t) {
  final created = t.created;
  final done = t.done;
  return [
    done == null ? '- [ ]' : '- [x]',
    ' ${t.text}',
    if (created != null) ' + ${formatHotStamp(created)}',
    if (done != null) ' ✓ ${formatHotStamp(done)}',
  ].join();
}

/// Newest first; ties keep their existing order.
List<HotTask> sortDone(Iterable<HotTask> done) {
  final list = done.toList();
  final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((a, b) {
    final byDate = b.done!.compareTo(a.done!);
    return byDate != 0 ? byDate : order[a.id]!.compareTo(order[b.id]!);
  });
  return list;
}

/// In-progress tasks in their order, then done tasks newest first.
String serializeHotTasks(List<HotTask> tasks, {String title = 'Hot tasks'}) {
  final open = tasks.where((t) => !t.isDone);
  final done = sortDone(tasks.where((t) => t.isDone));
  return [
    '# $title',
    '',
    for (final t in open) hotTaskLine(t),
    for (final t in done) hotTaskLine(t),
    '',
  ].join('\n');
}

/// Split into tasks to keep and done tasks old enough for the archive.
({List<HotTask> keep, List<HotTask> archive}) splitForArchive(
  List<HotTask> tasks,
  DateTime now,
) {
  final keep = <HotTask>[];
  final archive = <HotTask>[];
  for (final t in tasks) {
    final done = t.done;
    if (done != null && now.difference(done) > kHotArchiveAfter) {
      archive.add(t);
    } else {
      keep.add(t);
    }
  }
  return (keep: keep, archive: archive);
}

/// Fold changes someone else made to `tasks.md` (the MCP server, another
/// device syncing through Drive) into the app's in-memory list before it
/// saves, so a save never erases them.
///
/// [baseline] holds the lines of the file as the app last read or wrote it.
/// A disk line outside it is an outside change: a task not known to the app
/// is added; a task the app still has open but disk shows done is completed.
/// Outside deletions are not replayed — losing a task is worse than keeping
/// one that someone removed.
List<HotTask> mergeExternal({
  required List<HotTask> memory,
  required Set<String> baseline,
  required List<HotTask> disk,
  required int Function() nextId,
}) {
  var merged = [...memory];
  final added = <HotTask>[];
  for (final d in disk) {
    if (baseline.contains(hotTaskLine(d))) continue;
    final sameText = merged.where((m) => m.text == d.text).toList();
    if (d.isDone) {
      final open = sameText.where((m) => !m.isDone).firstOrNull;
      if (open != null) {
        merged = [
          for (final m in merged) m.id == open.id ? m.withDone(d.done) : m,
        ];
      } else if (!sameText.any((m) => hotTaskLine(m) == hotTaskLine(d))) {
        added.add(
          HotTask(id: nextId(), text: d.text, done: d.done, created: d.created),
        );
      }
    } else if (sameText.isEmpty) {
      added.add(HotTask(id: nextId(), text: d.text, created: d.created));
    }
  }
  return [...added, ...merged];
}

/// Merge newly archived tasks into the existing archive file, newest first.
/// A task already in the archive is not added twice — archiving may be
/// retried if writing `tasks.md` failed after the archive was written.
String appendToArchive(String existing, List<HotTask> archived, DateTime now) {
  final previous = parseHotTasks(existing, now: now);
  final seen = previous.map(hotTaskLine).toSet();
  var next = 0;
  final all = [
    for (final t in [
      ...previous,
      ...archived.where((t) => !seen.contains(hotTaskLine(t))),
    ])
      t.withId(next++),
  ];
  return serializeHotTasks(all, title: 'Hot tasks — archive');
}

extension on HotTask {
  HotTask withId(int newId) =>
      HotTask(id: newId, text: text, done: done, created: created);
}
