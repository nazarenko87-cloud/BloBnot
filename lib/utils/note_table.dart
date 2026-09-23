/// Filtering and sorting for the table view, kept free of Flutter so it can
/// be tested on its own.
library;

import '../models/note.dart';
import 'properties.dart';

/// Built-in columns, alongside the note's own fields.
const kColTitle = '__title';
const kColProject = '__project';
const kColModified = '__modified';

class TableQuery {
  const TableQuery({
    this.text = '',
    this.project,
    this.filters = const {},
    this.sortBy = kColModified,
    this.ascending = false,
    this.onlyWithFields = true,
  });

  /// Free text, matched against the title and every field value.
  final String text;

  /// Only notes in this project folder ('' = vault root); null = all.
  final String? project;

  /// field (lower-case) → exact value (case-insensitive), all must match.
  final Map<String, String> filters;

  final String sortBy;
  final bool ascending;

  /// Hide notes that have no fields at all.
  final bool onlyWithFields;
}

String? _fieldOf(Note n, String key) {
  final lower = key.toLowerCase();
  for (final e in n.properties.entries) {
    if (e.key.toLowerCase() == lower) return e.value;
  }
  return null;
}

/// The value a cell shows for [column].
String? cellValue(Note n, String column, String Function(Note) projectOf) =>
    switch (column) {
      kColTitle => n.title,
      kColProject => projectOf(n),
      kColModified => n.modified.toIso8601String(),
      _ => _fieldOf(n, column),
    };

List<Note> queryNotes(
  List<Note> notes,
  TableQuery q,
  String Function(Note) projectOf,
) {
  final text = q.text.trim().toLowerCase();
  final rows = notes.where((n) {
    if (q.onlyWithFields && n.properties.isEmpty) return false;
    if (q.project != null && projectOf(n) != q.project) return false;
    for (final f in q.filters.entries) {
      final v = _fieldOf(n, f.key);
      if (v == null || v.toLowerCase() != f.value.toLowerCase()) return false;
    }
    if (text.isNotEmpty) {
      final hay = [n.title, ...n.properties.values].join('\n').toLowerCase();
      if (!hay.contains(text)) return false;
    }
    return true;
  }).toList();

  rows.sort((a, b) {
    final c = q.sortBy == kColModified
        ? a.modified.compareTo(b.modified)
        : compareFieldValues(
            cellValue(a, q.sortBy, projectOf),
            cellValue(b, q.sortBy, projectOf),
          );
    // Empty cells stay last whichever way the column is sorted.
    final aEmpty = (cellValue(a, q.sortBy, projectOf) ?? '').isEmpty;
    final bEmpty = (cellValue(b, q.sortBy, projectOf) ?? '').isEmpty;
    if (aEmpty != bEmpty) return aEmpty ? 1 : -1;
    final ordered = q.ascending ? c : -c;
    return ordered != 0 ? ordered : a.titleLower.compareTo(b.titleLower);
  });
  return rows;
}
