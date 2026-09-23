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
  Color(0xFFE07A3F), // warm orange (Sand theme)
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
    this.flat = false,
    this.compact = false,
    this.fixedAccent,
  });

  final String id;
  final String label;
  final Color darkScaffold;
  final Color darkSurface;
  final Color lightScaffold;
  final Color lightSurface;

  /// Minimal/lightweight rendering: flat cards (no shadow, no radius, no
  /// blur) instead of the floating v2.0 shell look — cheaper to paint and
  /// visually the plainest option (used by the "Lite" style).
  final bool flat;

  /// Desktop-suite look ("Lite 2"): small icons, tight radius, hairline
  /// borders and hardly any animation, with a fixed accent instead of the
  /// chosen one.
  final bool compact;

  /// Accent this style always uses, ignoring the accent picker.
  final Color? fixedAccent;
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
  // Warm "v2.0" look: cream page with near-white cards.
  ThemeStyle(
    id: 'sand',
    label: 'Sand',
    darkScaffold: Color(0xFF272016),
    darkSurface: Color(0xFF332A1D),
    lightScaffold: Color(0xFFF0E9DA),
    lightSurface: Color(0xFFFBF7EF),
  ),
  // "Newsprint": black-and-white newspaper / TXT-file look — no accent
  // colour at all (buildTheme ignores accentIndex for this style), flat
  // hairline-bordered cards instead of shadows, fewer animations. See
  // buildTheme() for the rest of the grayscale/rule palette.
  ThemeStyle(
    id: 'lite',
    label: 'Lite',
    darkScaffold: Color(0xFF161616),
    darkSurface: Color(0xFF1C1C1C),
    lightScaffold: Color(0xFFF1F1EF),
    lightSurface: Color(0xFFF8F8F7),
    flat: true,
  ),
  // "Graphite": grey in both modes — neither the near-white nor near-black
  // every other style uses, but a real mid grey, lighter or darker.
  ThemeStyle(
    id: 'graphite',
    label: 'Graphite',
    darkScaffold: Color(0xFF3B3E43),
    darkSurface: Color(0xFF474A50),
    lightScaffold: Color(0xFFB9BCC0),
    lightSurface: Color(0xFFC9CCD0),
  ),
  // "Lite 2": the calm grey-and-orange of a Ubuntu desktop window. Keeps
  // colour (unlike Lite) but shrinks every control except the Hot tasks
  // flame, squares off the cards and drops the decorative motion.
  ThemeStyle(
    id: 'lite2',
    label: 'Lite 2',
    darkScaffold: Color(0xFF1D1B1A),
    darkSurface: Color(0xFF282626),
    lightScaffold: Color(0xFFF2F0EF),
    lightSurface: Color(0xFFFAFAFA),
    compact: true,
    fixedAccent: kUbuntuOrange,
  ),
];

/// Ubuntu's signature orange, the accent of the "Lite 2" style.
const Color kUbuntuOrange = Color(0xFFE95420);

ThemeStyle styleById(String id) => kThemeStyles.firstWhere(
  (s) => s.id == id,
  orElse: () => kThemeStyles.first,
);

/// Readable text colour for content painted directly on [accent] — needed
/// because "Lite" makes accent literal ink/paper (near-black or near-white
/// depending on brightness), so a hardcoded white label would vanish on the
/// dark-mode ink square. Plain luminance check; fine for every other style
/// too since their accents are all mid-saturation.
Color onAccent(Color accent) =>
    accent.computeLuminance() > 0.5 ? const Color(0xFF171717) : Colors.white;

/// Fixed sage-green used for project tags and the activity heatmap, so those
/// read as green regardless of the chosen accent (matches the v2.0 look).
const Color kTagGreen = Color(0xFF6E9E52);

/// The flame of the Hot tasks view — same warm orange as the Sand accent.
const Color kHotColor = Color(0xFFE07A3F);

/// Rounded-card shell metrics shared across the redesigned surfaces.
const double kCardRadius = 18;
const double kShellGap = 12;

/// Below this width the desktop card shell (rail + sidebar + editor + graph
/// side-by-side) has no room to breathe — switch to a single-pane phone
/// layout instead (drawer for nav+notes, one full-screen body, bottom
/// toolbar in the editor).
const double kMobileBreakpoint = 700;

