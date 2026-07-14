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

    // Rounded pill tabs floating at the top of the editor card (v2.0 look).
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final note = tabs[i];
          final active = note.path == currentPath;
          return Material(
            color: active
                ? accent.withValues(alpha: 0.14)
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => controller.select(note),
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
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? accent : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close tab',
                      iconSize: 13,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.closeTab(note.path),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
