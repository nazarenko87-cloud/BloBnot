import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';

/// Row of tabs for the notes currently open, with the active one highlighted.
/// Hidden when only one (or no) note is open.
///
/// With many notes open the row scrolls: the mouse wheel moves it sideways,
/// the active tab is scrolled into view when it changes, and once the tabs
/// overflow a "▾" button lists them all. Middle-click closes a tab.
class OpenTabs extends StatefulWidget {
  const OpenTabs({super.key});

  @override
  State<OpenTabs> createState() => _OpenTabsState();
}

class _OpenTabsState extends State<OpenTabs> {
  final _scroll = ScrollController();
  final _activeKey = GlobalKey();
  String? _lastActive;
  bool _overflow = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bring the active tab into view when the selection changes.
  void _revealActive(String? path) {
    if (path == null || path == _lastActive) return;
    _lastActive = path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// A vertical wheel notch scrolls the (horizontal) row.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    _scroll.jumpTo((position.pixels + delta).clamp(0, position.maxScrollExtent));
  }

  bool _onMetrics(ScrollMetricsNotification n) {
    final overflow = n.metrics.maxScrollExtent > 0.5;
    if (overflow != _overflow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _overflow = overflow);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final tabs = controller.openTabs;
    if (tabs.length < 2) return const SizedBox.shrink();
    final currentPath = controller.current?.path;
    _revealActive(currentPath);

    // Rounded pill tabs floating at the top of the editor card (v2.0 look).
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: _onMetrics,
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final note in tabs) ...[
                        _Tab(
                          key: note.path == currentPath ? _activeKey : null,
                          note: note,
                          active: note.path == currentPath,
                          onSelect: () => controller.select(note),
                          onClose: () => controller.closeTab(note.path),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_overflow)
            PopupMenuButton<Note>(
              tooltip: 'All open notes (${tabs.length})',
              icon: const Icon(Icons.expand_more, size: 20),
              onSelected: controller.select,
              itemBuilder: (context) => [
                for (final note in tabs)
                  CheckedPopupMenuItem<Note>(
                    value: note,
                    checked: note.path == currentPath,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.note,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final Note note;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTertiaryTapUp: (_) => onClose(),
      child: Material(
        color: active
            ? accent.withValues(alpha: 0.14)
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onSelect,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.only(left: 12, right: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? accent : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close tab',
                  iconSize: 13,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