/// Soft drop shadow for the floating cards.
List<BoxShadow> cardShadow(bool dark) => [
  BoxShadow(
    color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06),
    blurRadius: 16,
    offset: const Offset(0, 4),
  ),
];

/// Per-style shell metrics carried on [ThemeData] so [ShellCard] (and a
/// couple of other spots) can render the "Lite" style — flat, square,
/// hairline-bordered, quieter — without every call site needing to know
/// which style is active.
class ShellStyle extends ThemeExtension<ShellStyle> {
  const ShellStyle({
    required this.flat,
    required this.radius,
    this.borderColor,
    this.reducedMotion = false,
    this.serifTitles = false,
    this.compactIcons = false,
  });

  final bool flat;
  final double radius;

  /// Hairline card border used instead of a shadow when [flat] is true.
  final Color? borderColor;

  /// Skips decorative-only animation (currently: the reminder glyph pulse) —
  /// used by the newspaper/TXT-file "Lite" style, which asked for as little
  /// motion as the medium it imitates.
  final bool reducedMotion;

  /// Renders the wordmark and note titles in a serif "masthead" face
  /// instead of the app's usual sans/mono — a Lite-only touch.
  final bool serifTitles;

  /// Shrinks the rail and toolbar icons ("Lite 2"). The Hot tasks flame
  /// keeps its size — it is the one control meant to stay prominent.
  final bool compactIcons;

  /// Size for a rail/toolbar icon under this style.
  double icon(double normal) => compactIcons ? normal - 4 : normal;

  @override
  ShellStyle copyWith({
    bool? flat,
    double? radius,
    Color? borderColor,
    bool? reducedMotion,
    bool? serifTitles,
    bool? compactIcons,
  }) => ShellStyle(
    flat: flat ?? this.flat,
    radius: radius ?? this.radius,
    borderColor: borderColor ?? this.borderColor,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    serifTitles: serifTitles ?? this.serifTitles,
    compactIcons: compactIcons ?? this.compactIcons,
  );

  @override
  ShellStyle lerp(ThemeExtension<ShellStyle>? other, double t) =>
      other is ShellStyle && t >= 0.5 ? other : this;
}

/// System serif fallback stack used for Lite's "masthead" headings — no new
/// font asset, so the lightweight style stays lightweight.
const List<String> kMastheadFontFallback = ['Georgia', 'Times New Roman'];

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
  final base = dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);
  final scaffold = dark ? style.darkScaffold : style.lightScaffold;
  final surface = dark ? style.darkSurface : style.lightSurface;

  // "Lite" is deliberately monochrome — a newspaper/TXT-file look, so the
  // chosen accent colour is ignored on purpose and "primary" becomes plain
  // ink instead. Selection/active states invert ink↔paper rather than tint.
  final rule = dark ? const Color(0xFF333331) : const Color(0xFFC9C9C6);
  final ink = dark ? const Color(0xFFE9E9E6) : const Color(0xFF171717);
  final accent = style.flat
      ? ink
      : style.fixedAccent ??
            kAccents[accentIndex.clamp(0, kAccents.length - 1)];
  // Lite 2 borrows Ubuntu's window separator greys rather than Lite's rules.
  final hairline = style.compact
      ? (dark ? const Color(0xFF3A3736) : const Color(0xFFD6D2CF))
      : rule;
  final plain = style.flat || style.compact;

  return base.copyWith(
    scaffoldBackgroundColor: scaffold,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      secondary: accent,
      surface: surface,
    ),
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: scaffold),
    // Material 3 tints menus and dialogs toward its own seed colour, which
    // fights every one of these palettes; use the style's own surface.
    popupMenuTheme: base.popupMenuTheme.copyWith(color: surface),
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: surface),
    dividerColor: plain ? hairline : (dark ? Colors.white12 : Colors.black12),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: 0.3),
    ),
    // Lite 2 is meant to feel like a quiet desktop app: no page transitions
    // beyond a fade, and nothing that slides or bounces.
    pageTransitionsTheme: style.compact
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            },
          )
        : base.pageTransitionsTheme,
    extensions: [
      ShellStyle(
        flat: plain,
        radius: style.flat ? 0 : (style.compact ? 6 : kCardRadius),
        borderColor: plain ? hairline : null,
        reducedMotion: plain,
        serifTitles: style.flat,
        compactIcons: style.compact,
      ),
    ],
  );
}
