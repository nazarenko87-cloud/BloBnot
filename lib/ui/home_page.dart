import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart' show kAppVersion;
import '../state/vault_controller.dart';
import 'editor_pane.dart';
import 'graph_view.dart';
import 'lock_screen.dart';
import 'note_list.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showList = true;
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
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const Text(
              'BloBnot',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              'v$kAppVersion',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showList ? 'Hide notes list' : 'Show notes list',
            icon: Icon(
              _showList ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            ),
            onPressed: () => setState(() => _showList = !_showList),
          ),
          IconButton(
            tooltip: 'Toggle theme',
            icon: const Icon(Icons.brightness_6),
            onPressed: () => controller.setTheme(
              mode: controller.settings.themeMode == 'light' ? 'dark' : 'light',
            ),
          ),
          IconButton(
            tooltip: 'Open vault…',
            icon: const Icon(Icons.folder_open),
            onPressed: () => _pickVault(context),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => switch (v) {
              'password' => _passwordDialog(context),
              'about' => _showAbout(context),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'password', child: Text('Password…')),
              PopupMenuItem(value: 'about', child: Text('About')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (_showList)
            SizedBox(
              width: 260,
              child: NoteList(onNew: () => _newNote(context)),
            ),
          if (_showList) const VerticalDivider(width: 1),
          Expanded(child: _editorAndGraph(context)),
        ],
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
                      leading: const Icon(Icons.description_outlined,
                          size: 16),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final graphWidth = (total * _graphFraction).clamp(180.0, total - 260);
        return Row(
          children: [
            const Expanded(child: EditorPane()),
            _DragHandle(
              onDrag: (dx) => setState(() {
                _graphFraction = (_graphFraction - dx / total).clamp(0.18, 0.72);
              }),
            ),
            SizedBox(width: graphWidth, child: const GraphView()),
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
    final ctrl = TextEditingController();
    String project = '';
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
    await controller.createNote(
      title,
      subfolder: project.isEmpty ? null : project,
    );
  }

  Future<void> _passwordDialog(BuildContext context) async {
    final controller = context.read<VaultController>();
    final store = controller.passwordStore;
    final has = await store.hasPassword();
    if (!context.mounted) return;

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(has ? 'Change password' : 'Set password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (has)
              TextField(
                controller: currentCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password'),
              ),
            TextField(
              controller: newCtrl,
              obscureText: true,
              autofocus: !has,
              decoration: const InputDecoration(
                labelText: 'New password (empty = remove)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action != 'save' || !context.mounted) return;

    if (has && !await store.verify(currentCtrl.text)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong current password')),
        );
      }
      return;
    }
    if (newCtrl.text.isEmpty) {
      await store.clearPassword();
    } else {
      await store.setPassword(newCtrl.text);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newCtrl.text.isEmpty ? 'Password removed' : 'Password set',
          ),
        ),
      );
    }
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
