import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the desktop window where it can be grabbed. BloBnot draws its own
/// title bar, so if the top of the window slides under a taskbar docked at
/// the top of the screen there is nothing left to drag it by.

/// Gap kept between the window and the edges of the work area when the
/// window has to be shrunk to fit.
const double _margin = 8;

/// [window] moved (and, if it is bigger than [work], shrunk) so that it lies
/// entirely inside [work] — the screen minus its taskbars.
Rect fitInto(Rect window, Rect work) {
  final width = window.width > work.width
      ? work.width - 2 * _margin
      : window.width;
  final height = window.height > work.height
      ? work.height - 2 * _margin
      : window.height;
  final left = window.left.clamp(work.left, work.right - width).toDouble();
  final top = window.top.clamp(work.top, work.bottom - height).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

/// [window] with its top edge pulled down into [work] when it went above it,
/// so the title bar stays reachable. Sideways and downwards the window may
/// still hang off the screen — people park windows like that on purpose.
Rect keepTopReachable(Rect window, Rect work) {
  final overlapsSideways = window.right > work.left && window.left < work.right;
  if (!overlapsSideways || window.top >= work.top) return window;
  return window.translate(0, work.top - window.top);
}

/// Work area of the display the window is mostly on.
Future<Rect> _workAreaFor(Rect window) async {
  final displays = await screenRetriever.getAllDisplays();
  Rect workOf(Display d) {
    final pos = d.visiblePosition ?? Offset.zero;
    final size = d.visibleSize ?? d.size;
    return pos & size;
  }

  Rect? best;
  var bestArea = -1.0;
  for (final d in displays) {
    final work = workOf(d);
    final overlap = work.intersect(window);
    final area = overlap.isEmpty ? 0.0 : overlap.width * overlap.height;
    if (area > bestArea) {
      bestArea = area;
      best = work;
    }
  }
  return best ?? workOf(await screenRetriever.getPrimaryDisplay());
}

/// At start-up: fit the whole window inside the work area.
Future<void> fitWindowOnScreen() async {
  final bounds = await windowManager.getBounds();
  final fitted = fitInto(bounds, await _workAreaFor(bounds));
  if (fitted != bounds) await windowManager.setBounds(fitted);
}

/// After every move: bring the title bar back from under a top taskbar.
class KeepTitleBarReachable with WindowListener {
  @override
  Future<void> onWindowMoved() async {
    if (await windowManager.isFullScreen() ||
        await windowManager.isMaximized()) {
      return;
    }
    final bounds = await windowManager.getBounds();
    final fixed = keepTopReachable(bounds, await _workAreaFor(bounds));
    if (fixed != bounds) await windowManager.setPosition(fixed.topLeft);
  }
}
