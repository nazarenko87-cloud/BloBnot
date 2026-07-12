import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';
import '../utils/line_reminders.dart';

/// Full-width dashboard: vault stats + a card per note.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.onOpenNote});

  /// Called after a card is tapped (the note is already selected).
  final VoidCallback onOpenNote;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final notes = controller.notes;
    final reminderCount = notes
            .where((n) => controller.reminderFor(n.title) != null)
            .length +
        notes
            .map((n) => LineReminders.parseAll(n.body).length)
            .fold<int>(0, (a, b) => a + b);
    final pinned =
        notes.where((n) => controller.isPinned(n.title)).toList();
    final rest =
        notes.where((n) => !controller.isPinned(n.title)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _Stat(label: 'Notes', value: '${notes.length}'),
            _Stat(label: 'Projects', value: '${controller.projects.length}'),
            _Stat(label: 'Reminders', value: '$reminderCount'),
          ],
        ),
        const SizedBox(height: 16),
        if (pinned.isNotEmpty) ...[
          const _Label('Pinned'),
          _cards(context, controller, pinned),
          const SizedBox(height: 16),
        ],
        const _Label('All notes'),
        _cards(context, controller, rest),
      ],
    );
  }

  Widget _cards(
    BuildContext context,
    VaultController controller,
    List<Note> notes,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final note in notes)
          _NoteCard(
            note: note,
            project: controller.projectOf(note),
            pinned: controller.isPinned(note.title),
            hasReminder: controller.reminderFor(note.title) != null ||
                LineReminders.parseAll(note.body).isNotEmpty,
            onTap: () {
              controller.select(note);
              onOpenNote();
            },
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              Text(label, style: TextStyle(color: Colors.grey.shade500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.project,
    required this.pinned,
    required this.hasReminder,
    required this.onTap,
  });

  final Note note;
  final String project;
  final bool pinned;
  final bool hasReminder;
  final VoidCallback onTap;

  String get _snippet {
    final lines = note.body
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('#'))
        .take(3)
        .join('\n');
    return lines.length > 120 ? '${lines.substring(0, 120)}…' : lines;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 240,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (pinned) Icon(Icons.push_pin, size: 13, color: accent),
                    if (hasReminder)
                      Icon(Icons.notifications_active,
                          size: 13, color: accent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (project.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          project,
                          style: TextStyle(fontSize: 10, color: accent),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '${note.wordCount} w',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
