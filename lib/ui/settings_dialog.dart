import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/vault_controller.dart';
import 'theme.dart';

/// App settings: vault folder, theme (mode + accent), launch password.
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

    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Section('Vault'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    controller.vaultRoot ?? '(no vault selected)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
              ],
            ),
            const SizedBox(height: 16),
            const _Section('Theme'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'dark',
                  icon: Icon(Icons.dark_mode, size: 16),
                  label: Text('Petrol dark'),
                ),
                ButtonSegment(
                  value: 'light',
                  icon: Icon(Icons.light_mode, size: 16),
                  label: Text('Paper light'),
                ),
              ],
              selected: {s.themeMode == 'light' ? 'light' : 'dark'},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  controller.setTheme(mode: v.first),
            ),
            const SizedBox(height: 12),
            const Text('Accent', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
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
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.black87)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const _Section('Security'),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Password…'),
              onPressed: () => _passwordDialog(context),
            ),
          ],
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
