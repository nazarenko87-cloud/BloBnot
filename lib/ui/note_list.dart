import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';
import 'glyph_avatar.dart';
import 'pulse.dart';

class NoteList extends StatefulWidget {
  const NoteList({super.key, required this.onNew});
  final VoidCallback onNew;

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
  String _query = '';
  _Sort _sort = _Sort.name;
  String? _glyphFilter;

  int _compare(Note a, Note b) => switch (_sort) {
        _Sort.name => a.titleLower.compareTo(b.titleLower),
        _Sort.date => b.modified.compareTo(a.modified),
        _Sort.size => b.body.length.compareTo(a.body.length),
      };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final q = _query.toLowerCase();
    final filtered = controller.notes
        .where((n) =>
            q.isEmpty || n.titleLower.contains(q) || n.bodyLower.contains(q))
        .where(
          (n) => _glyphFilter == null || controller.glyphFor(n) == _glyphFilter,
        )
        .toList()
      ..sort(_compare);
    final pinned =
        filtered.where((n) => controller.isPinned(n.title)).toList();
    final rest =
        filtered.where((n) => !controller.isPinned(n.title)).toList();
    final rootNotes =
        rest.where((n) => controller.projectOf(n).isEmpty).toList();
    final byProject = <String, List<Note>>{
      for (final name in controller.projects) name: [],
    };
    for (final n in rest) {
      final proj = controller.projectOf(n);
      if (proj.isNotEmpty) byProject.putIfAbsent(proj, () => []).add(n);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Row(
            children: [
              Text('Notes  ${controller.notes.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
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
              IconButton(
                tooltip: 'New note',
                style: _compactButton,
                icon: const Icon(Icons.add, size: 20),
                onPressed: widget.onNew,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search notes…',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
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
        if (_query.isEmpty && controller.recentNotes.length > 1)
          _RecentRow(
            notes: controller.recentNotes,
            onTap: controller.select,
          ),
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
                      initiallyExpanded: true,
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: Pulse(
                          enabled: e.value
                              .any((n) => controller.hasAnyReminder(n)),
                          child: Icon(
                            Icons.folder,
                            size: 18,
                            color: controller.colorOf(e.key) != null
                                ? kProjectColors[controller.colorOf(e.key)! %
                                    kProjectColors.length]
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      title: Text(
                        '${e.key}  ${e.value.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Project menu',
                        style: _compactButton,
                        icon: const Icon(Icons.more_horiz, size: 16),
                        onSelected: (v) => switch (v) {
                          'color' => _pickColor(context, e.key),
                          'delete' => _deleteProject(context, e.key,
                              e.value.length),
                          _ => null,
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'color',
                            child: Text('Colour…'),
                          ),
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
        const Divider(height: 1),
        TextButton.icon(
          icon: const Icon(Icons.archive_outlined, size: 16),
          label: const Text('Archive'),
          onPressed: () => _showArchive(context),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, VaultController controller, Note note) {
    final glyph = controller.glyphFor(note);
    return _NoteTile(
      note: note,
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
      onTap: () => controller.select(note),
      onPin: () => controller.togglePin(note.title),
      onArchive: () => controller.archiveNote(note),
      onSetGlyph: () => _setGlyph(context, note),
      onDelete: () => _confirmDelete(context, note),
    );
  }

  Future<void> _setGlyph(BuildContext context, Note note) async {
    final controller = context.read<VaultController>();
    final ctrl =
        TextEditingController(text: controller.glyphFor(note) ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Glyph for "${note.title}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 4,
              decoration: const InputDecoration(
                hintText: 'Paste an emoji, e.g. 🚀',
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final e in ['📌', '🚀', '💡', '📞', '💰', '🔥', '⭐', '🧠'])
                  InkWell(
                    onTap: () => Navigator.pop(context, e),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await controller.setNoteGlyph(note.title, result.isEmpty ? null : result);
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
      await context.read<VaultController>().deleteProject(project);
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

  Future<void> _showArchive(BuildContext context) async {
    final controller = context.read<VaultController>();
    final archived = await controller.loadArchived();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive (${archived.length})'),
        content: SizedBox(
          width: 420,
          child: archived.isEmpty
              ? const Text('Archive is empty.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final note in archived)
                      ListTile(
                        dense: true,
                        title: Text(note.title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Restore',
                              icon: const Icon(Icons.unarchive, size: 18),
                              onPressed: () async {
                                await controller.restoreArchived(note);
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete forever',
                              icon: const Icon(
                                Icons.delete_forever,
                                size: 18,
                              ),
                              onPressed: () async {
                                await controller.deleteArchivedForever(note);
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${note.title}"?'),
        content: const Text('The file will be removed from the vault.'),
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
      await context.read<VaultController>().deleteNote(note);
    }
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.notes, required this.onTap});

  final List<Note> notes;
  final void Function(Note) onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Recent'),
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: notes.take(8).length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final note = notes[i];
              return ActionChip(
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                backgroundColor: accent.withValues(alpha: 0.10),
                side: BorderSide(color: accent.withValues(alpha: 0.25)),
                label: Text(
                  note.title,
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: () => onTap(note),
              );
            },
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.selected,
    required this.hasReminder,
    required this.pinned,
    required this.glyph,
    required this.glyphStyle,
    required this.onGlyphTap,
    required this.onTap,
    required this.onPin,
    required this.onArchive,
    required this.onSetGlyph,
    required this.onDelete,
  });

  final Note note;
  final bool selected;
  final bool hasReminder;
  final bool pinned;
  final String? glyph;
  final String glyphStyle;
  final VoidCallback? onGlyphTap;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onSetGlyph;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: accent.withValues(alpha: 0.12),
      leading: GlyphAvatar(
        note: note,
        glyph: glyph,
        style: glyphStyle,
        pulse: hasReminder,
        onTap: onGlyphTap,
      ),
      title: Row(
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
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (v) => switch (v) {
          'pin' => onPin(),
          'glyph' => onSetGlyph(),
          'archive' => onArchive(),
          'delete' => onDelete(),
          _ => null,
        },
        itemBuilder: (context) => [
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
    );
  }
}
