import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/vault_controller.dart';
import '../utils/hot_tasks.dart';
import 'theme.dart';

/// Short running to-dos: an "In progress" column and a "Done" column.
/// Tapping a task strikes it through, stamps the time and moves it to Done;
/// tapping a done task brings it back.
class HotTasksView extends StatefulWidget {
  const HotTasksView({super.key, this.card});

  /// Wraps each panel (desktop passes the shell's floating card).
  final Widget Function(Widget child)? card;

  @override
  State<HotTasksView> createState() => _HotTasksViewState();
}

class _HotTasksViewState extends State<HotTasksView> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Widget _card(Widget child) => widget.card?.call(child) ?? child;

  Future<void> _add() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _inputFocus.requestFocus();
    await runHotAction(
      context,
      context.read<VaultController>().addHotTask(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final open = controller.hotInProgress;
    final done = controller.hotDone;
    final narrow = MediaQuery.sizeOf(context).width < kMobileBreakpoint;
    final gap = narrow ? 8.0 : kShellGap;

    final inProgress = _Column(
      title: 'In progress',
      dot: kHotColor,
      count: open.length,
      showTitle: !narrow,
      child: _InProgressList(tasks: open),
    );
    final doneColumn = _Column(
      title: 'Done',
      dot: kTagGreen,
      count: done.length,
      showTitle: !narrow,
      footer: const _ArchiveFooter(),
      child: _DoneList(tasks: done, highlightId: controller.lastCompletedHotId),
    );

    final header = _card(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // On a phone the app bar already carries the title.
            if (!narrow)
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department, color: kHotColor, size: 26),
                  SizedBox(width: 8),
                  Text(
                    'Hot tasks',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: TextField(
                key: const Key('hot-input'),
                controller: _input,
                focusNode: _inputFocus,
                maxLength: 200,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: 'New task — what needs doing?',
                  counterText: '',
                  isDense: true,
                  prefixIcon: const Icon(Icons.add_task, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Add task (Enter)',
                    icon: const Icon(Icons.arrow_upward, color: kHotColor),
                    onPressed: _add,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final error = controller.hotError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: gap),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error),
              ),
            ),
          ),
        SizedBox(height: gap),
        Expanded(
          child: narrow
              ? DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      _card(
                        TabBar(
                          tabs: [
                            Tab(text: 'In progress · ${open.length}'),
                            Tab(text: 'Done · ${done.length}'),
                          ],
                        ),
                      ),
                      SizedBox(height: gap),
                      Expanded(
                        child: TabBarView(
                          children: [_card(inProgress), _card(doneColumn)],
                        ),
                      ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 23, child: _card(inProgress)),
                    SizedBox(width: gap),
                    Expanded(flex: 20, child: _card(doneColumn)),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Awaits a hot-task change and reports a failed save instead of losing it
/// silently.
Future<void> runHotAction(BuildContext context, Future<void> action) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action;
  } on Exception catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Could not save hot tasks: $e')),
    );
  }
}

/// Right-click (or long-press on a touch screen) menu for a task: edit its
/// text in place, or delete it. [at] is the pointer position; without one
/// the menu opens over the task itself. [onEdit] switches the row into its
/// inline editor.
Future<void> showHotTaskMenu(
  BuildContext context,
  HotTask task,
  Offset? at, {
  required VoidCallback onEdit,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final box = context.findRenderObject() as RenderBox?;
  if (overlay == null || box == null) return;
  final origin =
      at ?? box.localToGlobal(box.size.center(Offset.zero), ancestor: overlay);
  final position = RelativeRect.fromRect(
    origin & const Size(1, 1),
    Offset.zero & overlay.size,
  );
  final controller = context.read<VaultController>();
  final choice = await showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(
        value: 'edit',
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18, color: kHotColor),
            const SizedBox(width: 10),
            const Text('Edit task'),
          ],
        ),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 18),
            SizedBox(width: 10),
            Text('Delete task'),
          ],
        ),
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'delete') {
    await runHotAction(context, controller.deleteHotTask(task.id));
    return;
  }
  onEdit();
}

/// Edits a task's text right where it sits in the list. Enter or clicking
/// elsewhere saves; Esc cancels. Owns its controller, so the field stays
/// valid for as long as it is on screen.
class _InlineTaskEditor extends StatefulWidget {
  const _InlineTaskEditor({
    required this.initial,
    required this.onDone,
    this.style,
  });

  final String initial;
  final TextStyle? style;

  /// Called once: with the new text, or null when editing was cancelled.
  final ValueChanged<String?> onDone;

  @override
  State<_InlineTaskEditor> createState() => _InlineTaskEditorState();
}

