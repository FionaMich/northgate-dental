import 'package:material_ui/material_ui.dart';

/// Direction D (approved 2026-11-19): the blueprint's tooth mark, teal palette, bundled fonts.
abstract final class Palette {
  static const deepSea = Color(0xFF0B2B2A);
  static const teal = Color(0xFF137C6C);
  static const tealDark = Color(0xFF0E6B5E);
  static const shine = Color(0xFF1FBFA2);
  static const enamel = Color(0xFFE6F6F2);
  static const mist = Color(0xFFF1F6F5);
  static const line = Color(0xFFD6E3E0);
  static const muted = Color(0xFF4C6361);
  static const apricot = Color(0xFFF2A970);
  static const error = Color(0xFFB3261E);
  static const heroTop = Color(0xFF1A8E7E);
  static const heroMid = Color(0xFF0C4C46);
  static const heroBottom = Color(0xFF072B29);
}

const uiFont = 'PlusJakartaSans';
const logoFont = 'Lato';

const heroGradient = RadialGradient(
  center: Alignment(0, -0.65),
  radius: 1.2,
  colors: [Palette.heroTop, Palette.heroMid, Palette.heroBottom],
  stops: [0, 0.48, 1],
);

const buttonGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF179683), Palette.tealDark],
);

List<BoxShadow> lift([double strength = 1]) => [
  BoxShadow(
    color: Palette.deepSea.withValues(alpha: 0.18 * strength),
    blurRadius: 32,
    offset: const Offset(0, 16),
    spreadRadius: -12,
  ),
];

ThemeData northgateTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Palette.teal)
      .copyWith(primary: Palette.teal, onPrimary: Colors.white, surface: Palette.mist, onSurface: Palette.deepSea, error: Palette.error);
  final base = ThemeData(colorScheme: scheme, fontFamily: uiFont, scaffoldBackgroundColor: Palette.mist);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: c, width: w),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          headlineLarge: const TextStyle(
            fontSize: 34,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: Palette.deepSea,
          ),
          headlineMedium: const TextStyle(
            fontSize: 30,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            color: Palette.deepSea,
          ),
          titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.deepSea),
          bodyLarge: const TextStyle(fontSize: 15, height: 1.5, color: Palette.muted),
          labelMedium: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.muted),
        )
        .apply(fontFamily: uiFont),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF4F8F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(Palette.line),
      enabledBorder: border(Palette.line),
      focusedBorder: border(Palette.teal, 2),
      errorBorder: border(Palette.error),
      labelStyle: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w500),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.teal,
        textStyle: const TextStyle(fontFamily: uiFont, fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
  );
}
