import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/backup_service.dart';
import '../state/vault_controller.dart';
import 'theme.dart';

/// App settings (original v1.3 layout): theme mode + style, accent, glyph
/// style, editor font size, notes storage with backup, password.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final s = controller.settings;
    final accent = Theme.of(context).colorScheme.primary;

    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Section('Theme'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'system',
                    icon: Icon(Icons.settings_suggest, size: 16),
                    label: Text('System'),
                  ),
                  ButtonSegment(
                    value: 'light',
                    icon: Icon(Icons.light_mode, size: 16),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: 'dark',
                    icon: Icon(Icons.dark_mode, size: 16),
                    label: Text('Dark'),
                  ),
                ],
                selected: {s.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => controller.setTheme(mode: v.first),
              ),
              const SizedBox(height: 14),
              const _Section('Theme style'),
              Wrap(
                spacing: 8,
                children: [
                  for (final st in kThemeStyles)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => controller.setTheme(style: st.id),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 40,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                width: 2,
                                color: s.themeStyle == st.id
                                    ? accent
                                    : Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child:
                                            Container(color: st.darkScaffold),
                                      ),
                                      Expanded(
                                        child:
                                            Container(color: st.darkSurface),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child:
                                            Container(color: st.lightScaffold),
                                      ),
                                      Expanded(
                                        child:
                                            Container(color: st.lightSurface),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(st.label, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const _Section('Accent color'),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < kAccents.length; i++)
                    InkWell(
                      borderRadius: BorderRadius.circular(99),
                      onTap: () => controller.setTheme(accent: i),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: kAccents[i],
                          shape: BoxShape.circle,
                          border: s.accentIndex == i
                              ? Border.all(width: 3, color: Colors.white)
                              : null,
                        ),
                        child: s.accentIndex == i
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.black87,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const _Section('Glyph style'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'ring',
                    icon: Icon(Icons.circle_outlined, size: 16),
                    label: Text('Ring'),
                  ),
                  ButtonSegment(
                    value: 'fill',
                    icon: Icon(Icons.circle, size: 16),
                    label: Text('Fill'),
                  ),
                  ButtonSegment(
                    value: 'tint',
                    icon: Icon(Icons.square_rounded, size: 16),
                    label: Text('Tint'),
                  ),
                ],
                selected: {s.glyphStyle},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    controller.setTheme(glyphStyle: v.first),
              ),
              const SizedBox(height: 14),
              const _Section('Editor font size'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: s.editorScale.clamp(0.8, 1.6),
                      min: 0.8,
                      max: 1.6,
                      divisions: 8,
                      onChanged: (v) => controller.setTheme(editorScale: v),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('${(s.editorScale * 100).round()}%'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const _Section('Notes storage'),
              Text(
                'A folder of .md files. Point it at a folder synced by '
                'Google Drive to access your notes on your phone too.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 6),
              Text(
                controller.vaultRoot ?? '(no vault selected)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: accent),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Choose folder…'),
                    onPressed: () async {
                      final dir = await getDirectoryPath();
                      if (dir != null && context.mounted) {
                        await context.read<VaultController>().openVault(dir);
                      }
                    },
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.archive_outlined, size: 18),
                    label: const Text('Backup vault (.zip)'),
                    onPressed: () => _backup(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _Section('Security'),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text('Password…'),
                onPressed: () => _passwordDialog(context),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _backup(BuildContext context) async {
    final root = context.read<VaultController>().vaultRoot;
    if (root == null) return;
    try {
      final path = await BackupService.backupVault(root);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved: $path')),
        );
      }
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _passwordDialog(BuildContext context) async {
    final controller = context.read<VaultController>();
    final store = controller.passwordStore;
    final has = await store.hasPassword();
    if (!context.mounted) return;

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(has ? 'Change password' : 'Set password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (has)
              TextField(
                controller: currentCtrl,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Current password'),
              ),
            TextField(
              controller: newCtrl,
              obscureText: true,
              autofocus: !has,
              decoration: const InputDecoration(
                labelText: 'New password (empty = remove)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (action != 'save' || !context.mounted) return;

    if (has && !await store.verify(currentCtrl.text)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong current password')),
        );
      }
      return;
    }
    if (newCtrl.text.isEmpty) {
      await store.clearPassword();
    } else {
      await store.setPassword(newCtrl.text);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newCtrl.text.isEmpty
                ? 'Password removed'
                : 'Password set — app will lock on next launch',
          ),
        ),
      );
    }
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