class _InlineTaskEditorState extends State<_InlineTaskEditor> {
  late final _field = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode();
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(_field.text);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _finish(String? text) {
    if (_finished) return;
    _finished = true;
    widget.onDone(text);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
      },
      child: TextField(
        key: const Key('hot-edit-field'),
        controller: _field,
        focusNode: _focus,
        autofocus: true,
        maxLength: 200,
        style: widget.style,
        textInputAction: TextInputAction.done,
        onSubmitted: _finish,
        onTapOutside: (_) => _focus.unfocus(),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: accent, width: 1.5),
          ),
          helperText: 'Enter to save · Esc to cancel',
          helperStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.dot,
    required this.count,
    required this.child,
    required this.showTitle,
    this.footer,
  });

  final String title;
  final Color dot;
  final int count;
  final Widget child;
  final bool showTitle;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const Spacer(),
                Text(
                  '$count',
                  key: Key('hot-count-$title'),
                  style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        Expanded(child: child),
        ?footer,
      ],
    );
  }
}

class _InProgressList extends StatelessWidget {
  const _InProgressList({required this.tasks});

  final List<HotTask> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const _Empty('All done. Add a new task above.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      children: [
        for (final t in tasks) _InProgressTile(key: ValueKey(t.id), task: t),
      ],
    );
  }
}

class _InProgressTile extends StatefulWidget {
  const _InProgressTile({super.key, required this.task});

  final HotTask task;

  @override
  State<_InProgressTile> createState() => _InProgressTileState();
}

class _InProgressTileState extends State<_InProgressTile> {
  bool _completing = false;
  bool _hover = false;
  bool _editing = false;

  void _startEditing() => setState(() => _editing = true);

  void _finishEditing(String? text) {
    setState(() => _editing = false);
    if (text == null) return;
    runHotAction(
      context,
      context.read<VaultController>().editHotTask(widget.task.id, text),
    );
  }

