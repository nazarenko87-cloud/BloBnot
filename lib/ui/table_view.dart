import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';
import '../utils/note_table.dart';
import 'inline_editor.dart';
import 'theme.dart';

/// Every note that has fields, as a table: one row per note, one column per
/// field. Sort by any column, filter by text, project or a cell's value, and
/// edit a value right in its cell — it is written back to the note's `---`
/// block.
class NoteTableView extends StatefulWidget {
  const NoteTableView({super.key, required this.onOpenNote, this.card});

  /// Called after a note is selected from the table, to show the editor.
  final VoidCallback onOpenNote;

  /// Wraps each panel (desktop passes the shell's floating card).
  final Widget Function(Widget child)? card;

  @override
  State<NoteTableView> createState() => _NoteTableViewState();
}

class _NoteTableViewState extends State<NoteTableView> {
  final _search = TextEditingController();
  String? _project;
  final Map<String, String> _filters = {};
  String _sortBy = kColModified;
  bool _ascending = false;
  bool _onlyWithFields = true;

  /// Columns added here that no note uses yet.
  final List<String> _extraColumns = [];
  bool _addingColumn = false;

  /// The cell being edited: note path + field.
  ({String path, String key})? _editing;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _card(Widget child) => widget.card?.call(child) ?? child;

  void _sort(String column) {
    setState(() {
      if (_sortBy == column) {
        _ascending = !_ascending;
      } else {
        _sortBy = column;
        _ascending = column != kColModified;
      }
    });
  }

  void _filterBy(String key, String value) =>
      setState(() => _filters[key.toLowerCase()] = value);

