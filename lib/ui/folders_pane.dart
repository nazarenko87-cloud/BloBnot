part of 'note_list.dart';

/// Left column of the three-column layout: the views (hot tasks, all notes,
/// dashboard, table), the folders and the tags. Picking a folder or a tag
/// sets what the middle column lists; [footer] holds the tool buttons.
class FoldersPane extends StatefulWidget {
  const FoldersPane({
    super.key,
    required this.scope,
    required this.view,
    required this.onScope,
    required this.onHot,
    required this.onDashboard,
    required this.onTable,
    required this.onNewInProject,
    required this.footer,
  });

  final NoteScope scope;

  /// The main area right now: 'notes' | 'hot' | 'dashboard' | 'table'.
  final String view;
  final ValueChanged<NoteScope> onScope;
  final VoidCallback onHot;
  final VoidCallback onDashboard;
  final VoidCallback onTable;
  final void Function(String project) onNewInProject;
  final Widget footer;

  @override
  State<FoldersPane> createState() => _FoldersPaneState();
}

class _FoldersPaneState extends State<FoldersPane> {
  String? _renaming;

  /// Tags shown before "Show all"; the rest are one click away.
  static const _tagsShown = 12;
  bool _allTags = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final notes = controller.notes;
    final onNotes = widget.view == 'notes';

