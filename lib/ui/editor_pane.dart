import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/attachment_store.dart';
import '../services/export_service.dart';
import '../state/vault_controller.dart';
import '../utils/editor_ops.dart';
import '../utils/line_reminders.dart';
import '../utils/markdown_highlight.dart';
import 'sticker_picker.dart';

enum ViewMode { edit, split, preview }

class EditorPane extends StatefulWidget {
  const EditorPane({super.key});

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  final _textController = HighlightingTextController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  ViewMode _mode = ViewMode.split;
  String? _loadedPath;
  bool _findVisible = false;

  /// Body shown in the preview pane, refreshed on a 200ms debounce so the
  /// Markdown tree is not re-parsed on every keystroke.
  String _previewBody = '';
  Timer? _previewTimer;
  bool _dropActive = false;

  @override
  void dispose() {
    _previewTimer?.cancel();
    _textController.dispose();
    _scroll.dispose();
    _focus.dispose();
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  void _commitText() {
    context.read<VaultController>().editCurrentBody(_textController.text);
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _previewBody != _textController.text) {
        setState(() => _previewBody = _textController.text);
      }
    });
  }

  /// Replace the whole body from outside the TextField (checkbox toggles,
  /// find&replace) and persist.
  void _setBody(String body) {
    _textController.text = body;
    _previewBody = body; // immediate — these are discrete edits
    _commitText();
  }

  /// Sync the text field when the selected note changes (but not on our own
  /// edits, which would move the cursor).
  void _syncFrom(Note? note) {
    if (note == null) {
      _textController.clear();
      _loadedPath = null;
      _previewBody = '';
      return;
    }
    if (note.path != _loadedPath) {
      _textController.text = note.body;
      _previewBody = note.body;
      _loadedPath = note.path;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final note = controller.current;
    _syncFrom(note);

    if (note == null) {
      return const Center(child: Text('No note selected'));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          EditorOps.wrapSelection(_textController, '**', '**');
          _commitText();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          EditorOps.wrapSelection(_textController, '*', '*');
          _commitText();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          EditorOps.wrapSelection(_textController, '[[', ']]');
          _commitText();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          setState(() => _findVisible = !_findVisible);
        },
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, controller, note),
          _Toolbar(
            controller: _textController,
            onChanged: _commitText,
            onAttach: () => _attachFile(context),
            onSticker: () => _pickSticker(context),
            onExportHtml: () => _export(context, note, ExportService.toHtml),
            onExportPdf: () => _export(context, note, ExportService.toPdf),
            onAiContext: () => _copyAiContext(context, note),
            onLinkPicker: () => _pickLink(context),
          ),
          if (_findVisible) _findBar(context),
          const Divider(height: 1),
          Expanded(
            child: DropTarget(
              onDragDone: (detail) => _attachPaths(
                context,
                detail.files.map((f) => f.path).toList(),
              ),
              onDragEntered: (_) => setState(() => _dropActive = true),
              onDragExited: (_) => setState(() => _dropActive = false),
              child: Stack(
                children: [
                  Positioned.fill(child: _body(context, note)),
                  if (_dropActive)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          alignment: Alignment.center,
                          child: const Text(
                            'Drop files to attach',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _BacklinksPanel(note: note),
          _AttachmentsPanel(
            note: note,
            onAttach: () => _attachFile(context),
          ),
        ],
      ),
    );
  }

  Widget _findBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Find',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _replaceController,
              decoration: const InputDecoration(
                hintText: 'Replace with',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              final find = _findController.text;
              if (find.isEmpty) return;
              final count = find.allMatches(_textController.text).length;
              if (count > 0) {
                _setBody(
                  _textController.text
                      .replaceAll(find, _replaceController.text),
                );
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Replaced $count occurrence(s)')),
              );
            },
            child: const Text('Replace all'),
          ),
          IconButton(
            tooltip: 'Close (Ctrl+H)',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _findVisible = false),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    Note note,
    Future<String> Function(Note) exporter,
  ) async {
    try {
      final path = await exporter(note);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $path')),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  /// Copy this note plus every note it wiki-links to as one plain-text block,
  /// ready to paste into any AI chat (v1.3 "Copy AI context").
  Future<void> _copyAiContext(BuildContext context, Note note) async {
    final controller = context.read<VaultController>();
    final buf = StringBuffer('# ${note.title}\n\n${note.body}\n');
    for (final title in note.outgoingLinks) {
      for (final n in controller.notes) {
        if (n.title == title) {
          buf.write('\n---\n# ${n.title} (linked)\n\n${n.body}\n');
          break;
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI context copied to clipboard')),
      );
    }
  }

  /// Fires when the user has just typed `[[`: opens the note picker so the
  /// link can be completed inline (autocomplete).
  Future<void> _maybeAutocomplete(BuildContext context) async {
    final sel = _textController.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final caret = sel.start;
    final text = _textController.text;
    if (caret < 2 || text.substring(caret - 2, caret) != '[[') return;
    // Skip if this `[[` is already closed just ahead.
    if (caret <= text.length - 2 &&
        text.substring(caret, caret + 2) == ']]') {
      return;
    }
    final title = await _chooseNoteTitle(context);
    if (title == null || !mounted) return;
    // `[[` is already typed — insert `title]]` after the caret.
    final at = _textController.selection.baseOffset.clamp(0, text.length);
    final insert = '$title]]';
    _textController.text =
        _textController.text.replaceRange(at, at, insert);
    _textController.selection =
        TextSelection.collapsed(offset: at + insert.length);
    _commitText();
  }

  /// Note picker for the link button when nothing is selected: choose a note
  /// and `[[Title]]` is inserted at the cursor.
  Future<void> _pickLink(BuildContext context) async {
    final title = await _chooseNoteTitle(context);
    if (title == null || title.isEmpty) return;
    final link = '[[$title]]';
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      link,
    );
    _textController.selection =
        TextSelection.collapsed(offset: offset + link.length);
    _commitText();
  }

  /// Shared searchable note picker; returns the chosen title or null.
  Future<String?> _chooseNoteTitle(BuildContext context) async {
    final controller = context.read<VaultController>();
    final searchCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link to note'),
        contentPadding: const EdgeInsets.all(12),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            final q = searchCtrl.text.toLowerCase();
            final matches = controller.notes
                .where((n) =>
                    n.path != controller.current?.path &&
                    n.title.toLowerCase().contains(q))
                .take(10)
                .toList();
            return SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search notes…',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) {
                      if (matches.isNotEmpty) {
                        Navigator.pop(context, matches.first.title);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  for (final n in matches)
                    ListTile(
                      dense: true,
                      leading:
                          const Icon(Icons.description_outlined, size: 16),
                      title: Text(n.title),
                      onTap: () => Navigator.pop(context, n.title),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _insertLineReminder(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    final tag = LineReminders.buildTag(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.end : _textController.text.length;
    _textController.text =
        _textController.text.replaceRange(offset, offset, ' $tag');
    _textController.selection =
        TextSelection.collapsed(offset: offset + tag.length + 1);
    _commitText();
  }

  Future<void> _pickSticker(BuildContext context) async {
    final controller = context.read<VaultController>();
    final asset = await showStickerPicker(context);
    if (asset == null) return;
    final snippet = '![sticker]($asset)';
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      snippet,
    );
    _textController.selection =
        TextSelection.collapsed(offset: offset + snippet.length);
    controller.editCurrentBody(_textController.text);
  }

  Widget _header(BuildContext context, VaultController controller, Note note) {
    final reminder = controller.reminderFor(note.title);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      '${note.wordCount} words · ${note.readMinutes} min'
                      '${reminder != null ? '  ·  🔔 ${_fmt(reminder)}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    // Save indicator (icon-only; label in the tooltip).
                    Tooltip(
                      message: controller.isDirty ? 'Saving…' : 'Saved',
                      child: Icon(
                        controller.isDirty ? Icons.sync : Icons.check_circle,
                        size: 13,
                        color: controller.isDirty
                            ? Colors.grey.shade500
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                // Copyable file path (v1.3): click puts it on the clipboard.
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: note.path));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Path copied')),
                      );
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          note.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.copy,
                        size: 11,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Reminders',
            icon: Icon(
              reminder == null
                  ? Icons.notifications_none
                  : Icons.notifications_active,
              color: reminder == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
            onSelected: (v) => switch (v) {
              'note' => _editReminder(context, controller, note, reminder),
              'line' => _insertLineReminder(context),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'note',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sticky_note_2_outlined, size: 18),
                  title: Text('Reminder on note'),
                ),
              ),
              PopupMenuItem(
                value: 'line',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.alarm_add, size: 18),
                  title: Text('Reminder on line (at cursor)'),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedButton<ViewMode>(
              segments: const [
                ButtonSegment(value: ViewMode.edit, icon: Icon(Icons.edit)),
                ButtonSegment(
                  value: ViewMode.split,
                  icon: Icon(Icons.vertical_split),
                ),
                ButtonSegment(
                  value: ViewMode.preview,
                  icon: Icon(Icons.visibility),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _editReminder(
    BuildContext context,
    VaultController controller,
    Note note,
    DateTime? existing,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: existing ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) {
      // Allow clearing an existing reminder by cancelling the date picker.
      if (existing != null && context.mounted) {
        final clear = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove reminder?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (clear == true) await controller.clearReminder(note.title);
      }
      return;
    }
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(existing ?? now),
    );
    if (time == null) return;
    await controller.setReminder(
      note.title,
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<void> _attachFile(BuildContext context) async {
    final file = await openFile();
    if (file == null || !context.mounted) return;
    await _attachPaths(context, [file.path]);
  }

  /// Copy one or more files into the vault's attachments and insert links
  /// at the cursor. Shared by the picker button and drag-drop.
  Future<void> _attachPaths(BuildContext context, List<String> paths) async {
    final controller = context.read<VaultController>();
    final root = controller.vaultRoot;
    if (root == null) return;
    final store = AttachmentStore(root);
    final links = StringBuffer();
    for (final path in paths) {
      final name = await store.add(path);
      final ext = name.contains('.')
          ? name.substring(name.lastIndexOf('.')).toLowerCase()
          : '';
      final img = {'.png', '.jpg', '.jpeg', '.gif', '.webp'}.contains(ext);
      final encoded = 'attachments/${Uri.encodeComponent(name)}';
      links.write(img ? '![$name]($encoded)\n' : '[📎 $name]($encoded)\n');
    }
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      links.toString(),
    );
    _textController.selection =
        TextSelection.collapsed(offset: offset + links.length);
    controller.editCurrentBody(_textController.text);
  }

  Widget _body(BuildContext context, Note note) {
    return switch (_mode) {
      ViewMode.edit => _editor(context),
      ViewMode.preview => _preview(note),
      ViewMode.split => Row(
          children: [
            Expanded(child: _editor(context)),
            const VerticalDivider(width: 1),
            Expanded(child: _preview(note)),
          ],
        ),
    };
  }

  Widget _editor(BuildContext context) {
    final controller = context.read<VaultController>();
    final scale = context
        .select<VaultController, double>((c) => c.settings.editorScale);
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineNumbers(text: _textController, scale: scale),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focus,
                    maxLines: null,
                    expands: false,
                    keyboardType: TextInputType.multiline,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      height: 1.5,
                      fontSize: 14 * scale,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    // Right-click menu gains "Reminder on line…".
                    contextMenuBuilder: (context, editableTextState) =>
                        AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: [
                        ...editableTextState.contextMenuButtonItems,
                        ContextMenuButtonItem(
                          label: 'Reminder on line…',
                          onPressed: () {
                            ContextMenuController.removeAny();
                            _insertLineReminder(context);
                          },
                        ),
                      ],
                    ),
                    onChanged: (v) {
                      controller.editCurrentBody(v);
                      _schedulePreview();
                      _maybeAutocomplete(context);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(Note note) {
    final scale = context
        .select<VaultController, double>((c) => c.settings.editorScale);
    // Render the debounced body (not note.body) so parsing is throttled.
    final source = _previewBody;
    final rendered =
        LineReminders.linkify(Checklist.linkify(source)).replaceAllMapped(
      RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
      (m) => '**${(m.group(2) ?? m.group(1))!.trim()}**',
    );
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: Markdown(
      data: rendered,
      selectable: true,
      padding: const EdgeInsets.all(16),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        if (href == null || !href.startsWith('checkbox:')) return;
        final line = int.tryParse(href.substring('checkbox:'.length));
        if (line == null) return;
        // Toggle against the rendered source so the line index matches.
        final toggled = Checklist.toggleLine(source, line);
        if (toggled != null) _setBody(toggled);
      },
      sizedImageBuilder: (config) {
        final src = config.uri.toString();
        if (src.startsWith('assets/stickers/')) {
          // Small squircle emoji-style: crop away the caption text baked
          // into the sticker's edges, keep just the character.
          return ClipRSuperellipse(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 44,
              height: 44,
              child: ClipRect(
                child: Align(
                  widthFactor: 0.8,
                  heightFactor: 0.7,
                  child: Image.asset(src, width: 55, height: 63),
                ),
              ),
            ),
          );
        }
        if (src.startsWith('assets/')) {
          return Image.asset(src, width: 72, height: 72);
        }
        return Text(config.alt ?? src);
      },
      ),
    );
  }
}

class _BacklinksPanel extends StatelessWidget {
  const _BacklinksPanel({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final backlinks = controller.backlinksTo(note.title);
    if (backlinks.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ExpansionTile(
          dense: true,
          title: Text(
            'Backlinks (${backlinks.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          children: [
            for (final n in backlinks)
              ListTile(
                dense: true,
                leading: const Icon(Icons.arrow_back, size: 16),
                title: Text(n.title),
                onTap: () => controller.select(n),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.name,
    required this.store,
    required this.onDelete,
  });

  final String name;
  final AttachmentStore store;
  final VoidCallback onDelete;

  static const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

  IconData get _typeIcon {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.')).toLowerCase()
        : '';
    if (_imageExts.contains(ext)) return Icons.image_outlined;
    if (ext == '.pdf') return Icons.picture_as_pdf_outlined;
    if ({'.mp3', '.wav', '.ogg'}.contains(ext)) return Icons.audiotrack;
    if ({'.mp4', '.mkv', '.avi'}.contains(ext)) return Icons.movie_outlined;
    if ({'.zip', '.rar', '.7z'}.contains(ext)) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<String> _sizeLabel() async {
    try {
      final bytes = await File(store.pathOf(name)).length();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(2)} KB';
      }
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    } on IOException {
      return 'missing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => store.open(name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(_typeIcon, size: 22, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      FutureBuilder<String>(
                        future: _sizeLabel(),
                        builder: (context, snap) => Text(
                          'img-size: ${snap.data ?? '…'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.attach_file, size: 18, color: accent),
                PopupMenuButton<String>(
                  tooltip: 'Attachment menu',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (v) => switch (v) {
                    'open' => store.open(name),
                    'delete' => onDelete(),
                    _ => null,
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
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

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({required this.note, required this.onAttach});

  final Note note;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final names = AttachmentStore.referencedIn(note.body);
    if (names.isEmpty) return const SizedBox.shrink();
    final controller = context.read<VaultController>();
    final store = AttachmentStore(controller.vaultRoot!);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ExpansionTile(
          dense: true,
          title: Text(
            'Attachments (${names.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          children: [
            for (final name in names)
              _AttachmentCard(
                name: name,
                store: store,
                onDelete: () => _confirmDelete(context, store, name),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Attach file'),
                  onPressed: onAttach,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AttachmentStore store,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'The file will be removed from the attachments folder. '
          'The link in the note text stays.',
        ),
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
    if (ok == true) await store.delete(name);
  }
}

class _LineNumbers extends StatelessWidget {
  const _LineNumbers({required this.text, required this.scale});
  final TextEditingController text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: text,
      builder: (context, _) {
        final lines = '\n'.allMatches(text.text).length + 1;
        // One Text with all numbers — a per-line widget column re-lays out
        // every line on each keystroke, which lags on long notes.
        final buffer = StringBuffer();
        for (var i = 1; i <= lines; i++) {
          buffer.write(i);
          if (i < lines) buffer.write('\n');
        }
        return Container(
          width: 40,
          padding: const EdgeInsets.only(right: 8),
          alignment: Alignment.topRight,
          child: Text(
            buffer.toString(),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'monospace',
              height: 1.5,
              fontSize: 14 * scale,
              color: Colors.grey.shade600,
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onChanged,
    required this.onAttach,
    required this.onSticker,
    required this.onExportHtml,
    required this.onExportPdf,
    required this.onAiContext,
    required this.onLinkPicker,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final VoidCallback onSticker;
  final VoidCallback onExportHtml;
  final VoidCallback onExportPdf;
  final VoidCallback onAiContext;
  final VoidCallback onLinkPicker;

  void _wrap(String left, String right) {
    EditorOps.wrapSelection(controller, left, right);
    onChanged();
  }

  void _prefixLine(String prefix) {
    EditorOps.prefixLine(controller, prefix);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 18),
          onPressed: onTap,
        );
    Widget sep() => Container(
          width: 1,
          height: 22,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: Theme.of(context).dividerColor,
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const SizedBox(width: 8),
          // Group: linking — wiki link is the flagship action.
          IconButton.filledTonal(
            tooltip: 'Wiki link',
            icon: Icon(Icons.link, size: 22, color: accent),
            onPressed: () {
              final sel = controller.selection;
              if (sel.isValid && !sel.isCollapsed) {
                _wrap('[[', ']]');
              } else {
                onLinkPicker();
              }
            },
          ),
          sep(),
          // Group: text formatting.
          btn(Icons.format_bold, 'Bold', () => _wrap('**', '**')),
          btn(Icons.format_italic, 'Italic', () => _wrap('*', '*')),
          btn(Icons.title, 'Heading', () => _prefixLine('# ')),
          sep(),
          // Group: lists.
          btn(
            Icons.format_list_bulleted,
            'Bullet list',
            () => _prefixLine('- '),
          ),
          btn(
            Icons.format_list_numbered,
            'Numbered list',
            () => _prefixLine('1. '),
          ),
          btn(
            Icons.check_box_outlined,
            'Checklist',
            () => _prefixLine('- [ ] '),
          ),
          sep(),
          // Group: insert.
          btn(Icons.emoji_emotions_outlined, 'Sticker', onSticker),
          sep(),
          // Group: export & AI.
          btn(Icons.code, 'Export HTML', onExportHtml),
          btn(Icons.picture_as_pdf_outlined, 'Export PDF', onExportPdf),
          btn(Icons.smart_toy_outlined, 'Copy AI context', onAiContext),
          sep(),
          // Big accent paperclip at the very end (original toolbar look);
          // the toolbar scrolls horizontally, so it can never be clipped.
          IconButton.filledTonal(
            tooltip: 'Attach file',
            icon: Icon(Icons.attach_file, size: 22, color: accent),
            onPressed: onAttach,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
