import 'dart:io';

import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop tray integration: closing the window hides it to the tray so
/// reminder timers keep running; the tray menu restores or exits.
class TrayService with TrayListener, WindowListener {
  TrayService({required this.onHidden});

  /// Called when the window is hidden to the tray (used for auto-lock).
  final void Function() onHidden;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> init() async {
    if (!_isDesktop) return;
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await localNotifier.setup(appName: 'BloBnot');

    await trayManager.setIcon(
      Platform.isWindows ? 'assets/app_icon.ico' : 'assets/icon.png',
    );
    await trayManager.setToolTip('BloBnot');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show BloBnot'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Exit'),
        ],
      ),
    );
    trayManager.addListener(this);
  }

  /// System toast for a due reminder — visible even when hidden in the tray.
  void notify(String title, String body) {
    if (!_isDesktop) return;
    LocalNotification(title: title, body: body).show();
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
    onHidden();
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconMouseUp() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _show();
      case 'exit':
        // Remove the tray icon first, otherwise Windows keeps a ghost icon
        // in the tray until the cursor passes over it.
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
    }
  }

  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
