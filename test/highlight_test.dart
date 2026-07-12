import 'package:blobnot/utils/markdown_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = TextStyle(fontSize: 14);
const _p = HighlightPalette(
  heading: Colors.cyan,
  link: Colors.cyan,
  tag: Colors.amber,
  code: Colors.teal,
);

String _joined(List<TextSpan> spans) =>
    spans.map((s) => s.text ?? '').join();

void main() {
  test('spans always reassemble to the exact source text', () {
    const text =
        '# Head\nplain [[Link|x]] and `code` more\n#tag end\n**bold** {{remind:2026-01-01T09:00}}';
    expect(_joined(highlightMarkdown(text, _base, _p)), text);
  });

  test('heading line gets heading colour and bold', () {
    final spans = highlightMarkdown('# Title\nbody', _base, _p);
    expect(spans.first.text, '# Title\n');
    expect(spans.first.style?.color, Colors.cyan);
    expect(spans.first.style?.fontWeight, FontWeight.w700);
  });

  test('wiki link, tag and code get their palette colours', () {
    final spans =
        highlightMarkdown('a [[Note]] b #help c `x` d', _base, _p);
    TextSpan find(String t) => spans.firstWhere((s) => s.text == t);
    expect(find('[[Note]]').style?.color, Colors.cyan);
    expect(find('#help').style?.color, Colors.amber);
    expect(find('`x`').style?.color, Colors.teal);
  });

  test('hash inside a word is not a tag', () {
    final spans = highlightMarkdown('word#notag', _base, _p);
    expect(spans.length, 1);
    expect(spans.single.style?.color, isNot(Colors.amber));
  });
}
