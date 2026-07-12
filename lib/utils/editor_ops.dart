import 'package:flutter/widgets.dart';

/// Text-manipulation helpers shared by the toolbar buttons and hotkeys.
class EditorOps {
  /// Wrap the current selection with [left]/[right] markers.
  static void wrapSelection(
    TextEditingController controller,
    String left,
    String right,
  ) {
    final sel = controller.selection;
    if (!sel.isValid) return;
    final selected = sel.textInside(controller.text);
    controller.value = controller.value.replaced(sel, '$left$selected$right');
  }

  /// Insert [prefix] at the start of the line containing the selection.
  static void prefixLine(TextEditingController controller, String prefix) {
    final sel = controller.selection;
    if (!sel.isValid) return;
    final start = controller.text.lastIndexOf('\n', sel.start - 1) + 1;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(start, start, prefix),
      selection: TextSelection.collapsed(offset: sel.end + prefix.length),
    );
  }
}

/// Checklist helpers for the preview pane.
class Checklist {
  static final _boxPattern = RegExp(r'^(\s*[-*] )\[( |x|X)\]');

  /// Toggle `[ ]`↔`[x]` on the given 0-based line. Returns null when the line
  /// is not a checklist item.
  static String? toggleLine(String body, int line) {
    final lines = body.split('\n');
    if (line < 0 || line >= lines.length) return null;
    final m = _boxPattern.firstMatch(lines[line]);
    if (m == null) return null;
    final checked = m.group(2)!.toLowerCase() == 'x';
    lines[line] = lines[line].replaceRange(
      m.start,
      m.end,
      '${m.group(1)}[${checked ? ' ' : 'x'}]',
    );
    return lines.join('\n');
  }

  /// Rewrite checklist markers as tappable links carrying the line number:
  /// `- [ ] task` → `- [☐](checkbox:5) task`.
  static String linkify(String body) {
    final lines = body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = _boxPattern.firstMatch(lines[i]);
      if (m == null) continue;
      final checked = m.group(2)!.toLowerCase() == 'x';
      lines[i] = lines[i].replaceRange(
        m.start,
        m.end,
        '${m.group(1)}[${checked ? '☑' : '☐'}](checkbox:$i)',
      );
    }
    return lines.join('\n');
  }
}
