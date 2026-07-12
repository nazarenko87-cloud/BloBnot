import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/vault_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// App version string surfaced in the About dialog. Keep in sync with pubspec.
const String kAppVersion = '1.3.0';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => VaultController()..bootstrap(),
      child: const BloBnotApp(),
    ),
  );
}

class BloBnotApp extends StatelessWidget {
  const BloBnotApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<VaultController>().settings;
    return MaterialApp(
      title: 'BloBnot',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        dark: s.themeMode != 'light',
        accentIndex: s.accentIndex,
      ),
      home: const HomePage(),
    );
  }
}
