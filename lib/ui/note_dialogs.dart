import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';

// Note actions shared by the desktop note list and the phone home screen.

/// Pick an emoji glyph for a note (or clear it).
Future<void> showGlyphPicker(BuildContext context, Note note) async {
  final controller = context.read<VaultController>();
  final ctrl = TextEditingController(text: controller.glyphFor(note) ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Glyph for "${note.title}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 4,
            decoration: const InputDecoration(
              hintText: 'Paste an emoji, e.g. 🚀',
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final e in ['📌', '🚀', '💡', '📞', '💰', '🔥', '⭐', '🧠'])
                InkWell(
                  onTap: () => Navigator.pop(context, e),
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == null) return;
  await controller.setNoteGlyph(note.title, result.isEmpty ? null : result);
}

/// Archived notes, with restore and delete-forever.
Future<void> showArchiveDialog(BuildContext context) async {
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
                            icon: const Icon(Icons.delete_forever, size: 18),
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

/// Ask, then delete the note file.
Future<void> confirmDeleteNote(BuildContext context, Note note) async {
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

/// Ask for a new name. Returns the trimmed text, or null when cancelled
/// or left unchanged.
Future<String?> askNewName(
  BuildContext context, {
  required String title,
  required String current,
}) async {
  final ctrl = TextEditingController(text: current)
    ..selection = TextSelection(baseOffset: 0, extentOffset: current.length);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('rename-dialog-field'),
        controller: ctrl,
        autofocus: true,
        maxLength: 120,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  final name = result?.trim();
  if (name == null || name.isEmpty || name == current) return null;
  return name;
}

/// Rename a note, reporting a failure in a snack bar.
Future<void> renameNoteWithDialog(BuildContext context, Note note) async {
  final name = await askNewName(
    context,
    title: 'Rename note',
    current: note.title,
  );
  if (name == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await context.read<VaultController>().renameNote(note, name);
  } on Exception catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Rename failed: $e')));
  }
}
