import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/external_files_controller.dart';
import 'state/vault_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// App version string surfaced in the About dialog. Keep in sync with pubspec.
const String kAppVersion = '2.3';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = VaultController();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Needed for the Fullscreen toggle in the rail. No close-interception or
    // tray icon here on purpose — that used to cost several seconds of
    // native shutdown latency (measured) for a tray+system-toast feature
    // set that's no longer worth the cost.
    await windowManager.ensureInitialized();
    if (Platform.isWindows) {
      // Hide the plain black OS title bar (it didn't match the app's theme
      // or accent colour at all) and replace it with a themed one built in
      // _WindowsShell below.
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(titleBarStyle: TitleBarStyle.hidden),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    }
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller..bootstrap()),
        ChangeNotifierProvider(create: (_) => ExternalFilesController()),
      ],
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
      home: Platform.isWindows
          ? const _WindowsShell(child: HomePage())
          : const HomePage(),
    );
  }
}

/// Wraps [HomePage] with a custom title bar that matches the app's theme
/// instead of the OS's plain black one (native chrome is hidden — see
/// `TitleBarStyle.hidden` in `main()`).
class _WindowsShell extends StatelessWidget {
  const _WindowsShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          SizedBox(
            height: kWindowCaptionHeight,
            child: WindowCaption(
              brightness: theme.brightness,
              backgroundColor: theme.scaffoldBackgroundColor,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'B',
                      style: TextStyle(
                        color: onAccent(theme.colorScheme.primary),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'BloBnot',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
