import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';
import 'glyph_avatar.dart';
import '../utils/properties.dart' show stripFrontMatter;
import 'hot_tasks_view.dart' show HotBadge, hotAddedLabel;
import 'theme.dart' show kHotColor;
import 'inline_editor.dart';
import 'note_dialogs.dart';
import 'pulse.dart';

part 'folders_pane.dart';

class NoteList extends StatefulWidget {
  const NoteList({
    super.key,
    required this.onNew,
    required this.onNewInProject,
    this.onNoteOpened,
    this.scope,
  });
  final VoidCallback onNew;
  final void Function(String project) onNewInProject;

  /// Three-column layout: show only the notes in this scope, as one flat
  /// list with each note's first line. Null keeps the classic grouped list.
  final NoteScope? scope;

  /// Called right after a note is selected (in addition to the selection
  /// itself) — lets a mobile drawer close itself once a note is picked.
  final VoidCallback? onNoteOpened;

  @override
  State<NoteList> createState() => _NoteListState();
}

enum _Sort { name, date, size }

/// 12-colour palette for project labels (index saved in project_colors.json).
const List<Color> kProjectColors = [
  Color(0xFFE57373),
  Color(0xFFF06292),
  Color(0xFFBA68C8),
  Color(0xFF9575CD),
  Color(0xFF7986CB),
  Color(0xFF64B5F6),
  Color(0xFF4DD0E1),
  Color(0xFF4DB6AC),
  Color(0xFF81C784),
  Color(0xFFDCE775),
  Color(0xFFFFD54F),
  Color(0xFFFF8A65),
];

final ButtonStyle _compactButton = IconButton.styleFrom(
  padding: EdgeInsets.zero,
  minimumSize: const Size(34, 34),
  maximumSize: const Size(34, 34),
  visualDensity: VisualDensity.compact,
);

class _NoteListState extends State<NoteList> {
  final _searchController = TextEditingController();
  String _query = '';
  _Sort _sort = _Sort.name;
  String? _glyphFilter;

  /// The project or note (by path) whose name is being edited in place.
  String? _renamingProject;
  String? _renamingNote;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  int _compare(Note a, Note b) => switch (_sort) {
    _Sort.name => a.titleLower.compareTo(b.titleLower),
    _Sort.date => b.modified.compareTo(a.modified),
    _Sort.size => b.body.length.compareTo(a.body.length),
  };

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    if (scope != null) return _flat(context, scope);
    final controller = context.watch<VaultController>();
    final accent = Theme.of(context).colorScheme.primary;
    final q = _query.toLowerCase();
    final filtered =
        controller.notes
            .where(
              (n) =>
                  q.isEmpty ||
                  n.titleLower.contains(q) ||
                  n.bodyLower.contains(q),
            )
            .where(
              (n) =>
                  _glyphFilter == null ||
                  controller.glyphFor(n) == _glyphFilter,
            )
            .toList()
          ..sort(_compare);
    final pinned = filtered.where((n) => controller.isPinned(n.title)).toList();
    final rest = filtered.where((n) => !controller.isPinned(n.title)).toList();
    final rootNotes = rest
        .where((n) => controller.projectOf(n).isEmpty)
        .toList();
    final byProject = <String, List<Note>>{
      for (final name in controller.projects) name: [],
    };
    for (final n in rest) {
      final proj = controller.projectOf(n);
      if (proj.isNotEmpty) byProject.putIfAbsent(proj, () => []).add(n);
    }

