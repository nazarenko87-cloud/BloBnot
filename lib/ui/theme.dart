import 'package:flutter/material.dart';

/// Accent palette — index stored in vault settings.json.
const List<Color> kAccents = [
  Color(0xFF4FD1E0), // petrol cyan (default)
  Color(0xFF7DD87D), // green
  Color(0xFFE0A34F), // amber
  Color(0xFFE07D9A), // rose
  Color(0xFF9A7DE0), // violet
  Color(0xFF4F9AE0), // blue
  Color(0xFFE0D24F), // yellow
];

ThemeData buildTheme({required bool dark, required int accentIndex}) {
  final accent = kAccents[accentIndex.clamp(0, kAccents.length - 1)];
  final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  final scaffold = dark ? const Color(0xFF1C2426) : const Color(0xFFF5F2EA);
  final surface = dark ? const Color(0xFF232D30) : const Color(0xFFFFFFFF);

  return base.copyWith(
    scaffoldBackgroundColor: scaffold,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: surface,
    ),
    dividerColor: dark ? Colors.white12 : Colors.black12,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.3),
    ),
  );
}
