import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/utils/markdown_highlight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _palette = HighlightPalette(
  heading: Colors.blue,
  link: Colors.indigo,
  tag: Colors.amber,
  code: Colors.teal,
);
const _base = TextStyle(fontSize: 14);

List<TextSpan> _live(String text, {LineRange? active}) =>
    livePreviewMarkdown(text, _base, _palette, active: active);

String _joined(List<TextSpan> spans) => spans.map((s) => s.text).join();

/// The text a reader actually sees: spans drawn at a real size.
String _visible(List<TextSpan> spans) =>
    spans.where((s) => (s.style?.fontSize ?? 14) > 1).map((s) => s.text).join();

void main() {
  const note =
      '---\nstatus: open\n---\n# Title\n\nSome **bold**, *italic* and '
      '`code`.\n- [[Plan|the plan]] and [[Ideas]] #todo\n'
      '- [x] done task\n[site](https://example.com) ~~old~~';

  test('spans always add up to the exact source text', () {
    expect(_joined(_live(note)), note);
    for (var line = 0; line < 9; line++) {
      expect(_joined(_live(note, active: (first: line, last: line))), note);
    }
  });

  test('marks are hidden away from the caret', () {
    final visible = _visible(_live(note));
    expect(visible, contains('Title'));
    expect(visible, isNot(contains('# Title')));
    expect(visible, contains('Some bold, italic and code.'));
    expect(visible, contains('the plan and Ideas'));
    expect(visible, isNot(contains('[[')));
    expect(visible, isNot(contains('Plan|')));
    expect(visible, contains('site'));
    expect(visible, isNot(contains('https://example.com')));
    expect(visible, contains('old'));
    expect(visible, isNot(contains('~~')));
  });

  test("the caret's line shows its marks", () {
    // Line 5 is the "Some **bold**" line.
    final visible = _visible(_live(note, active: (first: 5, last: 5)));
    expect(visible, contains('**bold**'));
    expect(visible, contains('`code`'));
    // Other lines stay clean.
    expect(visible, isNot(contains('# Title')));
  });

  test('headings are larger, by level', () {
    final spans = _live('# One\n## Two\nbody');
    double sizeOf(String text) =>
        spans.firstWhere((s) => s.text!.startsWith(text)).style!.fontSize!;
    expect(sizeOf('One'), greaterThan(sizeOf('Two')));
    expect(sizeOf('Two'), greaterThan(14));
  });

  test('a ticked task is struck through', () {
    final spans = _live('- [x] done task');
    final task = spans.firstWhere((s) => s.text == 'done task');
    expect(task.style!.decoration, TextDecoration.lineThrough);
  });

  test('editor settings default on and survive a round trip', () {
    const defaults = VaultSettings();
    expect(defaults.livePreview, isTrue);
    expect(defaults.readableWidth, isTrue);
    expect(defaults.lineNumbers, isTrue);
    final off = VaultSettings.fromJson(
      defaults
          .copyWith(
            livePreview: false,
            readableWidth: false,
            lineNumbers: false,
          )
          .toJson(),
    );
    expect(off.livePreview, isFalse);
    expect(off.readableWidth, isFalse);
    expect(off.lineNumbers, isFalse);
    // Settings saved by an older version keep the new defaults.
    expect(VaultSettings.fromJson(const {}).livePreview, isTrue);
  });
}
