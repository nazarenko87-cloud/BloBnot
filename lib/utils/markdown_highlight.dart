import 'package:flutter/material.dart';

/// Colours used by the live source highlighter.
class HighlightPalette {
  const HighlightPalette({
    required this.heading,
    required this.link,
    required this.tag,
    required this.code,
  });

  final Color heading;
  final Color link;
  final Color tag;
  final Color code;
}

final _inline = RegExp(
  r'(\[\[[^\]]*\]\])' // wiki link
  r'|(`[^`\n]*`)' // inline code
  r'|((?:(?<=\s)|^)#[\wЀ-ӿ-]+)' // #tag
  r'|(\*\*[^*\n]+\*\*)' // bold
  r'|(\{\{remind:[^}]*\}\})', // line reminder tag
  multiLine: true,
);

final _headingLine = RegExp(r'^#{1,6}\s');
final _listMarker = RegExp(r'^(\s*)(\d+\.|[-*]( \[( |x|X)\])?)(?= )');

/// Split markdown [text] into styled spans (v1.0 live highlighting):
/// headings accent+bold, `[[links]]` accent, `#tags` amber, code teal.
/// The produced spans always concatenate back to exactly [text].
List<TextSpan> highlightMarkdown(
  String text,
  TextStyle base,
  HighlightPalette p,
) {
  final spans = <TextSpan>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = i < lines.length - 1 ? '${lines[i]}\n' : lines[i];
    if (_headingLine.hasMatch(line)) {
      spans.add(
        TextSpan(
          text: line,
          style: base.copyWith(color: p.heading, fontWeight: FontWeight.w700),
        ),
      );
      continue;
    }
    var pos = 0;
    // List markers ("1.", "-", "- [ ]") get the accent colour (v1.0 look).
    final marker = _listMarker.firstMatch(line);
    if (marker != null) {
      if (marker.group(1)!.isNotEmpty) {
        spans.add(TextSpan(text: marker.group(1), style: base));
      }
      spans.add(
        TextSpan(
          text: marker.group(2),
          style: base.copyWith(color: p.link, fontWeight: FontWeight.w700),
        ),
      );
      pos = marker.end;
    }
    for (final m in _inline.allMatches(line)) {
      if (m.start < pos) continue;
      if (m.start > pos) {
        spans.add(TextSpan(text: line.substring(pos, m.start), style: base));
      }
      final token = m.group(0)!;
      final style = switch (true) {
        _ when m.group(1) != null => base.copyWith(
          color: p.link,
          fontWeight: FontWeight.w600,
        ),
        _ when m.group(2) != null => base.copyWith(color: p.code),
        _ when m.group(3) != null => base.copyWith(color: p.tag),
        _ when m.group(4) != null => base.copyWith(fontWeight: FontWeight.w700),
        _ => base.copyWith(color: p.link),
      };
      spans.add(TextSpan(text: token, style: style));
      pos = m.end;
    }
    if (pos < line.length) {
      spans.add(TextSpan(text: line.substring(pos), style: base));
    }
  }
  return spans;
}

final _liveInline = RegExp(
  r'(\[\[[^\]\n]*\]\])' // 1 wiki link
  r'|(\[[^\]\n]+\]\([^)\s]+\))' // 2 markdown link
  r'|(`[^`\n]+`)' // 3 inline code
  r'|(\*\*[^*\n]+\*\*)' // 4 bold
  r'|(~~[^~\n]+~~)' // 5 strikethrough
  r'|((?<![\w*])\*(?![\s*])[^*\n]*?[^\s*]\*(?![\w*])' // 6 italic *x*
  r'|(?<![\w_])_(?![\s_])[^_\n]*?[^\s_]_(?![\w_]))' // 6 italic _x_
  r'|(\{\{remind:[^}]*\}\})' // 7 line reminder tag
  r'|((?:(?<=\s)|^)#[\wЀ-ӿ-]+)', // 8 #tag
  multiLine: true,
);

final _headingMarks = RegExp(r'^(#{1,6}\s+)');
final _doneTask = RegExp(r'^(\s*[-*] \[[xX]\] )');

/// Size of each heading level relative to body text in live preview.
const _headingScale = [1.6, 1.35, 1.18, 1.08, 1.0, 1.0];

/// Lines [first]..[last] (inclusive, 0-based) of the note.
typedef LineRange = ({int first, int last});

