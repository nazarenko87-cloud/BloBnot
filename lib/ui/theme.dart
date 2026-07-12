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

/// Background presets (v1.3 «фоновые пресеты» + neon conversion look).
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.label,
    required this.dark,
    required this.scaffold,
    required this.surface,
  });

  final String id;
  final String label;
  final bool dark;
  final Color scaffold;
  final Color surface;
}

const List<ThemePreset> kThemePresets = [
  ThemePreset(
    id: 'petrol',
    label: 'Petrol dark',
    dark: true,
    scaffold: Color(0xFF1C2426),
    surface: Color(0xFF232D30),
  ),
  ThemePreset(
    id: 'neon',
    label: 'Neon night',
    dark: true,
    scaffold: Color(0xFF150F2E),
    surface: Color(0xFF221A44),
  ),
  ThemePreset(
    id: 'paper',
    label: 'Paper light',
    dark: false,
    scaffold: Color(0xFFF5F2EA),
    surface: Color(0xFFFFFFFF),
  ),
  ThemePreset(
    id: 'amber',
    label: 'Amber',
    dark: false,
    scaffold: Color(0xFFF6E7BF),
    surface: Color(0xFFFCF3DA),
  ),
  ThemePreset(
    id: 'mist',
    label: 'Mist',
    dark: false,
    scaffold: Color(0xFFF1F4F8),
    surface: Color(0xFFFFFFFF),
  ),
];

ThemePreset presetById(String id) => kThemePresets.firstWhere(
      (p) => p.id == id,
      // Back-compat: old settings stored 'dark'/'light'.
      orElse: () => id == 'light' ? kThemePresets[2] : kThemePresets[0],
    );

ThemeData buildTheme({required String presetId, required int accentIndex}) {
  final preset = presetById(presetId);
  final accent = kAccents[accentIndex.clamp(0, kAccents.length - 1)];
  final base = preset.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: preset.scaffold,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: preset.surface,
    ),
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: preset.scaffold),
    dividerColor: preset.dark ? Colors.white12 : Colors.black12,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.3),
    ),
  );
}
