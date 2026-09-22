import 'package:blobnot/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ShellStyle shellOf(String styleId, {bool dark = false}) => buildTheme(
  styleId: styleId,
  accentIndex: 0,
  dark: dark,
).extension<ShellStyle>()!;

void main() {
  test('every style has a unique id and a label', () {
    final ids = kThemeStyles.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(kThemeStyles.every((s) => s.label.isNotEmpty), isTrue);
    expect(ids, contains('lite2'));
  });

  test('an unknown style id falls back instead of throwing', () {
    expect(styleById('no-such-style').id, kThemeStyles.first.id);
  });

  group('Lite 2', () {
    test('keeps Ubuntu orange whatever accent is picked', () {
      for (final index in [0, 3, 7]) {
        final theme = buildTheme(
          styleId: 'lite2',
          accentIndex: index,
          dark: false,
        );
        expect(theme.colorScheme.primary, kUbuntuOrange);
      }
    });

    test('is flat and quiet, with small icons and a tight radius', () {
      final shell = shellOf('lite2');
      expect(shell.flat, isTrue);
      expect(shell.reducedMotion, isTrue);
      expect(shell.compactIcons, isTrue);
      expect(shell.radius, 6);
      expect(shell.borderColor, isNotNull);
      expect(shell.icon(22), 18);
      // Unlike Lite, it is not a newspaper — no serif headings.
      expect(shell.serifTitles, isFalse);
    });

    test('paints a different ground in light and dark', () {
      final light = buildTheme(styleId: 'lite2', accentIndex: 0, dark: false);
      final dark = buildTheme(styleId: 'lite2', accentIndex: 0, dark: true);
      expect(
        light.scaffoldBackgroundColor,
        isNot(dark.scaffoldBackgroundColor),
      );
      expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
      expect(dark.brightness, Brightness.dark);
    });
  });

  test('the other styles keep full-size icons and the chosen accent', () {
    for (final style in kThemeStyles.where((s) => s.id != 'lite2')) {
      final shell = shellOf(style.id);
      expect(shell.compactIcons, isFalse, reason: style.id);
      expect(shell.icon(22), 22, reason: style.id);
    }
    final petrol = buildTheme(styleId: 'petrol', accentIndex: 3, dark: false);
    expect(petrol.colorScheme.primary, kAccents[3]);
    // Lite stays monochrome.
    final lite = buildTheme(styleId: 'lite', accentIndex: 3, dark: false);
    expect(lite.colorScheme.primary, isNot(kAccents[3]));
    expect(lite.extension<ShellStyle>()!.serifTitles, isTrue);
  });

  test('onAccent keeps label text readable on either accent', () {
    expect(onAccent(const Color(0xFF171717)), Colors.white);
    expect(onAccent(const Color(0xFFF5F5F5)), isNot(Colors.white));
    expect(onAccent(kUbuntuOrange), Colors.white);
  });
}
