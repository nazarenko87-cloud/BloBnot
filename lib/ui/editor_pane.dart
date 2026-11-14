import 'dart:async';
import 'dart:io';
import 'dart:ui' show BoxHeightStyle;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../services/attachment_store.dart';
import '../services/export_service.dart';
import '../services/settings_store.dart';
import '../state/vault_controller.dart';
import '../utils/editor_ops.dart';
import '../utils/line_reminders.dart';
import '../utils/markdown_highlight.dart';
import '../utils/properties.dart';
import 'focus_mode.dart';
import 'sticker_picker.dart';
import 'theme.dart';

part 'editor_line_numbers.dart';
part 'editor_panels.dart';
part 'editor_toolbar.dart';

enum ViewMode { edit, split, preview }

class EditorPane extends StatefulWidget {
  const EditorPane({super.key});

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  final _textController = HighlightingTextController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  ViewMode _mode = ViewMode.edit;
  String? _loadedPath;
  bool _findVisible = false;

  /// Body shown in the preview pane, refreshed on a 200ms debounce so the
  /// Markdown tree is not re-parsed on every keystroke.
  String _previewBody = '';
  Timer? _previewTimer;
  bool _dropActive = false;
  StreamSubscription<String>? _inserts;

  @override
  void initState() {
    super.initState();
    // Live preview reveals the Markdown marks only on the caret's line, and
    // only while the editor has focus.
    _focus.addListener(() => _textController.editing = _focus.hasFocus);
    _textController.live = context.read<VaultController>().settings.livePreview;
    _inserts = context.read<VaultController>().insertRequests.listen((text) {
      if (!mounted) return;
      _insertAtCursor(text);
      _commitText();
    });
  }

