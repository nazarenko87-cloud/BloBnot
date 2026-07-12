import 'dart:io';

/// A single note backed by a `.md` file in the vault.
///
/// Immutable value type — mutations return new copies (see [copyWith]).
class Note {
  final String path; // absolute file path
  final String title; // file name without .md
  final String body; // full markdown text
  final DateTime modified;

  const Note({
    required this.path,
    required this.title,
    required this.body,
    required this.modified,
  });

  Note copyWith({String? path, String? title, String? body, DateTime? modified}) {
    return Note(
      path: path ?? this.path,
      title: title ?? this.title,
      body: body ?? this.body,
      modified: modified ?? this.modified,
    );
  }

  int get wordCount =>
      body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;

  /// Estimated reading time in minutes (>=1).
  int get readMinutes => (wordCount / 200).ceil().clamp(1, 9999);

  static final _linkPattern = RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]');

  /// Titles referenced via `[[wiki-links]]` in this note's body.
  Set<String> get outgoingLinks => _linkPattern
      .allMatches(body)
      .map((m) => m.group(1)!.trim())
      .where((s) => s.isNotEmpty)
      .toSet();

  static String titleFromPath(String p) {
    final name = p.split(Platform.pathSeparator).last;
    return name.toLowerCase().endsWith('.md')
        ? name.substring(0, name.length - 3)
        : name;
  }
}