    final counts = <String, int>{};
    var unfiled = 0;
    var pinned = 0;
    final tagCounts = <String, int>{};
    final tagSpelling = <String, String>{};
    for (final n in notes) {
      final folder = controller.projectOf(n);
      if (folder.isEmpty) {
        unfiled++;
      } else {
        counts[folder] = (counts[folder] ?? 0) + 1;
      }
      if (controller.isPinned(n.title)) pinned++;
      for (final t in n.tags.toSet()) {
        final key = t.toLowerCase();
        tagCounts[key] = (tagCounts[key] ?? 0) + 1;
        tagSpelling.putIfAbsent(key, () => t);
      }
    }
    final tags = tagCounts.keys.toList()
      ..sort((a, b) {
        final byCount = tagCounts[b]!.compareTo(tagCounts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final shownTags = _allTags ? tags : tags.take(_tagsShown).toList();
    final folders = controller.projects;

    bool on(NoteScope s) => onNotes && widget.scope == s;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            key: const Key('folders-pane'),
            padding: const EdgeInsets.symmetric(vertical: 10),
            children: [
              _PaneRow(
                key: const Key('rail-hot'),
                icon: HotBadge(
                  count: controller.hotInProgressCount,
                  child: const Icon(
                    Icons.local_fire_department,
                    size: 22,
                    color: kHotColor,
                  ),
                ),
                label: 'Hot tasks',
                active: widget.view == 'hot',
                color: kHotColor,
                onTap: widget.onHot,
              ),
              _PaneRow(
                icon: const Icon(Icons.notes, size: 20),
                label: 'All notes',
                count: notes.length,
                active: on(NoteScope.all),
                onTap: () => widget.onScope(NoteScope.all),
              ),
              if (pinned > 0)
                _PaneRow(
                  icon: const Icon(Icons.push_pin_outlined, size: 19),
                  label: 'Pinned',
                  count: pinned,
                  active: on(NoteScope.pinned),
                  onTap: () => widget.onScope(NoteScope.pinned),
                ),
              _PaneRow(
                icon: const Icon(Icons.dashboard_outlined, size: 19),
                label: 'Dashboard',
                active: widget.view == 'dashboard',
                onTap: widget.onDashboard,
              ),
              _PaneRow(
                icon: const Icon(Icons.table_chart_outlined, size: 19),
                label: 'Table',
                tooltip: 'Table — notes by their fields',
                active: widget.view == 'table',
                onTap: widget.onTable,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 6, 2),
                child: Row(
                  children: [
                    Expanded(child: _label(context, 'Folders')),
                    IconButton(
                      tooltip: 'New project (folder)',
                      style: _compactButton,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 17,
                      ),
                      onPressed: () => _newProject(context),
                    ),
                  ],
                ),
              ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: controller.reorderProjects,
                children: [
                  for (final (i, f) in folders.indexed)
                    _folderRow(context, controller, i, f, counts[f] ?? 0),
                ],
              ),
              if (unfiled > 0)
                _PaneRow(
                  icon: Icon(
                    Icons.folder_open_outlined,
                    size: 18,
                    color: _muted(context),
                  ),
                  label: 'No folder',
                  count: unfiled,
                  active: on(NoteScope.unfiled),
                  onTap: () => widget.onScope(NoteScope.unfiled),
                ),
              if (tags.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: _label(context, 'Tags'),
                ),
                for (final t in shownTags)
                  _PaneRow(
                    icon: Text(
                      '#',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _muted(context),
                      ),
                    ),
                    label: tagSpelling[t]!,
                    count: tagCounts[t],
                    dense: true,
                    active: on(NoteScope.tag(t)),
                    onTap: () => widget.onScope(NoteScope.tag(t)),
                  ),
                if (tags.length > _tagsShown)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(() => _allTags = !_allTags),
                        child: Text(
                          _allTags ? 'Show fewer' : 'Show all ${tags.length}',
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        widget.footer,
      ],
    );
  }

  Widget _folderRow(
    BuildContext context,
    VaultController controller,
    int index,
    String folder,
    int count,
  ) {
    final colour = controller.colorOf(folder);
    final scope = NoteScope.folder(folder);
    return Padding(
      key: ValueKey('folder-$folder'),
      padding: EdgeInsets.zero,
      child: _renaming == folder
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: InlineTextEditor(
                initial: folder,
                fieldKey: const Key('rename-project-field'),
                helperText: null,
                maxLength: 120,
                style: const TextStyle(fontSize: 13),
                onDone: (v) => _finishRename(folder, v),
              ),
            )
          : _PaneRow(
              icon: ReorderableDragStartListener(
                index: index,
                child: Pulse(
                  enabled: controller.notes.any(
                    (n) =>
                        controller.projectOf(n) == folder &&
                        controller.hasAnyReminder(n),
                  ),
                  child: Icon(
                    Icons.folder,
                    size: 18,
                    color: colour != null
                        ? kProjectColors[colour % kProjectColors.length]
                        : _muted(context),
                  ),
                ),
              ),
              label: folder,
              count: count,
              active: widget.view == 'notes' && widget.scope == scope,
              onTap: () => widget.onScope(scope),
              menu: PopupMenuButton<String>(
                tooltip: 'Project menu',
                style: _compactButton,
                icon: const Icon(Icons.more_horiz, size: 16),
                onSelected: (v) => switch (v) {
                  'add_note' => widget.onNewInProject(folder),
                  'color' => _pickColor(context, folder),
                  'rename' => setState(() => _renaming = folder),
                  'delete' => _deleteProject(context, folder, count),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'add_note', child: Text('Add note')),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'color', child: Text('Colour…')),
                  PopupMenuItem(value: 'delete', child: Text('Delete project')),
                ],
              ),
            ),
    );
  }

  Future<void> _finishRename(String folder, String? name) async {
    setState(() => _renaming = null);
    if (name == null || name.trim().isEmpty || name.trim() == folder) return;
    final controller = context.read<VaultController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final wasOpen = widget.scope == NoteScope.folder(folder);
    try {
      final ok = await controller.renameProject(folder, name);
      if (!ok) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Could not rename: "$name" is taken')),
        );
      } else if (wasOpen) {
        widget.onScope(NoteScope.folder(name.trim()));
      }
    } on Exception catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }

  static Color _muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);

  static Widget _label(BuildContext context, String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: _muted(context),
    ),
  );
}

/// One entry of the folders column: icon, name, optional count and menu,
/// with a tinted pill when it is what the rest of the window shows.
class _PaneRow extends StatelessWidget {
  const _PaneRow({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
    this.color,
    this.menu,
    this.dense = false,
    this.tooltip,
  });

  final Widget icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;
  final Color? color;
  final Widget? menu;
  final bool dense;

  /// Longer explanation on hover, when the label alone is terse.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.62);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: active ? tint.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: dense ? 30 : 36,
            child: Row(
              children: [
                const SizedBox(width: 8),
                SizedBox(width: 26, child: Center(child: icon)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 12.5 : 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? tint : null,
                    ),
                  ),
                ),
                if (count != null)
                  Padding(
                    padding: EdgeInsets.only(right: menu == null ? 10 : 0),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        color: muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ?menu,
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null
        ? row
        : Tooltip(message: tooltip!, child: row);
  }
}