  Future<void> _complete() async {
    if (_completing || _editing) return;
    setState(() => _completing = true);
    final instant = MediaQuery.of(context).disableAnimations;
    final controller = context.read<VaultController>();
    // Let the strike-through play before the task leaves the column.
    await Future<void>.delayed(Duration(milliseconds: instant ? 0 : 450));
    if (!mounted) return;
    await runHotAction(context, controller.completeHotTask(widget.task.id));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    final instant = MediaQuery.of(context).disableAnimations;
    final duration = Duration(milliseconds: instant ? 0 : 320);
    final created = widget.task.created;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _editing ? null : _complete,
          onSecondaryTapDown: _editing
              ? null
              : (d) => showHotTaskMenu(
                  context,
                  widget.task,
                  d.globalPosition,
                  onEdit: _startEditing,
                ),
          onLongPress: _editing
              ? null
              : () => showHotTaskMenu(
                  context,
                  widget.task,
                  null,
                  onEdit: _startEditing,
                ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: duration,
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _completing ? kTagGreen : Colors.transparent,
                    border: Border.all(
                      color: _completing ? kTagGreen : kHotColor,
                      width: 2,
                    ),
                  ),
                  child: _completing
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editing
                      ? Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: _InlineTaskEditor(
                            initial: widget.task.text,
                            style: const TextStyle(fontSize: 15),
                            onDone: _finishEditing,
                          ),
                        )
                      : TweenAnimationBuilder<double>(
                          tween: Tween(end: _completing ? 1 : 0),
                          duration: duration,
                          builder: (context, t, _) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              widget.task.text,
                              style: TextStyle(
                                fontSize: 15,
                                color: Color.lerp(scheme.onSurface, muted, t),
                                decoration: t > 0
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: muted.withValues(alpha: t),
                                decorationThickness: 2,
                              ),
                            ),
                          ),
                        ),
                ),
                if (created != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8),
                    child: Text(
                      hotAddedLabel(created, DateTime.now()),
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ),
                // Hover-only on desktop, but a hidden button must not stay
                // clickable; touch screens have no hover, so show it there.
                Visibility(
                  visible:
                      !_completing &&
                      !_editing &&
                      (_hover ||
                          MediaQuery.sizeOf(context).width < kMobileBreakpoint),
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    tooltip: 'Delete task',
                    iconSize: 18,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    color: muted,
                    icon: const Icon(Icons.close),
                    onPressed: _completing
                        ? null
                        : () => runHotAction(
                            context,
                            context.read<VaultController>().deleteHotTask(
                              widget.task.id,
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
}

class _DoneList extends StatelessWidget {
  const _DoneList({required this.tasks, required this.highlightId});

  final List<HotTask> tasks;
  final int? highlightId;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const _Empty('Nothing done yet.');
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final now = DateTime.now();
    final children = <Widget>[];
    String? lastDay;
    for (final t in tasks) {
      final day = dayLabel(t.done!, now);
      if (day != lastDay) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Text(
              day,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        );
        lastDay = day;
      }
      children.add(
        _DoneTile(key: ValueKey(t.id), task: t, highlight: t.id == highlightId),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: children,
    );
  }
}

class _DoneTile extends StatefulWidget {
  const _DoneTile({super.key, required this.task, required this.highlight});

  final HotTask task;
  final bool highlight;

  @override
  State<_DoneTile> createState() => _DoneTileState();
}

class _DoneTileState extends State<_DoneTile> {
  bool _editing = false;

  void _startEditing() => setState(() => _editing = true);

  void _finishEditing(String? text) {
    setState(() => _editing = false);
    if (text == null) return;
    runHotAction(
      context,
      context.read<VaultController>().editHotTask(widget.task.id, text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final instant = MediaQuery.of(context).disableAnimations;
    final done = task.done!;
    final created = task.created;
    final time =
        '${done.hour.toString().padLeft(2, '0')}:${done.minute.toString().padLeft(2, '0')}';
    return TweenAnimationBuilder<double>(
      // Plays once, when the just-completed task arrives.
      tween: Tween(begin: widget.highlight && !instant ? 1 : 0, end: 0),
      duration: const Duration(milliseconds: 1200),
      builder: (context, glow, child) => Material(
        color: kTagGreen.withValues(alpha: 0.18 * glow),
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _editing
            ? null
            : () => runHotAction(
                context,
                context.read<VaultController>().reopenHotTask(task.id),
              ),
        onSecondaryTapDown: _editing
            ? null
            : (d) => showHotTaskMenu(
                context,
                task,
                d.globalPosition,
                onEdit: _startEditing,
              ),
        onLongPress: _editing
            ? null
            : () => showHotTaskMenu(context, task, null, onEdit: _startEditing),
        child: Tooltip(
          message: 'Back to in progress',
          waitDuration: const Duration(milliseconds: 600),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: kTagGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 13, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editing
                      ? _InlineTaskEditor(
                          initial: task.text,
                          style: const TextStyle(fontSize: 14),
                          onDone: _finishEditing,
                        )
                      : Text(
                          task.text,
                          style: TextStyle(
                            fontSize: 14,
                            color: muted,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: muted,
                          ),
                        ),
                ),
                if (created != null && !_editing)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'added ${hotAddedLabel(created, DateTime.now())}',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: kTagGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    time,
                    style: const TextStyle(
                      fontSize: 12,
                      color: kTagGreen,
                      fontFeatures: [FontFeature.tabularFigures()],
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
}

class _ArchiveFooter extends StatelessWidget {
  const _ArchiveFooter();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Done tasks move to the archive after 30 days',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          TextButton(
            onPressed: () => _showArchive(context),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  Future<void> _showArchive(BuildContext context) {
    final load = context.read<VaultController>().loadHotArchive();
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hot tasks archive'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: FutureBuilder<List<HotTask>>(
            future: load,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Could not read the archive: ${snap.error}');
              }
              final tasks = snap.data;
              if (tasks == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (tasks.isEmpty) {
                return const _Empty('Nothing archived yet.');
              }
              return ListView(
                children: [
                  for (final t in tasks)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.check_circle,
                        color: kTagGreen,
                        size: 18,
                      ),
                      title: Text(t.text),
                      trailing: Text(formatHotStamp(t.done!)),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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

/// When a task was added, short: "09:15" today, "Yesterday 18:40", else
/// "Sep 18 11:05".
String hotAddedLabel(DateTime added, DateTime now) {
  final time =
      '${added.hour.toString().padLeft(2, '0')}:'
      '${added.minute.toString().padLeft(2, '0')}';
  final date = '${_months[added.month - 1]} ${added.day}';
  // Always the date too — "09:15" alone is ambiguous once a list spans days.
  // The year only appears when it is not the current one.
  final year = added.year == now.year ? '' : ' ${added.year}';
  return '$date$year, $time';
}

/// "Today", "Yesterday", else e.g. "Thu, Sep 18".
String dayLabel(DateTime d, DateTime now) {
  // UTC calendar days: local midnights across a DST change are 23 or 25 hours
  // apart, which would make inDays round the wrong way.
  final day = DateTime.utc(d.year, d.month, d.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

/// Rail/drawer badge with the number of tasks in progress.
class HotBadge extends StatelessWidget {
  const HotBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: kHotColor,
      textColor: Colors.white,
      label: Text('$count'),
      child: child,
    );
  }
}
