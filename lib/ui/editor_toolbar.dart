part of 'editor_pane.dart';

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onChanged,
    required this.onAttach,
    required this.onSticker,
    required this.onAddField,
    required this.onExportHtml,
    required this.onExportPdf,
    required this.onAiContext,
    required this.onLinkPicker,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final VoidCallback onSticker;
  final VoidCallback onAddField;
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
    final shell = Theme.of(context).extension<ShellStyle>();
    final small = shell?.icon(18) ?? 18;
    final big = shell?.icon(22) ?? 22;
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      icon: Icon(icon, size: small),
      onPressed: onTap,
    );
    Widget sep() => Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).dividerColor,
    );
    // Rounded pill container around the toolbar (v2.0 look).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const SizedBox(width: 8),
              // Group: linking — wiki link is the flagship action.
              IconButton.filledTonal(
                tooltip: 'Wiki link',
                icon: Icon(Icons.link, size: big, color: accent),
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
              btn(
                Icons.view_list_outlined,
                'Add a field (shows in Table)',
                onAddField,
              ),
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
                icon: Icon(Icons.attach_file, size: big, color: accent),
                onPressed: onAttach,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