    return Column(
      children: [
        // Search + round add button. The app mark lives on the rail; a
        // second logo here only took room from the list.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search notes…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: _clearSearch,
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: accent.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onNew,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.add, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
        // "Notes N" with sort + new-project affordances.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Text(
                'Notes  ${controller.notes.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (controller.loadWarning != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      '${controller.loadWarning}. '
                      'Refresh (Ctrl+R) to try again.',
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const Spacer(),
              PopupMenuButton<_Sort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort_by_alpha, size: 18),
                style: _compactButton,
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _Sort.name, child: Text('By name')),
                  PopupMenuItem(value: _Sort.date, child: Text('By date')),
                  PopupMenuItem(value: _Sort.size, child: Text('By size')),
                ],
              ),
              IconButton(
                tooltip: 'New project (folder)',
                style: _compactButton,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                onPressed: () => _newProject(context),
              ),
            ],
          ),
        ),
        if (_glyphFilter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text('Glyph: $_glyphFilter'),
                onDeleted: () => setState(() => _glyphFilter = null),
              ),
            ),
          ),
        // Notes already open are one click away in the tab strip, so "recent"
        // is the ones that are not open — that is where the row earns its
        // place. Hidden when there are none.
        if (_query.isEmpty)
          if (controller.recentNotClosed case final closed
              when closed.isNotEmpty)
            _RecentRow(notes: closed, onTap: controller.select),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              if (pinned.isNotEmpty) ...[
                const _SectionLabel('Pinned'),
                for (final note in pinned) _tile(context, controller, note),
                const Divider(height: 8),
              ],
              // Root notes above the project folders (original ordering).
              for (final note in rootNotes) _tile(context, controller, note),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: controller.reorderProjects,
                children: [
                  for (final (i, e) in byProject.entries.indexed)
                    ExpansionTile(
                      key: ValueKey('project-${e.key}'),
                      dense: true,
                      initiallyExpanded: false,
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: Pulse(
                          enabled: e.value.any(
                            (n) => controller.hasAnyReminder(n),
                          ),
                          child: Icon(
                            Icons.folder,
                            size: 18,
                            color: controller.colorOf(e.key) != null
                                ? kProjectColors[controller.colorOf(e.key)! %
                                      kProjectColors.length]
                                : Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      title: _renamingProject == e.key
                          ? InlineTextEditor(
                              initial: e.key,
                              fieldKey: const Key('rename-project-field'),
                              helperText: null,
                              maxLength: 120,
                              style: const TextStyle(fontSize: 13),
                              onDone: (v) => _finishProjectRename(e.key, v),
                            )
                          : Builder(
                              builder: (context) {
                                final style = TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.62),
                                );
                                // Name truncates, count stays beside it —
                                // a long folder name used to push the count
                                // onto its own line.
                                return Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        e.key.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: style,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('${e.value.length}', style: style),
                                  ],
                                );
                              },
                            ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Project menu',
                        style: _compactButton,
                        icon: const Icon(Icons.more_horiz, size: 16),
                        onSelected: (v) => switch (v) {
                          'add_note' => widget.onNewInProject(e.key),
                          'color' => _pickColor(context, e.key),
                          'rename' => setState(() => _renamingProject = e.key),
                          'delete' => _deleteProject(
                            context,
                            e.key,
                            e.value.length,
                          ),
                          _ => null,
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'add_note',
                            child: Text('Add note'),
                          ),
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'color', child: Text('Colour…')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete project'),
                          ),
                        ],
                      ),
                      children: [
                        for (final note in e.value)
                          _tile(context, controller, note),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.archive_outlined, size: 16),
              label: const Text('Archive'),
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: BorderSide(color: Theme.of(context).dividerColor),
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              onPressed: () => showArchiveDialog(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    VaultController controller,
    Note note, {
    String? snippet,
  }) {
    final glyph = controller.glyphFor(note);
    return _NoteTile(
      note: note,
      snippet: snippet,
      selected: controller.current?.path == note.path,
      hasReminder: controller.hasAnyReminder(note),
      pinned: controller.isPinned(note.title),
      glyph: glyph,
      glyphStyle: controller.settings.glyphStyle,
      onGlyphTap: glyph == null
          ? null
          : () => setState(
              () => _glyphFilter = _glyphFilter == glyph ? null : glyph,
            ),
      onTap: () {
        controller.select(note);
        widget.onNoteOpened?.call();
      },
      renaming: _renamingNote == note.path,
      onRename: () => setState(() => _renamingNote = note.path),
      onRenameDone: (v) => _finishNoteRename(note, v),
      onPin: () => controller.togglePin(note.title),
      onArchive: () => controller.archiveNote(note),
      onSetGlyph: () => showGlyphPicker(context, note),
      onDelete: () => confirmDeleteNote(context, note),
    );
  }

  Future<void> _finishProjectRename(String project, String? name) async {
    setState(() => _renamingProject = null);
    if (name == null || name.trim() == project) return;
    final controller = context.read<VaultController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await controller.renameProject(project, name);
      if (!ok) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Could not rename: "$name" is taken')),
        );
      }
    } on Exception catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }

  Future<void> _finishNoteRename(Note note, String? name) async {
    setState(() => _renamingNote = null);
    if (name == null || name.trim() == note.title) return;
    final controller = context.read<VaultController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await controller.renameNote(note, name);
    } on Exception catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }

  /// Middle column of the three-column layout: the notes of one scope as a
  /// flat list, each with its date and first line. Pinned notes first.
  Widget _flat(BuildContext context, NoteScope scope) {
    final controller = context.watch<VaultController>();
    final accent = Theme.of(context).colorScheme.primary;
    final q = _query.toLowerCase();
    final notes =
        controller.notes
            .where((n) => scope.contains(controller, n))
            .where(
              (n) =>
                  q.isEmpty ||
                  n.titleLower.contains(q) ||
                  n.bodyLower.contains(q),
            )
            .toList()
          ..sort((a, b) {
            final pa = controller.isPinned(a.title);
            final pb = controller.isPinned(b.title);
            if (pa != pb) return pa ? -1 : 1;
            return _compare(a, b);
          });
    final folder = scope.folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  scope.title,
                  key: const Key('notes-column-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${notes.length}',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
              if (controller.loadWarning != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      '${controller.loadWarning}. '
                      'Refresh (Ctrl+R) to try again.',
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              PopupMenuButton<_Sort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort, size: 18),
                style: _compactButton,
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _Sort.name, child: Text('By name')),
                  PopupMenuItem(value: _Sort.date, child: Text('By date')),
                  PopupMenuItem(value: _Sort.size, child: Text('By size')),
                ],
              ),
              IconButton(
                tooltip: folder == null ? 'New note' : 'New note in "$folder"',
                style: _compactButton,
                icon: Icon(Icons.add_circle, size: 22, color: accent),
                onPressed: folder == null
                    ? widget.onNew
                    : () => widget.onNewInProject(folder),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search in ${scope.title}…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: _clearSearch,
                    ),
              isDense: true,
              filled: true,
              fillColor: accent.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _query.isEmpty
                          ? 'No notes here yet.\nUse + to add one.'
                          : 'Nothing matches "$_query".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const Key('notes-column'),
                  itemCount: notes.length,
                  itemBuilder: (context, i) => _tile(
                    context,
                    controller,
                    notes[i],
                    snippet: firstLineOf(notes[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

Future<void> _deleteProject(
  BuildContext context,
  String project,
  int noteCount,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete project "$project"?'),
      content: Text(
        noteCount == 0
            ? 'The empty folder will be removed.'
            : '$noteCount note(s) inside will be moved to the archive, '
                  'then the folder will be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<VaultController>().deleteProject(project);
    } on Exception catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete the whole project: $e. '
            'Notes already moved are in the Archive; try again.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }
}

Future<void> _pickColor(BuildContext context, String project) async {
  final controller = context.read<VaultController>();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Colour for "$project"'),
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < kProjectColors.length; i++)
            InkWell(
              onTap: () {
                controller.setProjectColor(project, i);
                Navigator.pop(context);
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: kProjectColors[i],
              ),
            ),
          InkWell(
            onTap: () {
              controller.setProjectColor(project, null);
              Navigator.pop(context);
            },
            child: const CircleAvatar(
              radius: 16,
              child: Icon(Icons.clear, size: 16),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _newProject(BuildContext context) async {
  final ctrl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('New project'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Folder name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  await context.read<VaultController>().createProject(name);
}

class _RecentRow extends StatefulWidget {
  const _RecentRow({required this.notes, required this.onTap});

  final List<Note> notes;
  final void Function(Note) onTap;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  /// Folded by default: the chips took four rows of the list. Kept for the
  /// rest of the session once opened.
  static bool _open = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.62);
    final label = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: muted,
    );
    // A wrapping block, not a sideways-scrolling strip: in the narrow sidebar
    // the strip cut the second chip off mid-word with nothing to say more
    // were hidden (and a mouse wheel can't scroll it). Every chip is whole,
    // long titles end in an ellipsis, the full title is in the tooltip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('recent-toggle'),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
            child: Row(
              children: [
                Text('RECENT', style: label),
                Text('  ${widget.notes.length}', style: label),
                const Spacer(),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: muted,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final note in widget.notes.take(6))
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    backgroundColor: accent.withValues(alpha: 0.10),
                    side: BorderSide(color: accent.withValues(alpha: 0.25)),
                    tooltip: note.title,
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 104),
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    onPressed: () => widget.onTap(note),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    // Uppercase, letter-spaced, muted — the v2.0 section header look.
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.62);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: muted,
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    this.snippet,
    required this.selected,
    required this.hasReminder,
    required this.pinned,
    required this.glyph,
    required this.glyphStyle,
    required this.onGlyphTap,
    required this.onTap,
    required this.renaming,
    required this.onRename,
    required this.onRenameDone,
    required this.onPin,
    required this.onArchive,
    required this.onSetGlyph,
    required this.onDelete,
  });

  final Note note;

  /// First line of the note's text, shown under the date (three-column
  /// layout). Null shows the date alone.
  final String? snippet;
  final bool selected;
  final bool hasReminder;
  final bool pinned;
  final String? glyph;
  final String glyphStyle;
  final VoidCallback? onGlyphTap;
  final VoidCallback onTap;
  final bool renaming;
  final VoidCallback onRename;
  final ValueChanged<String?> onRenameDone;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onSetGlyph;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Rounded highlight pill for the selected note (v2.0 look).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        tileColor: selected ? accent.withValues(alpha: 0.14) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: GlyphAvatar(
          note: note,
          glyph: glyph,
          style: glyphStyle,
          pulse: hasReminder,
          onTap: onGlyphTap,
        ),
        title: renaming
            ? InlineTextEditor(
                initial: note.title,
                fieldKey: const Key('rename-note-field'),
                helperText: null,
                maxLength: 120,
                onDone: onRenameDone,
              )
            : Row(
                children: [
                  Flexible(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (pinned) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.push_pin, size: 12, color: accent),
                  ],
                  if (hasReminder) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.notifications_active, size: 13, color: accent),
                  ],
                ],
              ),
        // Last change, small — the same "Sep 27, 14:05" as hot tasks.
        subtitle: renaming
            ? null
            : Text(
                snippet == null || snippet!.isEmpty
                    ? hotAddedLabel(note.modified, DateTime.now())
                    : '${hotAddedLabel(note.modified, DateTime.now())}'
                          '  ·  $snippet',
                key: Key('note-stamp-${note.title}'),
                maxLines: snippet == null ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: snippet == null ? 10.5 : 11.5,
                  height: snippet == null ? 1.1 : 1.3,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz, size: 18),
          onSelected: (v) => switch (v) {
            'rename' => onRename(),
            'pin' => onPin(),
            'glyph' => onSetGlyph(),
            'archive' => onArchive(),
            'delete' => onDelete(),
            _ => null,
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
              value: 'pin',
              child: Text(pinned ? 'Unpin' : 'Pin to top'),
            ),
            const PopupMenuItem(value: 'glyph', child: Text('Set glyph…')),
            const PopupMenuItem(value: 'archive', child: Text('Archive')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Which notes the middle column of the three-column layout shows.
@immutable
class NoteScope {
  const NoteScope._(this.kind, [this.value]);

  static const all = NoteScope._('all');
  static const pinned = NoteScope._('pinned');
  static const unfiled = NoteScope._('unfiled');
  const NoteScope.folder(String name) : this._('folder', name);
  const NoteScope.tag(String tag) : this._('tag', tag);

  /// 'all' | 'pinned' | 'unfiled' | 'folder' | 'tag'.
  final String kind;
  final String? value;

  String? get folder => kind == 'folder' ? value : null;

  String get title => switch (kind) {
    'pinned' => 'Pinned',
    'unfiled' => 'No folder',
    'folder' => value!,
    'tag' => '#$value',
    _ => 'All notes',
  };

  bool contains(VaultController c, Note n) => switch (kind) {
    'pinned' => c.isPinned(n.title),
    'unfiled' => c.projectOf(n).isEmpty,
    'folder' => c.projectOf(n) == value,
    'tag' => n.tags.any((t) => t.toLowerCase() == value!.toLowerCase()),
    _ => true,
  };

  /// Still points at something that exists (a renamed or deleted folder,
  /// a tag no note uses any more, does not).
  bool isValidIn(VaultController c) => switch (kind) {
    'folder' => c.projects.contains(value),
    'tag' => c.notes.any((n) => contains(c, n)),
    _ => true,
  };

  @override
  bool operator ==(Object other) =>
      other is NoteScope && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// The first line a reader would see in [note]: no front matter, no title
/// heading, Markdown marks stripped, at most ~140 characters.
String firstLineOf(Note note) {
  final lines = stripFrontMatter(note.body).split('\n');
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line == '# ${note.title}') continue;
    final plain = line
        .replaceFirst(
          RegExp(r'^(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+\.\s+|>\s*)'),
          '',
        )
        .replaceAllMapped(
          RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
          (m) => (m.group(2) ?? m.group(1))!,
        )
        .replaceAllMapped(
          RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
          (m) => m.group(1)!,
        )
        .replaceAll(RegExp(r'[*_`~]|\{\{remind:[^}]*\}\}'), '')
        .trim();
    if (plain.isEmpty) continue;
    return plain.length > 140 ? '${plain.substring(0, 140)}…' : plain;
  }
  return '';
}
