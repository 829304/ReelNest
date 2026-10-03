import 'package:flutter/material.dart';

import 'design_tokens.dart';

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final colors =
        ColorScheme.fromSeed(
          seedColor: DesignTokens.blue,
          brightness: brightness,
        ).copyWith(
          primary: isLight ? DesignTokens.blue : const Color(0xFF8FC5FF),
          surface: isLight ? Colors.white : const Color(0xFF1C2028),
          onSurface: isLight ? DesignTokens.titleText : const Color(0xFFF1F4F8),
          onSurfaceVariant: isLight
              ? DesignTokens.secondaryText
              : const Color(0xFFB7C0CE),
          outlineVariant: isLight
              ? DesignTokens.border
              : const Color(0xFF343B48),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFF7F9FC)
          : const Color(0xFF14171D),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: DesignTokens.largeTitle,
          fontWeight: FontWeight.bold,
          color: colors.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: DesignTokens.sectionTitle,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: DesignTokens.body,
          color: colors.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.cardRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}
