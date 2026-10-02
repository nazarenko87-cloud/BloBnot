import 'dart:ui';

import 'package:blobnot/services/window_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 1920x1080 screen with a 48-px taskbar docked at the top.
  const topTaskbar = Rect.fromLTWH(0, 48, 1920, 1032);

  group('fitInto', () {
    test('moves a window that opens under a top taskbar below it', () {
      final fitted = fitInto(
        const Rect.fromLTWH(10, 10, 1280, 720),
        topTaskbar,
      );
      expect(fitted, const Rect.fromLTWH(10, 48, 1280, 720));
    });

    test('leaves a window that is already on screen alone', () {
      const window = Rect.fromLTWH(200, 300, 1280, 720);
      expect(fitInto(window, topTaskbar), window);
    });

    test('shrinks a window bigger than the work area', () {
      const small = Rect.fromLTWH(0, 0, 1366, 728);
      final fitted = fitInto(const Rect.fromLTWH(10, 10, 1600, 900), small);
      expect(fitted.width, 1366 - 16);
      expect(fitted.height, 728 - 16);
      expect(small.contains(fitted.topLeft), isTrue);
      expect(fitted.bottom, lessThanOrEqualTo(small.bottom));
    });

    test('pulls back a window left on a second screen that is now gone', () {
      final fitted = fitInto(
        const Rect.fromLTWH(2500, 100, 1280, 720),
        topTaskbar,
      );
      expect(fitted.right, lessThanOrEqualTo(topTaskbar.right));
    });
  });

  group('keepTopReachable', () {
    test('brings the title bar back from under the taskbar', () {
      final fixed = keepTopReachable(
        const Rect.fromLTWH(300, 20, 1280, 720),
        topTaskbar,
      );
      expect(fixed, const Rect.fromLTWH(300, 48, 1280, 720));
    });

    test('lets the window hang off the bottom or the sides', () {
      const low = Rect.fromLTWH(-400, 700, 1280, 720);
      expect(keepTopReachable(low, topTaskbar), low);
    });
  });
}
