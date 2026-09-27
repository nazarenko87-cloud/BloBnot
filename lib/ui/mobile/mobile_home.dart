import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/vault_controller.dart';
import '../../utils/properties.dart';
import '../calculator_dialog.dart';
import '../dashboard.dart';
import '../hot_tasks_view.dart';
import '../note_dialogs.dart';
import '../note_list.dart' show kProjectColors;
import '../settings_dialog.dart';
import '../table_view.dart';
import '../theme.dart';
import 'mobile_pages.dart';

/// The phone home screen, after Google Keep: a search bar, the notes as
/// cards (pinned first, then newest), and a "+" for a quick note. Everything
/// else — hot tasks, dashboard, table, projects, glyphs, settings — sits in
/// the drawer, and opens as its own page with a back arrow.
class MobileHome extends StatefulWidget {
  const MobileHome({
    super.key,
    required this.onOpenFile,
    required this.onAbout,
  });

  final VoidCallback onOpenFile;
  final VoidCallback onAbout;

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  final _search = TextEditingController();
  String _query = '';
  String? _project;
  String? _glyph;
  bool _grid = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _project = null;
    _glyph = null;
    _search.clear();
    _query = '';
  });

  List<Note> _visible(VaultController controller) {
    final q = _query.trim().toLowerCase();
    final notes = controller.notes.where((n) {
      if (_project != null && controller.projectOf(n) != _project) {
        return false;
      }
      if (_glyph != null && controller.glyphFor(n) != _glyph) return false;
      if (q.isEmpty) return true;
      return n.titleLower.contains(q) || n.bodyLower.contains(q);
    }).toList()..sort((a, b) => b.modified.compareTo(a.modified));
    return notes;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final notes = _visible(controller);
    final pinned = [
      for (final n in notes)
        if (controller.isPinned(n.title)) n,
    ];
    final others = [
      for (final n in notes)
        if (!controller.isPinned(n.title)) n,
    ];

    return Scaffold(
      key: const Key('mobile-home'),
      drawer: _drawer(context, controller),
      floatingActionButton: FloatingActionButton(
        key: const Key('mobile-fab'),
        tooltip: 'New note',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => QuickNoteScreen(project: _project),
          ),
        ),
        child: const Icon(Icons.add, size: 30),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _searchBar(context),
            if (_project != null || _glyph != null) _filterChip(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: controller.reload,
                child: ListView(
                  key: const Key('mobile-notes'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 96),
                  children: [
                    if (_query.isEmpty && controller.hotInProgressCount > 0)
                      _HotStrip(onOpen: () => _openHot(context)),
                    if (notes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Center(
                          child: Text(
                            _query.isEmpty
                                ? 'No notes yet — tap + to write one.'
                                : 'Nothing matches "$_query".',
                            style: TextStyle(color: _muted(context)),
                          ),
                        ),
                      ),
                    if (pinned.isNotEmpty) ...[
                      _label(context, 'PINNED'),
                      _cards(context, controller, pinned),
                      if (others.isNotEmpty) _label(context, 'OTHERS'),
                    ],
                    _cards(context, controller, others),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  Widget _searchBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        child: Row(
          children: [
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Open navigation menu',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            Expanded(
              child: TextField(
                key: const Key('mobile-search'),
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search notes',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
              ),
            IconButton(
              key: const Key('mobile-layout-toggle'),
              tooltip: _grid ? 'List view' : 'Grid view',
              icon: Icon(
                _grid ? Icons.view_agenda_outlined : Icons.grid_view_outlined,
              ),
              onPressed: () => setState(() => _grid = !_grid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(BuildContext context) {
    final label = _project ?? 'Glyph $_glyph';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          key: const Key('mobile-filter-chip'),
          avatar: Icon(_project != null ? Icons.folder : Icons.star, size: 16),
          label: Text(label),
          deleteButtonTooltipMessage: 'Clear filter',
          onDeleted: _clearFilters,
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _muted(context),
      ),
    ),
  );

  /// Two columns that each flow on their own, so short and long cards pack
  /// like Keep's; in list view, one column.
  Widget _cards(
    BuildContext context,
    VaultController controller,
    List<Note> notes,
  ) {
    NoteCard card(Note n) => NoteCard(
      note: n,
      compact: !_grid,
      onTap: () => openNoteScreen(context, n),
      onLongPress: () => _noteSheet(context, controller, n),
    );
    if (!_grid) {
      return Column(children: [for (final n in notes) card(n)]);
    }
    final left = <Widget>[];
    final right = <Widget>[];
    for (final (i, n) in notes.indexed) {
      (i.isEven ? left : right).add(card(n));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left)),
        Expanded(child: Column(children: right)),
      ],
    );
  }

  Future<void> _noteSheet(
    BuildContext context,
    VaultController controller,
    Note note,
  ) async {
    final pinned = controller.isPinned(note.title);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                note.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final (value, icon, label) in [
              ('pin', Icons.push_pin_outlined, pinned ? 'Unpin' : 'Pin'),
              ('rename', Icons.edit_outlined, 'Rename'),
              ('glyph', Icons.emoji_emotions_outlined, 'Set glyph'),
              ('archive', Icons.archive_outlined, 'Archive'),
              ('delete', Icons.delete_outline, 'Delete'),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'pin':
        await controller.togglePin(note.title);
      case 'rename':
        await renameNoteWithDialog(context, note);
      case 'glyph':
        await showGlyphPicker(context, note);
      case 'archive':
        await controller.archiveNote(note);
      case 'delete':
        await confirmDeleteNote(context, note);
    }
  }

  void _openHot(BuildContext context) => pushMobilePage(
    context,
    title: 'Hot tasks',
    body: const Padding(padding: EdgeInsets.all(8), child: HotTasksView()),
  );

  /// Dashboard and Table select a note, then ask to show it: swap their page
  /// for the note's.
  void _openFromPage(BuildContext pageContext) {
    final note = context.read<VaultController>().current;
    Navigator.of(pageContext).pop();
    if (note != null) openNoteScreen(context, note);
  }

  Widget _drawer(BuildContext context, VaultController controller) {
    final accent = Theme.of(context).colorScheme.primary;
    void go(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    final glyphs = <String>{
      for (final n in controller.notes) ?controller.glyphFor(n),
    }.toList()..sort();

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'BloBnot',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
            _DrawerItem(
              key: const Key('drawer-notes'),
              icon: Icons.lightbulb_outline,
              label: 'Notes',
              selected: _project == null && _glyph == null,
              onTap: () => go(_clearFilters),
            ),
            _DrawerItem(
              key: const Key('drawer-hot'),
              icon: Icons.local_fire_department,
              iconColor: kHotColor,
              label: 'Hot tasks',
              badge: controller.hotInProgressCount,
              onTap: () => go(() => _openHot(context)),
            ),
            _DrawerItem(
              key: const Key('drawer-dashboard'),
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              onTap: () => go(
                () => pushMobilePage(
                  context,
                  title: 'Dashboard',
                  body: Builder(
                    builder: (page) =>
                        DashboardView(onOpenNote: () => _openFromPage(page)),
                  ),
                ),
              ),
            ),
            _DrawerItem(
              key: const Key('drawer-table'),
              icon: Icons.table_chart_outlined,
              label: 'Table',
              onTap: () => go(
                () => pushMobilePage(
                  context,
                  title: 'Table',
                  body: Builder(
                    builder: (page) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: NoteTableView(
                        onOpenNote: () => _openFromPage(page),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (controller.projects.isNotEmpty) ...[
              const Divider(),
              _section(context, 'Projects'),
              for (final p in controller.projects)
                _DrawerItem(
                  key: Key('drawer-project-$p'),
                  icon: Icons.folder_outlined,
                  iconColor: controller.colorOf(p) == null
                      ? null
                      : kProjectColors[controller.colorOf(p)! %
                            kProjectColors.length],
                  label: p,
                  selected: _project == p,
                  onTap: () => go(
                    () => setState(() {
                      _project = p;
                      _glyph = null;
                    }),
                  ),
                ),
            ],
            if (glyphs.isNotEmpty) ...[
              const Divider(),
              _section(context, 'Glyphs'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in glyphs)
                      ChoiceChip(
                        label: Text(g, style: const TextStyle(fontSize: 18)),
                        selected: _glyph == g,
                        onSelected: (_) => go(
                          () => setState(() {
                            _glyph = g;
                            _project = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const Divider(),
            _DrawerItem(
              key: const Key('drawer-archive'),
              icon: Icons.archive_outlined,
              label: 'Archive',
              onTap: () => go(() => showArchiveDialog(context)),
            ),
            _DrawerItem(
              icon: Icons.calculate_outlined,
              label: 'Calculator',
              onTap: () => go(() => showCalculatorDialog(context)),
            ),
            _DrawerItem(
              icon: Icons.file_open_outlined,
              label: 'Open file',
              onTap: () => go(widget.onOpenFile),
            ),
            _DrawerItem(
              key: const Key('drawer-settings'),
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => go(() => showSettingsDialog(context)),
            ),
            _DrawerItem(
              icon: Icons.info_outline,
              label: 'About',
              onTap: () => go(widget.onAbout),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _muted(context),
      ),
    ),
  );
}

/// Keep-like drawer row: a rounded highlight when selected.
class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.selected = false,
    this.badge = 0,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ListTile(
        selected: selected,
        selectedTileColor: accent.withValues(alpha: 0.14),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
        ),
        leading: HotBadge(
          count: badge,
          child: Icon(icon, color: iconColor),
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
  }
}

/// Hot tasks at a glance above the notes; tap for the full view.
class _HotStrip extends StatelessWidget {
  const _HotStrip({required this.onOpen});

  final VoidCallback onOpen;

  /// Tasks previewed on the strip.
  static const _preview = 2;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final tasks = controller.hotInProgress.take(_preview).toList();
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: kHotColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const Key('mobile-hot-strip'),
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department, color: kHotColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hot tasks · ${controller.hotInProgressCount}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      for (final t in tasks)
                        Text(
                          '• ${t.text}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A note as a Keep card: title, the start of the text, and a footer with
/// its project and last change.
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
    this.compact = false,
  });

  final Note note;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Characters of text shown on a card — enough for eight lines.
  static const _previewChars = 400;

  /// The text a reader sees, without front matter or the title heading.
  static String preview(Note note) {
    final lines = stripFrontMatter(note.body).split('\n');
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    if (lines.isNotEmpty && lines.first.trim() == '# ${note.title}') {
      lines.removeAt(0);
    }
    final text = lines.join('\n').trim();
    return text.length > _previewChars
        ? text.substring(0, _previewChars)
        : text;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    final project = controller.projectOf(note);
    final colourIndex = project.isEmpty ? null : controller.colorOf(project);
    final glyph = controller.glyphFor(note);
    final text = preview(note);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('note-card-${note.title}'),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (glyph != null) ...[
                      Text(glyph, style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (controller.hasAnyReminder(note))
                      Icon(Icons.notifications_active, size: 14, color: muted),
                  ],
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    text,
                    maxLines: compact ? 3 : 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (project.isNotEmpty) ...[
                      Icon(
                        Icons.folder,
                        size: 12,
                        color: colourIndex == null
                            ? muted
                            : kProjectColors[colourIndex %
                                  kProjectColors.length],
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          project,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Spacer(),
                    Text(
                      hotAddedLabel(note.modified, DateTime.now()),
                      style: TextStyle(fontSize: 9.5, color: muted),
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
