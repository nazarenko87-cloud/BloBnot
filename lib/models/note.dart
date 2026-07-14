import 'dart:io';

/// A single note backed by a `.md` file in the vault.
///
/// Immutable value type — mutations return new copies (see [copyWith]).
/// Derived values ([outgoingLinks], [tags], [checklistProgress], [wordCount],
/// [bodyLower]) are computed lazily and cached: the body never changes for a
/// given instance, so recomputing them on every rebuild would be wasted work.
class Note {
  final String path; // absolute file path
  final String title; // file name without .md
  final String body; // full markdown text
  final DateTime modified;

  Note({
    required this.path,
    required this.title,
    required this.body,
    required this.modified,
  });

  Note copyWith({
    String? path,
    String? title,
    String? body,
    DateTime? modified,
  }) {
    return Note(
      path: path ?? this.path,
      title: title ?? this.title,
      body: body ?? this.body,
      modified: modified ?? this.modified,
    );
  }

  int? _wordCount;
  int get wordCount => _wordCount ??= body.trim().isEmpty
      ? 0
      : body.trim().split(RegExp(r'\s+')).length;

  /// Estimated reading time in minutes (>=1).
  int get readMinutes => (wordCount / 200).ceil().clamp(1, 9999);

  /// Lower-cased body, cached for search.
  String? _bodyLower;
  String get bodyLower => _bodyLower ??= body.toLowerCase();

  /// Lower-cased title, cached for search/sort.
  String? _titleLower;
  String get titleLower => _titleLower ??= title.toLowerCase();

  static final _linkPattern = RegExp(
    r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]',
  );

  /// Titles referenced via `[[wiki-links]]` in this note's body.
  Set<String>? _outgoingLinks;
  Set<String> get outgoingLinks => _outgoingLinks ??= _linkPattern
      .allMatches(body)
      .map((m) => m.group(1)!.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  static final _tagPattern = RegExp(r'(?:^|\s)#([\wЀ-ӿ-]+)');

  /// `#tags` present in the body (lower-cased, de-duplicated).
  List<String>? _tags;
  List<String> get tags => _tags ??= _tagPattern
      .allMatches(body)
      .map((m) => m.group(1)!.toLowerCase())
      .toSet()
      .toList();

  static final _boxPattern = RegExp(r'^\s*[-*] \[( |x|X)\]', multiLine: true);

  /// Checklist completion 0..1, or null when the note has no checkboxes.
  bool _progressComputed = false;
  double? _checklistProgress;
  double? get checklistProgress {
    if (_progressComputed) return _checklistProgress;
    _progressComputed = true;
    final boxes = _boxPattern.allMatches(body).toList();
    if (boxes.isEmpty) return _checklistProgress = null;
    final done = boxes.where((m) => m.group(1)!.toLowerCase() == 'x').length;
    return _checklistProgress = done / boxes.length;
  }

  static String titleFromPath(String p) {
    final name = p.split(Platform.pathSeparator).last;
    return name.toLowerCase().endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
  }
}
