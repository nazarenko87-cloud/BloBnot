import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/vault_controller.dart';
import '../editor_pane.dart';
import '../note_dialogs.dart';

// Full-screen pages the phone home screen pushes. Each has a back arrow in
// its app bar, and the system back gesture returns to the notes too.

/// Push any view (hot tasks, dashboard, table…) as its own page.
Future<void> pushMobilePage(
  BuildContext context, {
  required String title,
  required Widget body,
  Key? key,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (context) => Scaffold(
      key: key,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(top: false, child: body),
    ),
  ),
);

/// Open [note] in the editor on its own page.
Future<void> openNoteScreen(BuildContext context, Note note) {
  context.read<VaultController>().select(note);
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const MobileNoteScreen()));
}

/// The editor for the selected note, with a back arrow to the list.
class MobileNoteScreen extends StatelessWidget {
  const MobileNoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final note = controller.current;
    return PopScope(
      // Write the last keystrokes now rather than after the typing pause.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(controller.flushPendingSave());
      },
      child: Scaffold(
        key: const Key('mobile-note-screen'),
        appBar: AppBar(
          title: Text(
            note?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: note == null ? null : _actions(context, controller, note),
        ),
        body: const SafeArea(top: false, child: EditorPane()),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    VaultController controller,
    Note note,
  ) {
    final pinned = controller.isPinned(note.title);
    return [
      IconButton(
        tooltip: pinned ? 'Unpin' : 'Pin',
        icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
        onPressed: () => controller.togglePin(note.title),
      ),
      IconButton(
        tooltip: 'Archive',
        icon: const Icon(Icons.archive_outlined),
        onPressed: () async {
          Navigator.of(context).pop();
          await controller.archiveNote(note);
        },
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) async {
          switch (v) {
            case 'rename':
              await renameNoteWithDialog(context, note);
            case 'glyph':
              await showGlyphPicker(context, note);
            case 'delete':
              final navigator = Navigator.of(context);
              final before = controller.notes.length;
              await confirmDeleteNote(context, note);
              if (controller.notes.length < before) navigator.pop();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'glyph', child: Text('Set glyph…')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ];
  }
}

/// Keep-style quick capture: a title and the text, saved on the way back.
/// Nothing typed — nothing created.
class QuickNoteScreen extends StatefulWidget {
  const QuickNoteScreen({super.key, this.project});

  /// Folder the note goes into (the project the list is filtered to).
  final String? project;

  @override
  State<QuickNoteScreen> createState() => _QuickNoteScreenState();
}

class _QuickNoteScreenState extends State<QuickNoteScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _saved = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Longest title taken from the first line of the text.
  static const _maxDerivedTitle = 60;

  Future<void> _save(VaultController controller) async {
    if (_saved) return;
    _saved = true;
    final text = _body.text.trimRight();
    var title = _title.text.trim();
    if (title.isEmpty && text.trim().isEmpty) return;
    if (title.isEmpty) {
      final first = text.trimLeft().split('\n').first.trim();
      title = first.length > _maxDerivedTitle
          ? first.substring(0, _maxDerivedTitle).trim()
          : first;
    }
    final project = widget.project;
    final folder = project == null || project.isEmpty ? null : project;
    // Settle the final title first so the heading matches the file name.
    final unique = controller.uniqueNoteTitle(title, subfolder: folder);
    await controller.createNote(
      unique,
      subfolder: folder,
      body: text.isEmpty ? null : '# $unique\n\n$text\n',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<VaultController>();
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_save(controller));
      },
      child: Scaffold(
        key: const Key('quick-note-screen'),
        appBar: AppBar(
          title: Text(
            widget.project == null || widget.project!.isEmpty
                ? 'New note'
                : 'New note · ${widget.project}',
          ),
          actions: [
            IconButton(
              key: const Key('quick-done'),
              tooltip: 'Save',
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                TextField(
                  key: const Key('quick-title'),
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('quick-body'),
                    controller: _body,
                    autofocus: true,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: 'Note',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
