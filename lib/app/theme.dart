import 'package:flutter/material.dart';

import '../features/settings/domain/app_settings.dart';

abstract final class BiliTheme {
  static const accent = Color(0xFFD94B68);
  static const canvas = Colors.white;
  static const ink = Color(0xFF242424);

  static ThemeData light({
    AppFontPreference font = AppFontPreference.harmonyOsSans,
    String systemFontFamily = '',
  }) => _build(Brightness.light, font.resolveFamily(systemFontFamily));
  static ThemeData dark({
    AppFontPreference font = AppFontPreference.harmonyOsSans,
    String systemFontFamily = '',
  }) => _build(Brightness.dark, font.resolveFamily(systemFontFamily));

  static ThemeData _build(Brightness brightness, String? fontFamily) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF202020) : canvas;
    final foreground = dark ? const Color(0xFFEAEAEA) : ink;
    final muted = dark ? const Color(0xFFADADAD) : const Color(0xFF777777);
    final panel = dark ? const Color(0xFF292929) : const Color(0xFFF8F8F8);
    final border = dark ? const Color(0xFF414141) : const Color(0xFFE5E5E5);
    final primary = dark ? const Color(0xFFEF8399) : accent;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF35131C) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF442730)
              : const Color(0xFFFFEFF2),
          onPrimaryContainer: primary,
          secondary: primary,
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: muted,
          surfaceContainerLowest: surface,
          surfaceContainerLow: panel,
          surfaceContainer: panel,
          surfaceContainerHigh: dark
              ? const Color(0xFF333333)
              : const Color(0xFFF1F1F1),
          surfaceContainerHighest: dark
              ? const Color(0xFF383838)
              : const Color(0xFFECECEC),
          outline: muted,
          outlineVariant: border,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: surface,
      dividerColor: border,
      hoverColor: primary.withValues(alpha: 0.045),
      focusColor: primary.withValues(alpha: 0.1),
      splashColor: primary.withValues(alpha: 0.08),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: TextStyle(color: primary),
        unselectedLabelTextStyle: TextStyle(color: muted),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: controlShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          side: BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: controlShape,
        side: BorderSide(color: border),
      ),
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w500,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: muted,
        ),
      ),
    );
  }
}
