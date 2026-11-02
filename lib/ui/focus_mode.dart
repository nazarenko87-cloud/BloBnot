import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl+. by the key's place on the keyboard as well as by its character.
/// Flutter maps letter shortcuts to Latin keys on any layout, but not
/// punctuation: on the Ukrainian or Russian layout that key types "ю", and a
/// plain `SingleActivator(period)` misses it. One activator, not two, because
/// [CallbackShortcuts] runs every binding that matches.
class CtrlPeriodKeyActivator extends ShortcutActivator {
  const CtrlPeriodKeyActivator();

  @override
  Iterable<LogicalKeyboardKey>? get triggers => null;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      event is KeyDownEvent &&
      (event.physicalKey == PhysicalKeyboardKey.period ||
          event.logicalKey == LogicalKeyboardKey.period) &&
      state.isControlPressed &&
      !state.isShiftPressed &&
      !state.isAltPressed &&
      !state.isMetaPressed;

  @override
  String debugDescribeKeys() => 'Ctrl + (period key)';
}

/// Focus mode on the desktop shell: only the note's text is shown — no rail,
/// notes list, tabs, graph or formatting toolbar. [HomePage] owns the state;
/// the editor reads it here to hide its own chrome and offer the way out.
class FocusModeScope extends InheritedWidget {
  const FocusModeScope({
    super.key,
    required this.active,
    required this.toggle,
    required super.child,
  });

  final bool active;
  final VoidCallback toggle;

  /// Null outside the desktop shell (phone pages, tests of single widgets).
  static FocusModeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FocusModeScope>();

  @override
  bool updateShouldNotify(FocusModeScope oldWidget) =>
      active != oldWidget.active;
}
