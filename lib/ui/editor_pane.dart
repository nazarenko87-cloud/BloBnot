import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/attachment_store.dart';
import '../services/export_service.dart';
import '../state/vault_controller.dart';
import 'sticker_picker.dart';

enum ViewMode { edit, split, preview }

class EditorPane extends StatefulWidget {
  const EditorPane({super.key});

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  final _textController = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  ViewMode _mode = ViewMode.split;
  String? _loadedPath;

  @override
  void dispose() {
    _textController.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Sync the text field when the selected note changes (but not on our own
  /// edits, which would move the cursor).
  void _syncFrom(Note? note) {
    if (note == null) {
      _textController.clear();
      _loadedPath = null;
      return;
    }
    if (note.path != _loadedPath) {
      _textController.text = note.body;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, controller, note),
        _Toolbar(
          controller: _textController,
          onChanged: () => controller.editCurrentBody(_textController.text),
          onAttach: () => _attachFile(context),
          onSticker: () => _pickSticker(context),
          onExportHtml: () => _export(context, note, ExportService.toHtml),
          onExportPdf: () => _export(context, note, ExportService.toPdf),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context, note)),
        _BacklinksPanel(note: note),
        _AttachmentsPanel(note: note),
      ],
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
                Text(
                  '${note.wordCount} words · ${note.readMinutes} min'
                  '${reminder != null ? '  ·  🔔 ${_fmt(reminder)}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: reminder == null ? 'Set reminder' : 'Edit reminder',
            icon: Icon(
              reminder == null
                  ? Icons.notifications_none
                  : Icons.notifications_active,
              color: reminder == null
                  ? null
                  : Theme.of(context).colorScheme.primary,
            ),
            onPressed: () => _editReminder(context, controller, note, reminder),
          ),
          SegmentedButton<ViewMode>(
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
    final controller = context.read<VaultController>();
    final root = controller.vaultRoot;
    if (root == null) return;
    final file = await openFile();
    if (file == null || !context.mounted) return;
    final name = await AttachmentStore(root).add(file.path);
    final link = '[📎 $name](attachments/${Uri.encodeComponent(name)})';
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      link,
    );
    _textController.selection =
        TextSelection.collapsed(offset: offset + link.length);
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
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineNumbers(text: _textController),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focus,
                    maxLines: null,
                    expands: false,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      height: 1.5,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    onChanged: (v) => controller.editCurrentBody(v),
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
    // Render wiki-links as their display text for now (milestone 1).
    final rendered = note.body.replaceAllMapped(
      RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
      (m) => '**${(m.group(2) ?? m.group(1))!.trim()}**',
    );
    return Markdown(
      data: rendered,
      selectable: true,
      padding: const EdgeInsets.all(16),
      sizedImageBuilder: (config) {
        final src = config.uri.toString();
        if (src.startsWith('assets/')) {
          return Image.asset(src, width: 72, height: 72);
        }
        return Text(config.alt ?? src);
      },
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

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({required this.note});

  final Note note;

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
              ListTile(
                dense: true,
                leading: const Icon(Icons.attach_file, size: 18),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Open',
                      icon: const Icon(Icons.open_in_new, size: 18),
                      onPressed: () => store.open(name),
                    ),
                    IconButton(
                      tooltip: 'Delete file',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => _confirmDelete(context, store, name),
                    ),
                  ],
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
  const _LineNumbers({required this.text});
  final TextEditingController text;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: text,
      builder: (context, _) {
        final lines = '\n'.allMatches(text.text).length + 1;
        return Container(
          width: 40,
          padding: const EdgeInsets.only(right: 8),
          alignment: Alignment.topRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 1; i <= lines; i++)
                Text(
                  '$i',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    height: 1.5,
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
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
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final VoidCallback onSticker;
  final VoidCallback onExportHtml;
  final VoidCallback onExportPdf;

  void _wrap(String left, String right) {
    final sel = controller.selection;
    final text = controller.text;
    if (!sel.isValid) return;
    final selected = sel.textInside(text);
    final replaced = '$left$selected$right';
    controller.value = controller.value.replaced(sel, replaced);
    onChanged();
  }

  void _prefixLine(String prefix) {
    final sel = controller.selection;
    if (!sel.isValid) return;
    final start = controller.text.lastIndexOf('\n', sel.start - 1) + 1;
    final newText = controller.text.replaceRange(start, start, prefix);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.end + prefix.length),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          icon: Icon(icon, size: 18),
          onPressed: onTap,
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const SizedBox(width: 8),
          btn(Icons.link, 'Wiki link', () => _wrap('[[', ']]')),
          btn(Icons.format_bold, 'Bold', () => _wrap('**', '**')),
          btn(Icons.format_italic, 'Italic', () => _wrap('*', '*')),
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
          btn(Icons.title, 'Heading', () => _prefixLine('# ')),
          btn(Icons.emoji_emotions_outlined, 'Sticker', onSticker),
          btn(Icons.code, 'Export HTML', onExportHtml),
          btn(Icons.picture_as_pdf_outlined, 'Export PDF', onExportPdf),
          const SizedBox(width: 4),
          // Prominent, at the very end of the toolbar (per handoff) — and the
          // toolbar scrolls horizontally, so it can never be clipped away.
          OutlinedButton.icon(
            onPressed: onAttach,
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('Attach file'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
