import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/external_files_controller.dart';
import '../state/vault_controller.dart';

/// Row of pill tabs for files opened via "Open file…" (outside the vault).
/// Hidden when nothing is open. Mirrors [OpenTabs]' look but is fully
/// separate — these files aren't notes until explicitly saved as one.
class ExternalFileTabs extends StatelessWidget {
  const ExternalFileTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExternalFilesController>();
    final files = controller.files;
    if (files.isEmpty) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final active = controller.active;

    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final file = files[i];
          final isActive = file == active;
          return Material(
            color: isActive
                ? accent.withValues(alpha: 0.14)
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => controller.select(i),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.only(left: 12, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 13,
                      color: isActive ? accent : null,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        file.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isActive ? accent : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      iconSize: 13,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.close(i),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shows the active externally-opened file: its full path, an editable text
/// area, and a "Save to notes" action that imports it into the vault.
class ExternalFileViewer extends StatefulWidget {
  const ExternalFileViewer({super.key});

  @override
  State<ExternalFileViewer> createState() => _ExternalFileViewerState();
}

class _ExternalFileViewerState extends State<ExternalFileViewer> {
  final _textController = TextEditingController();
  String? _loadedPath;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _syncFrom(ExternalFile file) {
    if (_loadedPath == file.path) return;
    _loadedPath = file.path;
    _textController.text = file.content;
  }

  @override
  Widget build(BuildContext context) {
    final files = context.watch<ExternalFilesController>();
    final file = files.active;
    if (file == null) return const SizedBox.shrink();
    _syncFrom(file);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save to notes'),
                onPressed: () => _saveToNotes(context, file),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 14, height: 1.5),
              decoration: const InputDecoration(border: InputBorder.none),
              onChanged: files.editActive,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveToNotes(BuildContext context, ExternalFile file) async {
    final controller = context.read<VaultController>();
    final base = file.title.contains('.')
        ? file.title.substring(0, file.title.lastIndexOf('.'))
        : file.title;
    final existingTitles = controller.notes
        .map((n) => n.titleLower)
        .toSet();
    var title = base;
    var i = 1;
    while (existingTitles.contains(title.toLowerCase())) {
      title = '$base (${i++})';
    }
    final note = await controller.createNote(title, body: _textController.text);
    if (!context.mounted) return;
    context.read<ExternalFilesController>().markSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved as note: ${note.title}')),
    );
  }
}
