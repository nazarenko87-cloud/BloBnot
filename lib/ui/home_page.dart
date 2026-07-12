import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show kAppVersion;
import '../state/vault_controller.dart';
import 'editor_pane.dart';
import 'graph_view.dart';
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();

    if (!controller.hasVault) {
      return Scaffold(body: _NoVault(onOpen: () => _pickVault(context)));
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const Text('BloBnot', style: TextStyle(fontWeight: FontWeight.w700)),
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
            icon: Icon(_showList ? Icons.view_sidebar : Icons.view_sidebar_outlined),
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
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAbout(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (_showList)
            SizedBox(width: 260, child: NoteList(onNew: () => _newNote(context))),
          if (_showList) const VerticalDivider(width: 1),
          Expanded(child: _editorAndGraph(context)),
        ],
      ),
    );
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
                _graphFraction =
                    (_graphFraction - dx / total).clamp(0.18, 0.72);
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
    final title = await _promptTitle(context);
    if (title == null || title.isEmpty || !context.mounted) return;
    await context.read<VaultController>().createNote(title);
  }

  Future<String?> _promptTitle(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New note'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Note title'),
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
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FlutterLogo(size: 56),
            const SizedBox(height: 12),
            const Text('BloBnot',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('v$kAppVersion', style: TextStyle(color: Colors.grey.shade500)),
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
          const Text('BloBnot',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
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
