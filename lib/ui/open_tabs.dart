import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/vault_controller.dart';

/// Row of tabs for the notes currently open, with the active one highlighted.
/// Hidden when only one (or no) note is open.
class OpenTabs extends StatelessWidget {
  const OpenTabs({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final tabs = controller.openTabs;
    if (tabs.length < 2) return const SizedBox.shrink();
    final accent = Theme.of(context).colorScheme.primary;
    final currentPath = controller.current?.path;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, i) {
          final note = tabs[i];
          final active = note.path == currentPath;
          return InkWell(
            onTap: () => controller.select(note),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 180),
              padding: const EdgeInsets.only(left: 12, right: 4),
              decoration: BoxDecoration(
                color: active ? accent.withValues(alpha: 0.12) : null,
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color: active ? accent : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? accent : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close tab',
                    iconSize: 14,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    icon: const Icon(Icons.close),
                    onPressed: () => controller.closeTab(note.path),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