  @override
  void dispose() {
    _inserts?.cancel();
    _previewTimer?.cancel();
    _textController.dispose();
    _scroll.dispose();
    _focus.dispose();
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  void _commitText() {
    context.read<VaultController>().editCurrentBody(_textController.text);
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted && _previewBody != _textController.text) {
        setState(() => _previewBody = _textController.text);
      }
    });
  }

  /// Keep the caret's line inside the visible viewport of the outer
  /// [_scroll] view. The `TextField` here is unbounded (`expands: false`
  /// inside a `SingleChildScrollView`) so it never scrolls itself as the
  /// note grows — without this, typing past the bottom of a small window
  /// wrote new lines the toolbar/panels below the editor were covering.
  void _ensureCaretVisible(double scale) {
    if (!_scroll.hasClients) return;
    final sel = _textController.selection;
    final editable = _editable();
    if (!sel.isValid || editable == null) return;
    final caret = editable.getLocalRectForCaret(
      TextPosition(
        offset: sel.baseOffset.clamp(0, _textController.text.length),
      ),
    );
    // The editable starts at the top of the scrolled content.
    final caretTop = caret.top;
    final caretBottom = caret.bottom;
    final position = _scroll.position;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    const margin = 8.0;
    if (caretBottom + margin > viewBottom) {
      _scroll.animateTo(
        (caretBottom + margin - position.viewportDimension).clamp(
          0,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (caretTop - margin < viewTop) {
      _scroll.animateTo(
        (caretTop - margin).clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  /// The laid-out text of the editor, for caret and line positions.
  RenderEditable? _editable() {
    final root = _fieldKey.currentContext?.findRenderObject();
    if (root == null) return null;
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// Replace the whole body from outside the TextField (checkbox toggles,
  /// find&replace) and persist.
  void _setBody(String body) {
    _textController.text = body;
    _previewBody = body; // immediate — these are discrete edits
    _commitText();
  }

  int _loadedReload = 0;

  /// A note also changed on another device: say where the other version
  /// went, once, after this frame.
  void _showConflictNotice(VaultController controller) {
    final notice = controller.conflictNotice;
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.conflictNotice != notice) return;
      controller.clearConflictNotice();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notice), duration: const Duration(seconds: 8)),
      );
    });
  }

  /// Sync the text field when the selected note changes (but not on our own
  /// edits, which would move the cursor) — or when the vault was re-read and
  /// the file may hold a newer copy from another device. A reload writes any
  /// pending edit first, so taking the file's text then loses nothing.
  void _syncFrom(Note? note, int reloadCount, {bool dirty = false}) {
    if (note == null) {
      _textController.clear();
      _loadedPath = null;
      _previewBody = '';
      return;
    }
    if (note.path != _loadedPath) {
      _textController.text = note.body;
      _previewBody = note.body;
      _loadedPath = note.path;
      _loadedReload = reloadCount;
    } else if (reloadCount != _loadedReload && !dirty) {
      // While an edit is buffered the editor holds the newer text (typed
      // during the reload); its pending save will write it out.
      _loadedReload = reloadCount;
      if (_textController.text != note.body) {
        final caret = _textController.selection.baseOffset;
        _textController.text = note.body;
        _textController.selection = TextSelection.collapsed(
          offset: caret.clamp(0, note.body.length),
        );
        _previewBody = note.body;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final note = controller.current;
    _syncFrom(note, controller.reloadCount, dirty: controller.isDirty);
    _showConflictNotice(controller);

    if (note == null) {
      return const Center(child: Text('No note selected'));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          EditorOps.wrapSelection(_textController, '**', '**');
          _commitText();
        },
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          EditorOps.wrapSelection(_textController, '*', '*');
          _commitText();
        },
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          EditorOps.wrapSelection(_textController, '[[', ']]');
          _commitText();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          setState(() => _findVisible = !_findVisible);
        },
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: () {
          final toolbar = _Toolbar(
            controller: _textController,
            onChanged: _commitText,
            onAttach: () => _attachFile(context),
            onSticker: () => _pickSticker(context),
            onAddField: _addField,
            onExportHtml: () => _export(context, note, ExportService.toHtml),
            onExportPdf: () => _export(context, note, ExportService.toPdf),
            onAiContext: () => _copyAiContext(context, note),
            onLinkPicker: () => _pickLink(context),
          );
          final body = Expanded(
            child: DropTarget(
              onDragDone: (detail) => _attachPaths(
                context,
                detail.files.map((f) => f.path).toList(),
              ),
              onDragEntered: (_) => setState(() => _dropActive = true),
              onDragExited: (_) => setState(() => _dropActive = false),
              child: Stack(
                children: [
                  Positioned.fill(child: _body(context, note)),
                  if (_dropActive)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.12),
                          alignment: Alignment.center,
                          child: const Text(
                            'Drop files to attach',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
          // Focus mode keeps the text and its header; panels and the toolbar
          // go (the shortcuts — Ctrl+B, Ctrl+I, Ctrl+K — still work).
          final focus = FocusModeScope.maybeOf(context)?.active ?? false;
          final rest = [
            if (_findVisible) _findBar(context),
            const Divider(height: 1),
            body,
            if (!focus) ...[
              _BacklinksPanel(note: note),
              _AttachmentsPanel(
                note: note,
                onAttach: () => _attachFile(context),
                onDeleted: (name) => _setBody(
                  AttachmentStore.stripLink(_textController.text, name),
                ),
              ),
            ],
          ];
          // Thumb-reachable: on a phone the formatting toolbar sits at the
          // bottom instead of just under the header.
          final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
          return [
            _header(context, controller, note),
            if (!isMobile && !focus) toolbar,
            ...rest,
            if (isMobile) toolbar,
          ];
        }(),
      ),
    );
  }

  Widget _findBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Find',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _replaceController,
              decoration: const InputDecoration(
                hintText: 'Replace with',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              final find = _findController.text;
              if (find.isEmpty) return;
              final count = find.allMatches(_textController.text).length;
              if (count > 0) {
                _setBody(
                  _textController.text.replaceAll(
                    find,
                    _replaceController.text,
                  ),
                );
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Replaced $count occurrence(s)')),
              );
            },
            child: const Text('Replace all'),
          ),
          IconButton(
            tooltip: 'Close (Ctrl+H)',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _findVisible = false),
          ),
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    Note note,
    Future<String> Function(Note) exporter,
  ) async {
    try {
      final path = await exporter(note);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved: $path')));
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  /// Copy this note plus every note it wiki-links to as one plain-text block,
  /// ready to paste into any AI chat (v1.3 "Copy AI context").
  Future<void> _copyAiContext(BuildContext context, Note note) async {
    final controller = context.read<VaultController>();
    final buf = StringBuffer('# ${note.title}\n\n${note.body}\n');
    for (final title in note.outgoingLinks) {
      for (final n in controller.notes) {
        if (n.title == title) {
          buf.write('\n---\n# ${n.title} (linked)\n\n${n.body}\n');
          break;
        }
      }
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI context copied to clipboard')),
      );
    }
  }

  /// Fires when the user has just typed `[[`: opens the note picker so the
  /// link can be completed inline (autocomplete).
  Future<void> _maybeAutocomplete(BuildContext context) async {
    final sel = _textController.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final caret = sel.start;
    final text = _textController.text;
    if (caret < 2 || text.substring(caret - 2, caret) != '[[') return;
    // Skip if this `[[` is already closed just ahead.
    if (caret <= text.length - 2 && text.substring(caret, caret + 2) == ']]') {
      return;
    }
    final title = await _chooseNoteTitle(context);
    if (title == null || !mounted) return;
    // `[[` is already typed — insert `title]]` after the caret.
    final at = _textController.selection.baseOffset.clamp(0, text.length);
    final insert = '$title]]';
    _textController.text = _textController.text.replaceRange(at, at, insert);
    _textController.selection = TextSelection.collapsed(
      offset: at + insert.length,
    );
    _commitText();
  }

  /// Note picker for the link button when nothing is selected: choose a note
  /// and `[[Title]]` is inserted at the cursor.
  Future<void> _pickLink(BuildContext context) async {
    final title = await _chooseNoteTitle(context);
    if (title == null || title.isEmpty) return;
    final link = '[[$title]]';
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      link,
    );
    _textController.selection = TextSelection.collapsed(
      offset: offset + link.length,
    );
    _commitText();
  }

  /// Shared searchable note picker; returns the chosen title or null.
  Future<String?> _chooseNoteTitle(BuildContext context) async {
    final controller = context.read<VaultController>();
    final searchCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link to note'),
        contentPadding: const EdgeInsets.all(12),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            final q = searchCtrl.text.toLowerCase();
            final matches = controller.notes
                .where(
                  (n) =>
                      n.path != controller.current?.path &&
                      n.title.toLowerCase().contains(q),
                )
                .take(10)
                .toList();
            return SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search notes…',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                    onSubmitted: (_) {
                      if (matches.isNotEmpty) {
                        Navigator.pop(context, matches.first.title);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  for (final n in matches)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined, size: 16),
                      title: Text(n.title),
                      onTap: () => Navigator.pop(context, n.title),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _insertLineReminder(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    final tag = LineReminders.buildTag(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.end : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      offset,
      ' $tag',
    );
    _textController.selection = TextSelection.collapsed(
      offset: offset + tag.length + 1,
    );
    _commitText();
  }

  Future<void> _pickSticker(BuildContext context) async {
    final controller = context.read<VaultController>();
    final asset = await showStickerPicker(context);
    if (asset == null) return;
    final snippet = '![sticker]($asset)';
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      snippet,
    );
    _textController.selection = TextSelection.collapsed(
      offset: offset + snippet.length,
    );
    controller.editCurrentBody(_textController.text);
  }

  // Reminder bell and Edit/Split/Preview: 15% over Material's 24 and 18.
  static const double _headerIconSize = 27.6;
  static const double _modeIconSize = 20.7;

  /// Below this header width the word count and status icons are dropped.
  static const double _metaMinWidth = 400;

  Widget _header(BuildContext context, VaultController controller, Note note) {
    final reminder = controller.reminderFor(note.title);
    // On mobile the note title already sits in the AppBar — showing it again
    // here would just duplicate it and burn scarce vertical space.
    final isMobile = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final shell = Theme.of(context).extension<ShellStyle>();
    final focus = FocusModeScope.maybeOf(context);
    final muted = Colors.grey.shade500;
    // One line: title, then the small facts after it. The file path used to
    // take a line of its own; it is in the copy button's tooltip now.
    final meta = [
      Flexible(
        child: Text(
          '${note.wordCount} words · ${note.readMinutes} min'
          '${reminder != null ? '  ·  🔔 ${_fmt(reminder)}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ),
      // Save indicator (icon-only; label in the tooltip).
      if (controller.saveError case final error?)
        Tooltip(
          message: '$error\nRetrying…',
          child: Icon(
            Icons.error_outline,
            size: 13,
            color: Theme.of(context).colorScheme.error,
          ),
        )
      else
        Tooltip(
          message: controller.isDirty ? 'Saving…' : 'Saved',
          child: Icon(
            controller.isDirty ? Icons.sync : Icons.check_circle,
            size: 13,
            color: controller.isDirty
                ? muted
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      // Copyable file path (v1.3): click puts it on the clipboard.
      Tooltip(
        message:
            '${_breadcrumb(controller.vaultRoot, note.path)}\n'
            'Click to copy the file path',
        child: InkWell(
          key: const Key('copy-note-path'),
          borderRadius: BorderRadius.circular(4),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: note.path));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Path copied')));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.copy, size: 12, color: muted),
          ),
        ),
      ),
    ];
    // The focus button only where the header has room for it.
    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
        child: Row(
          children: [
            // Title and facts share what the buttons leave; both shorten
            // with an ellipsis rather than push the buttons off the card. A
            // very narrow card keeps the title alone.
            Expanded(
              child: Row(
                children: [
                  if (!isMobile)
                    Flexible(
                      flex: 3,
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: shell?.serifTitles ?? false
                              ? 'Georgia'
                              : null,
                          fontFamilyFallback: shell?.serifTitles ?? false
                              ? kMastheadFontFallback
                              : null,
                        ),
                      ),
                    ),
                  if (isMobile || box.maxWidth >= _metaMinWidth) ...[
                    if (!isMobile) const SizedBox(width: 12),
                    for (final m in meta) ...[m, const SizedBox(width: 6)],
                  ],
                ],
              ),
            ),
            if (focus != null && (focus.active || box.maxWidth >= 560))
              IconButton(
                key: const Key('focus-toggle'),
                tooltip: focus.active
                    ? 'Leave focus mode (Esc)'
                    : 'Focus mode (Ctrl+.)',
                icon: Icon(
                  focus.active ? Icons.close_fullscreen : Icons.open_in_full,
                  size: 20,
                ),
                onPressed: focus.toggle,
              ),
            PopupMenuButton<String>(
              tooltip: 'Reminders',
              iconSize: _headerIconSize,
              icon: Icon(
                reminder == null
                    ? Icons.notifications_none
                    : Icons.notifications_active,
                color: reminder == null
                    ? null
                    : Theme.of(context).colorScheme.primary,
              ),
              onSelected: (v) => switch (v) {
                'note' => _editReminder(context, controller, note, reminder),
                'line' => _insertLineReminder(context),
                _ => null,
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'note',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.sticky_note_2_outlined, size: 18),
                    title: Text('Reminder on note'),
                  ),
                ),
                PopupMenuItem(
                  value: 'line',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.alarm_add, size: 18),
                    title: Text('Reminder on line (at cursor)'),
                  ),
                ),
              ],
            ),
            // Bounded so the FittedBox actually scales it down on narrow cards.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 152),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: SegmentedButton<ViewMode>(
                  // Side by side has no room on a phone.
                  segments: [
                    const ButtonSegment(
                      value: ViewMode.edit,
                      icon: Icon(Icons.edit),
                      tooltip: 'Edit',
                    ),
                    if (!isMobile)
                      const ButtonSegment(
                        value: ViewMode.split,
                        icon: Icon(Icons.vertical_split),
                        tooltip: 'Edit and preview side by side',
                      ),
                    const ButtonSegment(
                      value: ViewMode.preview,
                      icon: Icon(Icons.visibility),
                      tooltip: 'Preview',
                    ),
                  ],
                  selected: {
                    isMobile && _mode == ViewMode.split ? ViewMode.edit : _mode,
                  },
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    iconSize: WidgetStatePropertyAll(_modeIconSize),
                    minimumSize: WidgetStatePropertyAll(Size(0, 46)),
                  ),
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Breadcrumb like "Vault / Project / Note.md" from an absolute path.
  static String _breadcrumb(String? vaultRoot, String path) {
    if (vaultRoot == null || !path.startsWith(vaultRoot)) return path;
    final rel = path
        .substring(vaultRoot.length)
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    final vaultName = vaultRoot
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .last;
    return [vaultName, ...rel].join('  /  ');
  }

  static String _fmt(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _editReminder(
    BuildContext context,
    VaultController controller,
    Note note,
    DateTime? existing,
  ) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: existing ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) {
      // Allow clearing an existing reminder by cancelling the date picker.
      if (existing != null && context.mounted) {
        final clear = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove reminder?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (clear == true) await controller.clearReminder(note.title);
      }
      return;
    }
    if (!context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(existing ?? now),
    );
    if (time == null) return;
    await controller.setReminder(
      note.title,
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }

  Future<void> _attachFile(BuildContext context) async {
    final file = await openFile();
    if (file == null || !context.mounted) return;
    await _attachPaths(context, [file.path]);
  }

  /// Copy one or more files into the vault's attachments and insert links
  /// at the cursor. Shared by the picker button and drag-drop.
  Future<void> _attachPaths(BuildContext context, List<String> paths) async {
    final controller = context.read<VaultController>();
    final root = controller.vaultRoot;
    if (root == null) return;
    final store = AttachmentStore(root);
    final links = StringBuffer();
    for (final path in paths) {
      links.write(_linkFor(await store.add(path)));
    }
    _insertAtCursor(links.toString());
    controller.editCurrentBody(_textController.text);
  }

  static const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp'};

  /// Markdown snippet for an attachment already saved under [name] — an
  /// image embed for picture types, a plain file link otherwise. Shared by
  /// the file picker/drag-drop path and the clipboard-paste path.
  static String _linkFor(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.')).toLowerCase()
        : '';
    final encoded = 'attachments/${Uri.encodeComponent(name)}';
    return _imageExts.contains(ext)
        ? '![$name]($encoded)\n'
        : '[📎 $name]($encoded)\n';
  }

  /// Opens a new `key: value` line in the note's fields block — creating the
  /// block at the top when there is none — and puts the caret on it.
  void _addField() {
    final text = _textController.text;
    final front = parseFrontMatter(text);
    final lines = text.split('\n');
    final int caretLine;
    if (front.hasBlock) {
      caretLine = front.lineCount - 1; // just above the closing fence
      lines.insert(caretLine, '');
    } else {
      lines.insertAll(0, ['---', '', '---']);
      caretLine = 1;
    }
    final caret = lines
        .take(caretLine)
        .fold<int>(0, (sum, l) => sum + l.length + 1);
    _textController.text = lines.join('\n');
    _textController.selection = TextSelection.collapsed(offset: caret);
    _commitText();
    if (_mode == ViewMode.preview) setState(() => _mode = ViewMode.edit);
    _focus.requestFocus();
  }

  void _insertAtCursor(String text) {
    final sel = _textController.selection;
    final offset = sel.isValid ? sel.start : _textController.text.length;
    _textController.text = _textController.text.replaceRange(
      offset,
      sel.isValid ? sel.end : offset,
      text,
    );
    _textController.selection = TextSelection.collapsed(
      offset: offset + text.length,
    );
  }

  /// Overrides the TextField's default Ctrl+V: an image on the clipboard
  /// (e.g. a screenshot) is saved into the vault's attachments and inserted
  /// inline, exactly like a dragged-in file; plain text falls back to the
  /// normal paste.
  Future<void> _handlePaste(BuildContext context) async {
    final image = await Pasteboard.image;
    if (!context.mounted) return;
    if (image != null) {
      final controller = context.read<VaultController>();
      final root = controller.vaultRoot;
      if (root == null) return;
      final store = AttachmentStore(root);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final name = await store.addBytes('screenshot-$stamp.png', image);
      _insertAtCursor(_linkFor(name));
      controller.editCurrentBody(_textController.text);
      _schedulePreview();
      return;
    }
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.isEmpty) return;
    _insertAtCursor(text);
    _commitText();
  }

  Widget _body(BuildContext context, Note note) {
    final phone = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final mode = phone && _mode == ViewMode.split ? ViewMode.edit : _mode;
    return switch (mode) {
      ViewMode.edit => _editor(context),
      ViewMode.preview => _preview(note),
      ViewMode.split => Row(
        children: [
          Expanded(child: _editor(context)),
          const VerticalDivider(width: 1),
          Expanded(child: _preview(note)),
        ],
      ),
    };
  }

  Widget _editor(BuildContext context) {
    final controller = context.read<VaultController>();
    final settings = context.select<VaultController, VaultSettings>(
      (c) => c.settings,
    );
    final scale = settings.editorScale;
    if (_textController.live != settings.livePreview) {
      // Not during build: the setter notifies the text field.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _textController.live = settings.livePreview,
      );
    }
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        // Bottom padding keeps the last line clear of whatever sits right
        // below the editor (attachments/backlinks panels, or the toolbar on
        // a narrow/mobile window) instead of the caret writing flush against
        // the very edge of the visible area.
        padding: const EdgeInsets.only(bottom: 32),
        child: _readable(
          settings,
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (settings.lineNumbers)
                  _LineNumbers(
                    text: _textController,
                    scale: scale,
                    editable: _editable,
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Actions(
                      // Overrides the TextField's built-in Ctrl+V — an image
                      // on the clipboard is saved as an attachment instead of
                      // being silently ignored/pasted as nothing.
                      actions: <Type, Action<Intent>>{
                        PasteTextIntent: CallbackAction<PasteTextIntent>(
                          onInvoke: (intent) {
                            _handlePaste(context);
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        key: _fieldKey,
                        controller: _textController,
                        focusNode: _focus,
                        // Whole-row selection boxes: they also give the line
                        // numbers each row's true height.
                        selectionHeightStyle: BoxHeightStyle.max,
                        maxLines: null,
                        expands: false,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          height: 1.5,
                          fontSize: 14 * scale,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                        // Right-click menu gains "Reminder on line…".
                        contextMenuBuilder: (context, editableTextState) =>
                            AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editableTextState.contextMenuAnchors,
                              buttonItems: [
                                ...editableTextState.contextMenuButtonItems,
                                ContextMenuButtonItem(
                                  label: 'Reminder on line…',
                                  onPressed: () {
                                    ContextMenuController.removeAny();
                                    _insertLineReminder(context);
                                  },
                                ),
                              ],
                            ),
                        onChanged: (v) {
                          controller.editCurrentBody(v);
                          _schedulePreview();
                          _maybeAutocomplete(context);
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _ensureCaretVisible(scale),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// At most about 100 characters per line, centred, when the window is
  /// wider than that and the setting is on.
  Widget _readable(VaultSettings settings, Widget child) {
    if (!settings.readableWidth) return child;
    // Average glyph width is about 0.6 em; plus line numbers and padding.
    final maxWidth = 100 * 14 * settings.editorScale * 0.6 + 80;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  Widget _preview(Note note) {
    final settings = context.select<VaultController, VaultSettings>(
      (c) => c.settings,
    );
    final scale = settings.editorScale;
    // Render the debounced body (not note.body) so parsing is throttled.
    final source = _previewBody;
    final linked = LineReminders.linkify(Checklist.linkify(source))
        .replaceAllMapped(
          RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
          (m) => '**${(m.group(2) ?? m.group(1))!.trim()}**',
        );
    // The fields block is shown as a card above the text, not as raw lines.
    // Linkify keeps line counts, so dropping the block's lines from the
    // rendered text leaves checkbox line numbers pointing at `source`.
    final front = parseFrontMatter(source);
    final rendered = front.hasBlock
        ? linked.split('\n').skip(front.lineCount).join('\n')
        : linked;
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: _readable(
        settings,
        // One selection over the whole preview, so a drag runs across
        // paragraphs, lists and headings and Ctrl+C / right-click copies it.
        // Markdown's own `selectable` makes each block a separate field.
        SelectionArea(
          key: const Key('preview-selection'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (front.properties.isNotEmpty)
                _PropertiesCard(properties: front.properties),
              Expanded(child: _markdown(rendered, source)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _markdown(String rendered, String source) {
    return Markdown(
      data: rendered,
      padding: const EdgeInsets.all(16),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (text, href, title) {
        if (href == null || !href.startsWith('checkbox:')) return;
        final line = int.tryParse(href.substring('checkbox:'.length));
        if (line == null) return;
        // Toggle against the rendered source so the line index matches.
        final toggled = Checklist.toggleLine(source, line);
        if (toggled != null) _setBody(toggled);
      },
      sizedImageBuilder: (config) {
        final src = config.uri.toString();
        if (src.startsWith('assets/stickers/')) {
          // Small squircle emoji-style tile — the sticker art is already a
          // square face with no baked-in caption, so just fit it in.
          return ClipRSuperellipse(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Image.asset(src, fit: BoxFit.contain),
            ),
          );
        }
        if (src.startsWith('assets/')) {
          return Image.asset(src, width: 72, height: 72);
        }
        if (src.startsWith('attachments/')) {
          final root = context.read<VaultController>().vaultRoot;
          if (root == null) return Text(config.alt ?? src);
          final name = Uri.decodeComponent(
            src.substring('attachments/'.length),
          );
          final file = File(AttachmentStore(root).pathOf(name));
          return _AttachmentThumbnail(file: file, alt: config.alt ?? name);
        }
        return Text(config.alt ?? src);
      },
    );
  }
}
