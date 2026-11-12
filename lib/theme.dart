import 'package:flutter/material.dart';

import 'data/models.dart';

/// Цветове по макета „Макет на календара“, вариант Б.
class Palette {
  final Color bg, surface, surfaceAlt, border, text, textMuted, primary, onPrimary;
  final Color heroBg, heroBorder, heroMuted, calendarTile, onCalendarTile, calendarTileMuted;
  final Color chipBg, chipText;
  final bool dark;

  const Palette({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.heroBg,
    required this.heroBorder,
    required this.heroMuted,
    required this.calendarTile,
    required this.onCalendarTile,
    required this.calendarTileMuted,
    required this.chipBg,
    required this.chipText,
    required this.dark,
  });

  static const yellow = Color(0xFFF2C230);
  static const onYellow = Color(0xFF1F2933);

  static const light = Palette(
    bg: Color(0xFFEEF1F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F8FA),
    border: Color(0xFFD5DBE1),
    text: Color(0xFF1F2933),
    textMuted: Color(0xFF52606D),
    primary: Color(0xFF2F5D8C),
    onPrimary: Color(0xFFFFFFFF),
    heroBg: Color(0xFF1F3A5C),
    heroBorder: Color(0xFF1F3A5C),
    heroMuted: Color(0xFFC9D6E4),
    calendarTile: Color(0xFF2F5D8C),
    onCalendarTile: Color(0xFFFFFFFF),
    calendarTileMuted: Color(0xFFDCE7F3),
    chipBg: Color(0xFFE3E7EB),
    chipText: Color(0xFF3E4C59),
    dark: false,
  );

  static const darkP = Palette(
    bg: Color(0xFF12171C),
    surface: Color(0xFF1F252C),
    surfaceAlt: Color(0xFF181D23),
    border: Color(0xFF323B45),
    text: Color(0xFFE8ECEF),
    textMuted: Color(0xFFA9B4BF),
    primary: Color(0xFF8DBBEE),
    onPrimary: Color(0xFF0F1D2D),
    heroBg: Color(0xFF243B57),
    heroBorder: Color(0xFF34506F),
    heroMuted: Color(0xFFC9D6E4),
    calendarTile: Color(0xFF8DBBEE),
    onCalendarTile: Color(0xFF0F1D2D),
    calendarTileMuted: Color(0xFF1B2F45),
    chipBg: Color(0xFF2A323B),
    chipText: Color(0xFFB4BFCA),
    dark: true,
  );

  /// Цветове на свещениците в храма (без жълтото на епархията).
  /// Различават се и по светлина, не само по тон.
  static const _priestLight = [
    Color(0xFF2F5D8C), // синьо
    Color(0xFF2E7D4F), // зелено
    Color(0xFFB45A12), // оранжево
    Color(0xFF6B4FA3), // лилаво
    Color(0xFFB03A5B), // розово-червено
    Color(0xFF1F7A80), // тюркоаз
    Color(0xFF7A5230), // кафяво
    Color(0xFF4A5A6A), // сиво-синьо
  ];
  static const _priestDark = [
    Color(0xFF8DBBEE),
    Color(0xFF7FCB9C),
    Color(0xFFF0A764),
    Color(0xFFB9A3E6),
    Color(0xFFEE8FA9),
    Color(0xFF7FCFD4),
    Color(0xFFD9A877),
    Color(0xFFB4BFCA),
  ];

  /// Цветът на свещеника с пореден номер [index] в храма.
  Color priest(int index) {
    final list = dark ? _priestDark : _priestLight;
    return list[index % list.length];
  }

  /// Текст върху цвета на свещеника.
  Color onPriest() => dark ? const Color(0xFF0F1D2D) : Colors.white;

  static Palette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkP : light;

  /// Приглушени цветове за видовете събития (фон, текст).
  (Color, Color) kind(EventKind k) {
    if (!dark) {
      return switch (k) {
        EventKind.krashtene => (const Color(0xFFDDF0EC), const Color(0xFF14584D)),
        EventKind.venchavka => (const Color(0xFFF5EAD7), const Color(0xFF6B4A12)),
        EventKind.pogrebenie => (const Color(0xFFE8E6E3), const Color(0xFF4A4640)),
        EventKind.panihida => (const Color(0xFFE6E3EE), const Color(0xFF463A66)),
        EventKind.vodosvet => (const Color(0xFFF4E0E4), const Color(0xFF7A2438)),
        EventKind.sluzhba => (const Color(0xFFE3ECF6), const Color(0xFF1F4A75)),
        EventKind.arhiereyska => (const Color(0xFFF6E7C1), const Color(0xFF6A4B00)),
        EventKind.izpoved => (const Color(0xFFE4EEE2), const Color(0xFF2F5228)),
        EventKind.maslosvet => (const Color(0xFFF3E6DA), const Color(0xFF6E3E17)),
        EventKind.kurban => (const Color(0xFFEFE9D2), const Color(0xFF574C12)),
        EventKind.drugo => (const Color(0xFFE3E7EB), const Color(0xFF3E4C59)),
      };
    }
    return switch (k) {
      EventKind.krashtene => (const Color(0xFF1F3F3A), const Color(0xFFA8DDD2)),
      EventKind.venchavka => (const Color(0xFF3F3420), const Color(0xFFEBCF9C)),
      EventKind.pogrebenie => (const Color(0xFF35322E), const Color(0xFFD6D1CA)),
      EventKind.panihida => (const Color(0xFF332E45), const Color(0xFFCBC3E8)),
      EventKind.vodosvet => (const Color(0xFF45252D), const Color(0xFFEDB9C5)),
      EventKind.sluzhba => (const Color(0xFF213549), const Color(0xFFA9CBEE)),
      EventKind.arhiereyska => (const Color(0xFF433712), const Color(0xFFF0D58A)),
      EventKind.izpoved => (const Color(0xFF263A23), const Color(0xFFB9D9B1)),
      EventKind.maslosvet => (const Color(0xFF402C1C), const Color(0xFFEBC4A2)),
      EventKind.kurban => (const Color(0xFF3A351E), const Color(0xFFDCD3A0)),
      EventKind.drugo => (const Color(0xFF2A323B), const Color(0xFFB4BFCA)),
    };
  }
}

ThemeData buildTheme(Palette p) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.dark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: p.dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.surface,
      onSurface: p.text,
    ),
    scaffoldBackgroundColor: p.bg,
  );
  final t = base.textTheme.apply(bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    textTheme: t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 17),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 17),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: p.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.primary,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        side: BorderSide(color: p.primary, width: 1.5),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
