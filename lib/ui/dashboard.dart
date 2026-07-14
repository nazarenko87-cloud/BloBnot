import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';
import '../utils/line_reminders.dart';
import 'theme.dart';

/// Full-width dashboard: vault stats + a card per note.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.onOpenNote});

  /// Called after a card is tapped (the note is already selected).
  final VoidCallback onOpenNote;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final notes = controller.notes;
    final reminderCount =
        notes.where((n) => controller.reminderFor(n.title) != null).length +
        notes
            .map((n) => LineReminders.parseAll(n.body).length)
            .fold<int>(0, (a, b) => a + b);
    final pinned = notes.where((n) => controller.isPinned(n.title)).toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
    final rest = notes.where((n) => !controller.isPinned(n.title)).toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            _Stat(
              label: 'Notes',
              value: '${notes.length}',
              icon: Icons.description_outlined,
              tint: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            _Stat(
              label: 'Projects',
              value: '${controller.projects.length}',
              icon: Icons.folder_outlined,
              tint: kTagGreen,
            ),
            const SizedBox(width: 16),
            _Stat(
              label: 'Reminders',
              value: '$reminderCount',
              icon: Icons.notifications_none,
              tint: const Color(0xFFB98B4E),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (pinned.isNotEmpty) ...[
          const _Label('Pinned'),
          _cards(context, controller, pinned),
          const SizedBox(height: 20),
        ],
        const _Label('All notes', trailing: 'sorted by last edit'),
        _cards(context, controller, rest),
        const SizedBox(height: 24),
        _ActivityCard(notes: notes),
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
            hasReminder:
                controller.reminderFor(note.title) != null ||
                LineReminders.parseAll(note.body).isNotEmpty,
            glyph: controller.glyphFor(note),
            onTap: () {
              controller.select(note);
              onOpenNote();
            },
          ),
      ],
    );
  }
}

/// Activity heatmap wrapped in its own titled card with a less/more legend
/// (green palette, matching the v2.0 look regardless of accent).
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.notes});

  final List<Note> notes;

  static const _weeks = 26;

  Color _cellColor(int count) => switch (count) {
    0 => kTagGreen.withValues(alpha: 0.10),
    1 => kTagGreen.withValues(alpha: 0.35),
    2 => kTagGreen.withValues(alpha: 0.6),
    _ => kTagGreen,
  };

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final counts = <DateTime, int>{};
    for (final n in notes) {
      final d = DateTime(n.modified.year, n.modified.month, n.modified.day);
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final start = today.subtract(
      Duration(days: _weeks * 7 + today.weekday - 1),
    );

    Widget cell(int count) => Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: _cellColor(count),
        borderRadius: BorderRadius.circular(3),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Label('Activity', trailing: 'last 26 weeks'),
              const Spacer(),
              Text(
                'less',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 4),
              for (final a in [0.10, 0.35, 0.6, 1.0])
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: kTagGreen.withValues(alpha: a),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                'more',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var day = 0; day < 7; day++)
                  Row(
                    children: [
                      for (var week = 0; week <= _weeks; week++)
                        cell(
                          counts[DateTime(
                                start.year,
                                start.month,
                                start.day + week * 7 + day,
                              )] ??
                              0,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    required this.glyph,
    required this.onTap,
  });

  final Note note;
  final String project;
  final bool pinned;
  final bool hasReminder;
  final String? glyph;
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
      width: 250,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.07),
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (glyph != null) ...[
                      Text(glyph!, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (pinned) Icon(Icons.push_pin, size: 13, color: accent),
                    if (hasReminder)
                      Icon(Icons.notifications_active, size: 13, color: accent),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (project.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: kTagGreen.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          project.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Color(0xFF4A7A3A),
                          ),
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
