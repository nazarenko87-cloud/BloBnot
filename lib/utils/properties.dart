/// Note properties ("fields"): simple `key: value` lines in a block fenced by
/// `---` at the very top of a note — the front-matter format Obsidian and
/// most Markdown tools understand, so the fields survive outside BloBnot.
///
/// ```markdown
/// ---
/// manager: Oleg
/// status: needs fixes
/// score: 4
/// ---
/// # Weekly report check
/// ```
///
/// Only flat `key: value` pairs are understood. Anything else inside the
/// block (comments, nested YAML) is left exactly as it is when a field is
/// written, so hand-written front matter is never damaged.
library;

class FrontMatter {
  const FrontMatter({
    required this.properties,
    required this.lineCount,
    required this.hasBlock,
  });

  /// Fields in the order they appear. Keys keep their original spelling.
  final Map<String, String> properties;

  /// Lines the block occupies, fences included; 0 when there is no block.
  final int lineCount;

  final bool hasBlock;

  static const empty = FrontMatter(
    properties: {},
    lineCount: 0,
    hasBlock: false,
  );
}

final _keyValue = RegExp(r'^([A-Za-zЀ-ӿ0-9_][\wЀ-ӿ .\-]*?)\s*:\s*(.*)$');

bool _isFence(String line) => line.trimRight() == '---';

/// The closing fence's line index, or -1 when the note has no block.
int _closingFence(List<String> lines) {
  if (lines.isEmpty || !_isFence(lines.first)) return -1;
  for (var i = 1; i < lines.length; i++) {
    if (_isFence(lines[i])) return i;
  }
  return -1;
}

/// A value as written: surrounding quotes removed.
String _unquote(String v) {
  final t = v.trim();
  if (t.length >= 2 &&
      ((t.startsWith('"') && t.endsWith('"')) ||
          (t.startsWith("'") && t.endsWith("'")))) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

FrontMatter parseFrontMatter(String body) {
  final lines = body.split('\n');
  final close = _closingFence(lines);
  if (close < 0) return FrontMatter.empty;
  final props = <String, String>{};
  for (final raw in lines.sublist(1, close)) {
    final m = _keyValue.firstMatch(raw.trimRight());
    if (m == null) continue;
    props[m.group(1)!.trim()] = _unquote(m.group(2)!);
  }
  return FrontMatter(properties: props, lineCount: close + 1, hasBlock: true);
}

/// The note without its front-matter block (what a reader sees).
String stripFrontMatter(String body) {
  final fm = parseFrontMatter(body);
  if (!fm.hasBlock) return body;
  return body.split('\n').skip(fm.lineCount).join('\n');
}

/// A value safe to write on one line: newlines folded, and quoted when it
/// would otherwise be misread (leading/trailing space, or a `#` comment).
String _encode(String value) {
  final v = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
  final needsQuotes =
      v != v.trim() || v.contains(' #') || v.startsWith('#') || v == '---';
  return needsQuotes ? '"${v.replaceAll('"', "'")}"' : v;
}

/// Set [key] to [value], adding the block or the line as needed. An empty
/// [value] removes the field; the block goes too once it holds nothing.
/// Keys match case-insensitively, keeping the note's own spelling.
String setProperty(String body, String key, String value) {
  final k = key.trim();
  if (k.isEmpty) return body;
  final lines = body.split('\n');
  final close = _closingFence(lines);
  final remove = value.trim().isEmpty;

  if (close < 0) {
    if (remove) return body;
    return ['---', '$k: ${_encode(value)}', '---', ...lines].join('\n');
  }

  final inner = lines.sublist(1, close);
  var found = false;
  final updated = <String>[];
  for (final raw in inner) {
    final m = _keyValue.firstMatch(raw.trimRight());
    if (m != null && m.group(1)!.trim().toLowerCase() == k.toLowerCase()) {
      found = true;
      if (!remove) updated.add('${m.group(1)!.trim()}: ${_encode(value)}');
      continue;
    }
    updated.add(raw);
  }
  if (!found && !remove) updated.add('$k: ${_encode(value)}');

  final rest = lines.sublist(close + 1);
  if (updated.every((l) => l.trim().isEmpty)) {
    return rest.join('\n');
  }
  return ['---', ...updated, '---', ...rest].join('\n');
}

/// Numeric value for sorting, when a field holds a number ("4", "12.5",
/// "4,5").
double? numericValue(String v) =>
    double.tryParse(v.trim().replaceFirst(',', '.'));

/// Sort order for table cells: numbers by value, dates (YYYY-MM-DD) and text
/// alphabetically, empty always last.
int compareFieldValues(String? a, String? b) {
  final ea = a == null || a.isEmpty;
  final eb = b == null || b.isEmpty;
  if (ea || eb) return ea == eb ? 0 : (ea ? 1 : -1);
  final na = numericValue(a);
  final nb = numericValue(b);
  if (na != null && nb != null) return na.compareTo(nb);
  return a.toLowerCase().compareTo(b.toLowerCase());
}
