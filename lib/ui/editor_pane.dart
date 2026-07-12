import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';

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
        _header(context, note),
        _Toolbar(
          controller: _textController,
          onChanged: () => controller.editCurrentBody(_textController.text),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context, note)),
      ],
    );
  }

  Widget _header(BuildContext context, Note note) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text('${note.wordCount} words · ${note.readMinutes} min',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
          ),
          SegmentedButton<ViewMode>(
            segments: const [
              ButtonSegment(value: ViewMode.edit, icon: Icon(Icons.edit)),
              ButtonSegment(
                  value: ViewMode.split, icon: Icon(Icons.vertical_split)),
              ButtonSegment(
                  value: ViewMode.preview, icon: Icon(Icons.visibility)),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ],
      ),
    );
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
                        fontFamily: 'monospace', height: 1.5, fontSize: 14),
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
    );
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
          padding: const EdgeInsets.only(top: 0, right: 8),
          alignment: Alignment.topRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 1; i <= lines; i++)
                Text('$i',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      height: 1.5,
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final VoidCallback onChanged;

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
    final newText =
        controller.text.replaceRange(start, start, prefix);
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
          btn(Icons.format_list_bulleted, 'Bullet list', () => _prefixLine('- ')),
          btn(Icons.format_list_numbered, 'Numbered list',
              () => _prefixLine('1. ')),
          btn(Icons.check_box_outlined, 'Checklist', () => _prefixLine('- [ ] ')),
          btn(Icons.title, 'Heading', () => _prefixLine('# ')),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
