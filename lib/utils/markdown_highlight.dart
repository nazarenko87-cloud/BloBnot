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
      spans.add(TextSpan(
        text: line,
        style: base.copyWith(color: p.heading, fontWeight: FontWeight.w700),
      ));
      continue;
    }
    var pos = 0;
    // List markers ("1.", "-", "- [ ]") get the accent colour (v1.0 look).
    final marker = _listMarker.firstMatch(line);
    if (marker != null) {
      if (marker.group(1)!.isNotEmpty) {
        spans.add(TextSpan(text: marker.group(1), style: base));
      }
      spans.add(TextSpan(
        text: marker.group(2),
        style: base.copyWith(color: p.link, fontWeight: FontWeight.w700),
      ));
      pos = marker.end;
    }
    for (final m in _inline.allMatches(line)) {
      if (m.start < pos) continue;
      if (m.start > pos) {
        spans.add(TextSpan(text: line.substring(pos, m.start), style: base));
      }
      final token = m.group(0)!;
      final style = switch (true) {
        _ when m.group(1) != null =>
          base.copyWith(color: p.link, fontWeight: FontWeight.w600),
        _ when m.group(2) != null => base.copyWith(color: p.code),
        _ when m.group(3) != null => base.copyWith(color: p.tag),
        _ when m.group(4) != null =>
          base.copyWith(fontWeight: FontWeight.w700),
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

/// TextEditingController that renders its value with markdown highlighting.
///
/// The highlighted spans are cached and only recomputed when the text or the
/// base style actually changes, so idle repaints (cursor blink, focus) are
/// cheap even for long notes.
class HighlightingTextController extends TextEditingController {
  String? _cacheText;
  TextStyle? _cacheBase;
  List<TextSpan>? _cacheSpans;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    if (_cacheSpans == null || _cacheText != text || _cacheBase != base) {
      final accent = Theme.of(context).colorScheme.primary;
      final palette = HighlightPalette(
        heading: accent,
        link: accent,
        tag: const Color(0xFFE0C24F),
        code: const Color(0xFF7DD8C8),
      );
      _cacheSpans = highlightMarkdown(text, base, palette);
      _cacheText = text;
      _cacheBase = base;
    }
    return TextSpan(children: _cacheSpans);
  }
}
