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

class _NoteListState extends State<NoteList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final notes = controller.notes
        .where((n) =>
            _query.isEmpty ||
            n.title.toLowerCase().contains(_query.toLowerCase()) ||
            n.body.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Row(
            children: [
              Text('Notes  ${controller.notes.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'New note',
                icon: const Icon(Icons.add),
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
          child: ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, i) {
              final note = notes[i];
              final selected = controller.current?.path == note.path;
              return _NoteTile(
                note: note,
                selected: selected,
                hasReminder: controller.reminderFor(note.title) != null,
                onTap: () => controller.select(note),
                onDelete: () => _confirmDelete(context, note),
              );
            },
          ),
        ),
      ],
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

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.selected,
    required this.hasReminder,
    required this.onTap,
    required this.onDelete,
  });

  final Note note;
  final bool selected;
  final bool hasReminder;
  final VoidCallback onTap;
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
          if (hasReminder) ...[
            const SizedBox(width: 4),
            Icon(Icons.notifications_active, size: 13, color: accent),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (v) {
          if (v == 'delete') onDelete();
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onTap,
    );
  }
}
