import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/tray_service.dart';
import 'state/vault_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// App version string surfaced in the About dialog. Keep in sync with pubspec.
const String kAppVersion = '2.0';

/// Tray/notifications singleton, initialized in [main] on desktop.
TrayService? trayService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = VaultController();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    trayService = TrayService(onHidden: controller.lockNow);
    await trayService!.init();
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
