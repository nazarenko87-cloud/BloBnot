import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart' show kAppVersion, trayService;
import '../state/vault_controller.dart';
import 'dashboard.dart';
import 'editor_pane.dart';
import 'graph_view.dart';
import 'calculator_dialog.dart';
import 'lock_screen.dart';
import 'note_list.dart';
import 'open_tabs.dart';
import 'settings_dialog.dart';
import 'theme.dart';

/// A rounded, softly-shadowed floating panel — the building block of the
/// card-based v2.0 shell.
class ShellCard extends StatelessWidget {
  const ShellCard({super.key, required this.child, this.clip = true});

  final Widget child;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Outer container carries only the soft shadow (no colour), so it does
    // not sit as a coloured DecoratedBox between ListTiles and their Material.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kCardRadius),
        boxShadow: cardShadow(dark),
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(kCardRadius),
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        child: child,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showList = true;
  bool _showDashboard = false;
  bool _showGraph = true;
  // Graph pane width as a fraction of the editor+graph area (18%–72%).
  double _graphFraction = 0.32;
  bool _dueDialogShowing = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();

    if (controller.locked) return const LockScreen();

    _maybeShowDueReminder(controller);

    if (!controller.hasVault) {
      return Scaffold(body: _NoVault(onOpen: () => _pickVault(context)));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
            _quickSwitcher(context),
      },
      // Card-based v2.0 shell: floating rounded panels on the page colour.
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(kShellGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rail(context),
              const SizedBox(width: kShellGap),
              Expanded(
                child: _showDashboard
                    ? ShellCard(
                        child: DashboardView(
                          onOpenNote: () =>
                              setState(() => _showDashboard = false),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_showList) ...[
                            SizedBox(
                              width: 260,
                              child: ShellCard(
                                child: NoteList(onNew: () => _newNote(context)),
                              ),
                            ),
                            const SizedBox(width: kShellGap),
                          ],
                          Expanded(child: _editorAndGraph(context)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget item(IconData icon, String tip, bool active, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: IconButton(
            tooltip: tip,
            isSelected: active,
            style: IconButton.styleFrom(
              backgroundColor: active ? accent.withValues(alpha: 0.18) : null,
            ),
            icon: Icon(icon, size: 22, color: active ? accent : null),
            onPressed: onTap,
          ),
        );

    return ShellCard(
      child: SizedBox(
        width: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              // App mark at the very top of the rail.
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'B',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              item(
                Icons.description_outlined,
                'Notes',
                !_showDashboard,
                () => setState(() => _showDashboard = false),
              ),
              item(
                Icons.dashboard_outlined,
                'Dashboard',
                _showDashboard,
                () => setState(() => _showDashboard = true),
              ),
              item(
                Icons.view_sidebar_outlined,
                _showList ? 'Hide notes list' : 'Show notes list',
                _showList,
                () => setState(() => _showList = !_showList),
              ),
              item(
                Icons.bolt,
                'Quick switcher (Ctrl+P)',
                false,
                () => _quickSwitcher(context),
              ),
              item(
                Icons.hub_outlined,
                _showGraph ? 'Hide graph' : 'Show graph',
                _showGraph,
                () => setState(() => _showGraph = !_showGraph),
              ),
              const Spacer(),
              item(
                Icons.calculate_outlined,
                'Calculator',
                false,
                () => showCalculatorDialog(context),
              ),
              item(Icons.fullscreen, 'Fullscreen', false, () async {
                final fs = await windowManager.isFullScreen();
                await windowManager.setFullScreen(!fs);
              }),
              item(
                Icons.settings_outlined,
                'Settings',
                false,
                () => showSettingsDialog(context),
              ),
              item(
                Icons.info_outline,
                'About',
                false,
                () => _showAbout(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _quickSwitcher(BuildContext context) async {
    final controller = context.read<VaultController>();
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(12),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            final q = ctrl.text.toLowerCase();
            final matches = controller.notes
                .where((n) => n.title.toLowerCase().contains(q))
                .take(8)
                .toList();
            return SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Jump to note…',
                      prefixIcon: Icon(Icons.bolt),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) {
                      if (matches.isNotEmpty) {
                        controller.select(matches.first);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  for (final n in matches)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 16),
                      title: Text(n.title),
                      onTap: () {
                        controller.select(n);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Show the "reminder due" alert exactly once per firing.
  void _maybeShowDueReminder(VaultController controller) {
    final title = controller.dueReminderTitle;
    if (title == null || _dueDialogShowing) return;
    _dueDialogShowing = true;
    // Real system toast — visible even when the window is hidden in tray.
    trayService?.notify('BloBnot — reminder', title);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.notifications_active, size: 36),
          title: Text(title),
          content: const Text('Reminder is due.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await context.read<VaultController>().dismissDueReminder();
      _dueDialogShowing = false;
    });
  }

  Widget _editorAndGraph(BuildContext context) {
    final editorCard = ShellCard(
      child: Column(
        children: [
          const OpenTabs(),
          const Expanded(child: EditorPane()),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        if (!_showGraph) {
          // Toggled back on from the rail's "Show graph" icon.
          return editorCard;
        }
        // Guard the clamp: on a very narrow area (total-260 < 180) the upper
        // bound would fall below the lower one and throw.
        final upper = (total - 260) > 180.0 ? (total - 260) : 180.0;
        final graphWidth = (total * _graphFraction).clamp(180.0, upper);
        return Row(
          children: [
            Expanded(child: editorCard),
            _DragHandle(
              onDrag: (dx) => setState(() {
                _graphFraction = (_graphFraction - dx / total).clamp(
                  0.18,
                  0.72,
                );
              }),
            ),
            SizedBox(
              width: graphWidth,
              child: ShellCard(
                child: GraphView(
                  onHide: () => setState(() => _showGraph = false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickVault(BuildContext context) async {
    final dir = await getDirectoryPath();
    if (dir == null || !context.mounted) return;
    await context.read<VaultController>().openVault(dir);
  }

  Future<void> _newNote(BuildContext context) async {
    final controller = context.read<VaultController>();
    final templates = await controller.loadTemplates();
    if (!context.mounted) return;
    final ctrl = TextEditingController();
    String project = '';
    String templateTitle = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New note'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Note title'),
                onSubmitted: (_) => Navigator.pop(context, true),
              ),
              if (controller.projects.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: project,
                  decoration: const InputDecoration(
                    labelText: 'Project',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('(vault root)'),
                    ),
                    for (final name in controller.projects)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (v) => setDialogState(() => project = v ?? ''),
                ),
              ],
              if (templates.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: templateTitle,
                  decoration: const InputDecoration(
                    labelText: 'Template',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('(blank)')),
                    for (final t in templates)
                      DropdownMenuItem(value: t.title, child: Text(t.title)),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => templateTitle = v ?? ''),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final title = ctrl.text.trim();
    if (ok != true || title.isEmpty || !context.mounted) return;
    String? body;
    if (templateTitle.isNotEmpty) {
      final tpl = templates.firstWhere((t) => t.title == templateTitle);
      // Substitute the template's own heading for the new note's title.
      body = tpl.body.replaceFirst('# ${tpl.title}', '# $title');
    }
    await controller.createNote(
      title,
      subfolder: project.isEmpty ? null : project,
      body: body,
    );
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 96),
            const SizedBox(height: 12),
            const Text(
              'BloBnot',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              'v$kAppVersion',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            const Text('Created by Nazarenko Andrii'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDrag});
  final void Function(double dx) onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: Container(
          width: 6,
          color: Colors.transparent,
          child: Center(
            child: Container(width: 1, color: Theme.of(context).dividerColor),
          ),
        ),
      ),
    );
  }
}

class _NoVault extends StatelessWidget {
  const _NoVault({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'BloBnot',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Choose a folder to use as your vault.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open vault…'),
          ),
        ],
      ),
    );
  }
}