  Future<void> _saveCell(Note note, String key, String? value) async {
    setState(() => _editing = null);
    if (value == null) return;
    final controller = context.read<VaultController>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await controller.setNoteProperty(note.path, key, value.trim());
    } on Exception catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not save the field: $e')),
      );
    }
  }

  void _open(Note note) {
    context.read<VaultController>().select(note);
    widget.onOpenNote();
  }

  Future<void> _cellMenu(
    Note note,
    String key,
    String? value,
    Offset at,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final hasValue = value != null && value.isNotEmpty;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'edit', child: Text('Edit value')),
        if (hasValue)
          PopupMenuItem(
            value: 'filter',
            child: Text('Show only $key = $value'),
          ),
        if (hasValue)
          const PopupMenuItem(value: 'clear', child: Text('Clear value')),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        setState(() => _editing = (path: note.path, key: key));
      case 'filter':
        _filterBy(key, value!);
      case 'clear':
        await _saveCell(note, key, '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    String projectOf(Note n) => controller.projectOf(n);
    final rows = queryNotes(
      controller.notes,
      TableQuery(
        text: _search.text,
        project: _project,
        filters: _filters,
        sortBy: _sortBy,
        ascending: _ascending,
        onlyWithFields: _onlyWithFields,
      ),
      projectOf,
    );
    // Only the fields the visible rows use: filtering to products shows price
    // and stock, not a column of dashes for every report field.
    final used = {
      for (final n in rows)
        for (final k in n.properties.keys) k.toLowerCase(),
    };
    final keys = [
      for (final k in controller.propertyKeys)
        if (used.contains(k.toLowerCase())) k,
      for (final k in _extraColumns)
        if (!controller.propertyKeys.any(
          (p) => p.toLowerCase() == k.toLowerCase(),
        ))
          k,
    ];
    final narrow = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final gap = narrow ? 8.0 : kShellGap;

    final header = _card(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!narrow)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.table_chart_outlined, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Table',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            SizedBox(
              width: 260,
              child: TextField(
                key: const Key('table-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search titles and fields',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            DropdownButton<String?>(
              value: _project,
              hint: const Text('All projects'),
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All projects'),
                ),
                const DropdownMenuItem(value: '', child: Text('Vault root')),
                for (final p in controller.projects)
                  DropdownMenuItem(value: p, child: Text(p)),
              ],
              onChanged: (v) => setState(() => _project = v),
            ),
            FilterChip(
              key: const Key('table-only-fields'),
              label: const Text('Only notes with fields'),
              selected: _onlyWithFields,
              selectedColor: scheme.primary.withValues(alpha: 0.16),
              checkmarkColor: scheme.primary,
              onSelected: (v) => setState(() => _onlyWithFields = v),
            ),
            if (_addingColumn)
              SizedBox(
                width: 180,
                child: InlineTextEditor(
                  initial: '',
                  hintText: 'Field name',
                  helperText: null,
                  maxLength: 40,
                  fieldKey: const Key('table-new-column'),
                  onDone: (name) => setState(() {
                    _addingColumn = false;
                    final n = name?.trim().replaceAll(':', '') ?? '';
                    if (n.isNotEmpty && !keys.contains(n)) {
                      _extraColumns.add(n);
                      _onlyWithFields = false;
                    }
                  }),
                ),
              )
            else
              TextButton.icon(
                onPressed: () => setState(() => _addingColumn = true),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add field'),
              ),
          ],
        ),
      ),
    );

    final chips = _filters.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in _filters.entries)
                InputChip(
                  label: Text('${f.key} = ${f.value}'),
                  onDeleted: () => setState(() => _filters.remove(f.key)),
                ),
            ],
          );

    final Widget body;
    if (rows.isEmpty) {
      body = _EmptyTable(
        hasAnyFields: controller.propertyKeys.isNotEmpty,
        filtered:
            _filters.isNotEmpty || _search.text.isNotEmpty || _project != null,
      );
    } else {
      DataColumn col(String id, String label) => DataColumn(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onSort: (_, _) => _sort(id),
      );
      final columns = [
        col(kColTitle, 'Note'),
        for (final k in keys) col(k, k),
        col(kColProject, 'Project'),
        col(kColModified, 'Modified'),
      ];
      final sortIndex = [
        kColTitle,
        ...keys,
        kColProject,
        kColModified,
      ].indexWhere((c) => c.toLowerCase() == _sortBy.toLowerCase());

      DataCell fieldCell(Note note, String key) {
        final value = note.properties.entries
            .where((e) => e.key.toLowerCase() == key.toLowerCase())
            .map((e) => e.value)
            .firstOrNull;
        final editing = _editing?.path == note.path && _editing?.key == key;
        if (editing) {
          return DataCell(
            SizedBox(
              width: 180,
              child: InlineTextEditor(
                initial: value ?? '',
                helperText: null,
                fieldKey: Key('cell-${note.title}-$key'),
                onDone: (v) => _saveCell(note, key, v),
              ),
            ),
          );
        }
        return DataCell(
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (d) =>
                _cellMenu(note, key, value, d.globalPosition),
            onLongPressStart: (d) =>
                _cellMenu(note, key, value, d.globalPosition),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 60, maxWidth: 240),
              child: Text(
                value == null || value.isEmpty ? '—' : value,
                overflow: TextOverflow.ellipsis,
                style: value == null || value.isEmpty
                    ? TextStyle(color: muted.withValues(alpha: 0.35))
                    : null,
              ),
            ),
          ),
          onTap: () => setState(() => _editing = (path: note.path, key: key)),
        );
      }

      final table = DataTable(
        key: const Key('note-table'),
        sortColumnIndex: sortIndex < 0 ? null : sortIndex,
        sortAscending: _ascending,
        headingRowHeight: 44,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 64,
        columnSpacing: 28,
        showCheckboxColumn: false,
        columns: columns,
        rows: [
          for (final note in rows)
            DataRow(
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(
                      note.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () => _open(note),
                ),
                for (final k in keys) fieldCell(note, k),
                DataCell(
                  Text(
                    projectOf(note).isEmpty ? '—' : projectOf(note),
                    style: TextStyle(color: muted),
                  ),
                ),
                DataCell(
                  Text(
                    _shortDate(note.modified),
                    style: TextStyle(
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
      body = Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: table,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (chips != null) ...[SizedBox(height: gap), chips],
        SizedBox(height: gap),
        Expanded(
          child: _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '${rows.length} ${rows.length == 1 ? 'note' : 'notes'}'
                    '  ·  click a value to edit, right-click to filter',
                    key: const Key('table-count'),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day}, '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _EmptyTable extends StatelessWidget {
  const _EmptyTable({required this.hasAnyFields, required this.filtered});

  final bool hasAnyFields;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    if (filtered || hasAnyFields) {
      return Center(
        child: Text('No notes match.', style: TextStyle(color: muted)),
      );
    }
    final code = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.06);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined, size: 40, color: muted),
            const SizedBox(height: 12),
            const Text(
              'No notes have fields yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a block like this at the very top of a note, or use the\n'
              'Fields button in the editor toolbar:',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: code,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '---\nmanager: Oleg\nstatus: needs fixes\nscore: 4\n---',
                style: TextStyle(fontFamily: 'monospace', height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
