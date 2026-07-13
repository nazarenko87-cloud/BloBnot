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

/// Background style with a dark and a light variant (original Settings had
/// Theme = System/Light/Dark plus Theme style = Petrol/Honey/Sky/Sage).
class ThemeStyle {
  const ThemeStyle({
    required this.id,
    required this.label,
    required this.darkScaffold,
    required this.darkSurface,
    required this.lightScaffold,
    required this.lightSurface,
  });

  final String id;
  final String label;
  final Color darkScaffold;
  final Color darkSurface;
  final Color lightScaffold;
  final Color lightSurface;
}

const List<ThemeStyle> kThemeStyles = [
  ThemeStyle(
    id: 'petrol',
    label: 'Petrol',
    darkScaffold: Color(0xFF1C2426),
    darkSurface: Color(0xFF232D30),
    lightScaffold: Color(0xFFF5F2EA),
    lightSurface: Color(0xFFFFFFFF),
  ),
  ThemeStyle(
    id: 'honey',
    label: 'Honey',
    darkScaffold: Color(0xFF2A2314),
    darkSurface: Color(0xFF342C1B),
    lightScaffold: Color(0xFFF6E7BF),
    lightSurface: Color(0xFFFCF3DA),
  ),
  ThemeStyle(
    id: 'sky',
    label: 'Sky',
    darkScaffold: Color(0xFF141A2E),
    darkSurface: Color(0xFF1D2440),
    lightScaffold: Color(0xFFF1F4F8),
    lightSurface: Color(0xFFFFFFFF),
  ),
  ThemeStyle(
    id: 'sage',
    label: 'Sage',
    darkScaffold: Color(0xFF1A241C),
    darkSurface: Color(0xFF223026),
    lightScaffold: Color(0xFFEDF4EC),
    lightSurface: Color(0xFFFFFFFF),
  ),
];

ThemeStyle styleById(String id) => kThemeStyles.firstWhere(
      (s) => s.id == id,
      orElse: () => kThemeStyles.first,
    );

ThemeMode themeModeOf(String mode) => switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

ThemeData buildTheme({
  required String styleId,
  required int accentIndex,
  required bool dark,
}) {
  final style = styleById(styleId);
  final accent = kAccents[accentIndex.clamp(0, kAccents.length - 1)];
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final scaffold = dark ? style.darkScaffold : style.lightScaffold;
  final surface = dark ? style.darkSurface : style.lightSurface;

  return base.copyWith(
    scaffoldBackgroundColor: scaffold,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: surface,
    ),
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: scaffold),
    dividerColor: dark ? Colors.white12 : Colors.black12,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.3),
    ),
  );
}
