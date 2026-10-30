import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'design_tokens.dart';

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final palette = isLight
        ? const AppPalette.light()
        : const AppPalette.dark();
    final colors =
        ColorScheme.fromSeed(
          seedColor: DesignTokens.blue,
          brightness: brightness,
        ).copyWith(
          primary: palette.iconGlyph,
          onPrimary: Colors.white,
          surface: palette.surface,
          onSurface: palette.title,
          onSurfaceVariant: palette.secondary,
          outline: palette.border,
          outlineVariant: palette.border,
          surfaceContainerLowest: palette.page,
          surfaceContainerLow: palette.sidebarBottom,
          surfaceContainer: palette.control,
          surfaceContainerHigh: palette.surface,
        );
    final baseText = TextTheme(
      headlineLarge: TextStyle(
        fontSize: DesignTokens.largeTitle,
        height: 1.16,
        fontWeight: FontWeight.bold,
        color: palette.title,
      ),
      titleLarge: TextStyle(
        fontSize: DesignTokens.sectionTitle,
        height: 1.24,
        fontWeight: FontWeight.w600,
        color: palette.title,
      ),
      titleMedium: TextStyle(
        fontSize: DesignTokens.body,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: palette.title,
      ),
      bodyLarge: TextStyle(
        fontSize: DesignTokens.body,
        height: 1.42,
        color: palette.body,
      ),
      bodyMedium: TextStyle(
        fontSize: DesignTokens.body,
        height: 1.42,
        color: palette.body,
      ),
      bodySmall: TextStyle(
        fontSize: DesignTokens.callout,
        height: 1.36,
        color: palette.secondary,
      ),
      labelLarge: TextStyle(
        fontSize: DesignTokens.body,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: palette.body,
      ),
      labelMedium: TextStyle(
        fontSize: DesignTokens.callout,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: palette.secondary,
      ),
      labelSmall: TextStyle(
        fontSize: DesignTokens.caption,
        height: 1.18,
        fontWeight: FontWeight.w600,
        color: palette.subtle,
      ),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      extensions: [palette],
      scaffoldBackgroundColor: palette.page,
      canvasColor: palette.page,
      hoverColor: palette.hoverFill.withValues(alpha: isLight ? .82 : .92),
      focusColor: palette.iconGlyph.withValues(alpha: isLight ? .14 : .22),
      splashColor: palette.iconGlyph.withValues(alpha: .08),
      highlightColor: palette.iconGlyph.withValues(alpha: .06),
      textTheme: baseText,
      iconTheme: IconThemeData(color: palette.secondary, size: 18),
      dividerTheme: DividerThemeData(
        color: palette.rowDivider,
        thickness: .8,
        space: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow.withValues(alpha: isLight ? .11 : .28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.cardRadius),
          side: BorderSide(color: palette.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, DesignTokens.prominentButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          textStyle: baseText.labelLarge,
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, DesignTokens.defaultButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          foregroundColor: palette.body,
          side: BorderSide(color: palette.border),
          textStyle: baseText.labelLarge,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, DesignTokens.defaultButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: palette.iconGlyph,
          textStyle: baseText.labelLarge,
          shape: controlShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.searchFill,
        hintStyle: baseText.bodyMedium?.copyWith(
          color: palette.searchPlaceholder,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
          borderSide: BorderSide(color: palette.border, width: .8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
          borderSide: BorderSide(color: palette.iconGlyph, width: 1.2),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow.withValues(alpha: isLight ? .16 : .34),
        elevation: 7,
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        position: PopupMenuPosition.under,
        iconColor: palette.secondary,
        iconSize: 17,
        textStyle: baseText.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
          side: BorderSide(color: palette.border),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            palette.shadow.withValues(alpha: isLight ? .16 : .34),
          ),
          elevation: const WidgetStatePropertyAll(7),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
              side: BorderSide(color: palette.border),
            ),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.subtle
                : palette.body,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.subtle
                : palette.secondary,
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? palette.hoverFill
                : Colors.transparent,
          ),
          textStyle: WidgetStatePropertyAll(baseText.bodyMedium),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.page,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: baseText.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: baseText.bodyMedium?.copyWith(
          color: palette.secondary,
          height: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.sheetRadius),
          side: BorderSide(color: palette.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: baseText.bodySmall?.copyWith(color: palette.title),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: isLight ? .12 : .30),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight
            ? const Color(0xF02B3442)
            : const Color(0xF0EDF2F8),
        contentTextStyle: baseText.bodyMedium?.copyWith(
          color: isLight ? Colors.white : const Color(0xFF15202E),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => palette.subtle.withValues(
            alpha: states.contains(WidgetState.hovered) ? .58 : .34,
          ),
        ),
      ),
    );
  }
}
