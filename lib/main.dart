import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/vault_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// App version string surfaced in the About dialog. Keep in sync with pubspec.
const String kAppVersion = '2.0';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = VaultController();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Needed for the Fullscreen toggle in the rail. No close-interception or
    // tray icon here on purpose — that used to cost several seconds of
    // native shutdown latency (measured) for a tray+system-toast feature
    // set that's no longer worth the cost.
    await windowManager.ensureInitialized();
  }
  runApp(
    ChangeNotifierProvider.value(
      value: controller..bootstrap(),
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
        styleId: s.themeStyle,
        accentIndex: s.accentIndex,
        dark: false,
      ),
      darkTheme: buildTheme(
        styleId: s.themeStyle,
        accentIndex: s.accentIndex,
        dark: true,
      ),
      themeMode: themeModeOf(s.themeMode),
      home: const HomePage(),
    );
  }
}