/// Live preview: the same text as [highlightMarkdown], but headings are
/// larger and the Markdown marks (`##`, `**`, `[[ ]]`, backticks) are hidden
/// on every line outside [active], where the caret is; there they show,
/// dimmed, for editing. Hidden marks are drawn at a near-zero size rather
/// than removed, so the spans still concatenate back to exactly [text] and
/// every offset lines up with the source.
List<TextSpan> livePreviewMarkdown(
  String text,
  TextStyle base,
  HighlightPalette p, {
  LineRange? active,
}) {
  final hidden = base.copyWith(
    fontSize: 0.01,
    color: const Color(0x00000000),
    letterSpacing: 0,
  );
  final muted = base.copyWith(
    color: (base.color ?? const Color(0xFF888888)).withValues(alpha: 0.45),
  );
  final size = base.fontSize ?? 14;
  final spans = <TextSpan>[];
  final lines = text.split('\n');
  final frontEnd = _frontMatterEnd(lines);
  for (var i = 0; i < lines.length; i++) {
    final line = i < lines.length - 1 ? '${lines[i]}\n' : lines[i];
    final editing = active != null && i >= active.first && i <= active.last;
    final marks = editing ? muted : hidden;
    if (i <= frontEnd) {
      spans.add(
        TextSpan(
          text: line,
          style: muted.copyWith(fontSize: size * 0.9),
        ),
      );
      continue;
    }
    final heading = _headingMarks.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.trim().length;
      spans
        ..add(TextSpan(text: heading.group(1), style: marks))
        ..add(
          TextSpan(
            text: line.substring(heading.end),
            style: base.copyWith(
              color: p.heading,
              fontWeight: FontWeight.w700,
              fontSize: size * _headingScale[level - 1],
            ),
          ),
        );
      continue;
    }
    var pos = 0;
    var body = base;
    final done = _doneTask.firstMatch(line);
    final marker = done ?? _listMarker.firstMatch(line);
    if (marker != null) {
      final indent = done == null ? marker.group(1)! : '';
      if (indent.isNotEmpty) spans.add(TextSpan(text: indent, style: base));
      spans.add(
        TextSpan(
          text: line.substring(indent.length, marker.end),
          style: base.copyWith(color: p.link, fontWeight: FontWeight.w700),
        ),
      );
      pos = marker.end;
      if (done != null) {
        // A ticked task reads as finished: struck through and faded.
        body = muted.copyWith(decoration: TextDecoration.lineThrough);
      }
    }
    for (final m in _liveInline.allMatches(line, pos)) {
      if (m.start < pos) continue;
      if (m.start > pos) {
        spans.add(TextSpan(text: line.substring(pos, m.start), style: body));
      }
      _liveToken(spans, m, body, marks, p);
      pos = m.end;
    }
    if (pos < line.length) {
      spans.add(TextSpan(text: line.substring(pos), style: body));
    }
  }
  return spans;
}

/// Index of the closing `---` of a front-matter block, or -1 when the note
/// has none.
int _frontMatterEnd(List<String> lines) {
  if (lines.isEmpty || lines.first.trim() != '---') return -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') return i;
  }
  return -1;
}

void _liveToken(
  List<TextSpan> spans,
  RegExpMatch m,
  TextStyle body,
  TextStyle marks,
  HighlightPalette p,
) {
  final token = m.group(0)!;
  // Visible text between an [open]-long and a [close]-long mark.
  void wrapped(int open, int close, TextStyle style) {
    spans
      ..add(TextSpan(text: token.substring(0, open), style: marks))
      ..add(
        TextSpan(
          text: token.substring(open, token.length - close),
          style: style,
        ),
      )
      ..add(
        TextSpan(text: token.substring(token.length - close), style: marks),
      );
  }

  final link = body.copyWith(color: p.link, fontWeight: FontWeight.w600);
  if (m.group(1) != null) {
    // [[Note|alias]] shows only the alias.
    final bar = token.indexOf('|');
    wrapped(bar < 0 ? 2 : bar + 1, 2, link);
  } else if (m.group(2) != null) {
    // [text](url) shows only the text.
    final close = token.indexOf('](');
    spans
      ..add(TextSpan(text: '[', style: marks))
      ..add(TextSpan(text: token.substring(1, close), style: link))
      ..add(TextSpan(text: token.substring(close), style: marks));
  } else if (m.group(3) != null) {
    wrapped(
      1,
      1,
      body.copyWith(
        color: p.code,
        backgroundColor: p.code.withValues(alpha: 0.12),
      ),
    );
  } else if (m.group(4) != null) {
    wrapped(2, 2, body.copyWith(fontWeight: FontWeight.w700));
  } else if (m.group(5) != null) {
    wrapped(2, 2, body.copyWith(decoration: TextDecoration.lineThrough));
  } else if (m.group(6) != null) {
    wrapped(1, 1, body.copyWith(fontStyle: FontStyle.italic));
  } else if (m.group(7) != null) {
    spans.add(
      TextSpan(
        text: token,
        style: body.copyWith(color: p.link),
      ),
    );
  } else {
    spans.add(
      TextSpan(
        text: token,
        style: body.copyWith(color: p.tag),
      ),
    );
  }
}

/// TextEditingController that renders its value with markdown highlighting.
///
/// The highlighted spans are cached and only recomputed when the text or the
/// base style actually changes, so idle repaints (cursor blink, focus) are
/// cheap even for long notes.
class HighlightingTextController extends TextEditingController {
  String? _cacheText;
  TextStyle? _cacheBase;
  List<TextSpan>? _cacheSpans;
  Object? _cacheMode;

  bool _live = false;

  /// Render as live preview (see [livePreviewMarkdown]).
  bool get live => _live;
  set live(bool value) {
    if (value == _live) return;
    _live = value;
    notifyListeners();
  }

  bool _editing = false;

  /// Whether the editor has focus: only then does the caret's line show its
  /// Markdown marks.
  set editing(bool value) {
    if (value == _editing) return;
    _editing = value;
    notifyListeners();
  }

  /// Lines the selection touches, while editing.
  LineRange? get _activeLines {
    if (!_editing || !selection.isValid) return null;
    int lineOf(int offset) => _newline
        .allMatches(text.substring(0, offset.clamp(0, text.length)))
        .length;
    return (first: lineOf(selection.start), last: lineOf(selection.end));
  }

  static final _newline = RegExp('\n');

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final Object mode = _live ? (_activeLines ?? 'live') : 'source';
    if (_cacheSpans == null ||
        _cacheText != text ||
        _cacheBase != base ||
        _cacheMode != mode) {
      final accent = Theme.of(context).colorScheme.primary;
      final palette = HighlightPalette(
        heading: accent,
        link: accent,
        tag: const Color(0xFFE0C24F),
        code: const Color(0xFF7DD8C8),
      );
      _cacheSpans = _live
          ? livePreviewMarkdown(
              text,
              base,
              palette,
              active: mode is LineRange ? mode : null,
            )
          : highlightMarkdown(text, base, palette);
      _cacheText = text;
      _cacheBase = base;
      _cacheMode = mode;
    }
    return TextSpan(children: _cacheSpans);
  }
}
