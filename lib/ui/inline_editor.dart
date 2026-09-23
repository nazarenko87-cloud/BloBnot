import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Edits a piece of text right where it is shown — a hot task, a table cell —
/// instead of in a pop-up. Enter or clicking elsewhere saves; Esc cancels.
/// Owns its controller, so the field stays valid for as long as it is on
/// screen.
class InlineTextEditor extends StatefulWidget {
  const InlineTextEditor({
    super.key,
    required this.initial,
    required this.onDone,
    this.style,
    this.helperText = 'Enter to save · Esc to cancel',
    this.hintText,
    this.fieldKey = const Key('hot-edit-field'),
    this.maxLength = 200,
  });

  final String initial;
  final TextStyle? style;
  final String? helperText;
  final String? hintText;
  final Key fieldKey;
  final int maxLength;

  /// Called once: with the new text, or null when editing was cancelled.
  final ValueChanged<String?> onDone;

  @override
  State<InlineTextEditor> createState() => _InlineTextEditorState();
}

class _InlineTextEditorState extends State<InlineTextEditor> {
  late final _field = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode();
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_field.text);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish(String? text) {
    if (_finished) return;
    _finished = true;
    widget.onDone(text);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        key: widget.fieldKey,
        controller: _field,
        focusNode: _focus,
        autofocus: true,
        maxLength: widget.maxLength,
        style: widget.style,
        textInputAction: TextInputAction.done,
        onSubmitted: _finish,
        onTapOutside: (_) => _focus.unfocus(),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          hintText: widget.hintText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          helperText: widget.helperText,
          helperStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}
