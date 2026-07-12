import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';

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

  int _compare(Note a, Note b) => switch (_sort) {
        _Sort.name =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        _Sort.date => b.modified.compareTo(a.modified),
        _Sort.size => b.body.length.compareTo(a.body.length),
      };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final filtered = controller.notes
        .where((n) =>
            _query.isEmpty ||
            n.title.toLowerCase().contains(_query.toLowerCase()) ||
            n.body.toLowerCase().contains(_query.toLowerCase()))
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
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              if (pinned.isNotEmpty) ...[
                const _SectionLabel('Pinned'),
                for (final note in pinned) _tile(context, controller, note),
                const Divider(height: 8),
              ],
              for (final e in byProject.entries)
                ExpansionTile(
                  dense: true,
                  initiallyExpanded: true,
                  leading: Icon(
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
                  title: Text(
                    '${e.key}  ${e.value.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Project colour',
                    style: _compactButton,
                    icon: const Icon(Icons.palette_outlined, size: 16),
                    onPressed: () => _pickColor(context, e.key),
                  ),
                  children: [
                    for (final note in e.value)
                      _tile(context, controller, note),
                  ],
                ),
              for (final note in rootNotes) _tile(context, controller, note),
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
    return _NoteTile(
      note: note,
      selected: controller.current?.path == note.path,
      hasReminder: controller.reminderFor(note.title) != null,
      pinned: controller.isPinned(note.title),
      onTap: () => controller.select(note),
      onPin: () => controller.togglePin(note.title),
      onArchive: () => controller.archiveNote(note),
      onDelete: () => _confirmDelete(context, note),
    );
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
    required this.onTap,
    required this.onPin,
    required this.onArchive,
    required this.onDelete,
  });

  final Note note;
  final bool selected;
  final bool hasReminder;
  final bool pinned;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: accent.withValues(alpha: 0.12),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: accent.withValues(alpha: 0.2),
        child: Text(
          note.title.isEmpty ? '?' : note.title.characters.first.toUpperCase(),
          style: TextStyle(fontSize: 12, color: accent),
        ),
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
          'archive' => onArchive(),
          'delete' => onDelete(),
          _ => null,
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'pin',
            child: Text(pinned ? 'Unpin' : 'Pin to top'),
          ),
          const PopupMenuItem(value: 'archive', child: Text('Archive')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onTap,
    );
  }
}
