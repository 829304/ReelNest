import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The normal-page color roles translated from AppColors.swift.
///
/// Pages consume semantic roles rather than rebuilding approximate colors.
/// Music's future standalone theme intentionally does not use this palette.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.page,
    required this.sidebarTop,
    required this.sidebarBottom,
    required this.surface,
    required this.control,
    required this.border,
    required this.rowDivider,
    required this.title,
    required this.body,
    required this.secondary,
    required this.subtle,
    required this.iconChip,
    required this.iconGlyph,
    required this.hoverFill,
    required this.searchFill,
    required this.searchPlaceholder,
    required this.shadow,
    required this.prominentStart,
    required this.prominentEnd,
  });

  const AppPalette.light()
    : page = const Color(0xFFF6F8FC),
      sidebarTop = const Color(0xFFF8FAFD),
      sidebarBottom = const Color(0xFFF3F6FA),
      surface = Colors.white,
      control = const Color(0xFFF1F3F7),
      border = const Color(0xFFEDF0F5),
      rowDivider = const Color(0xFFF1F4F8),
      title = const Color(0xFF1D1D1F),
      body = const Color(0xFF334155),
      secondary = const Color(0xFF5A6478),
      subtle = const Color(0xFF9AA3B4),
      iconChip = const Color(0xFFE7F0FD),
      iconGlyph = DesignTokens.blue,
      hoverFill = const Color(0xFFF1F3F7),
      searchFill = const Color(0xFFEEF1F6),
      searchPlaceholder = const Color(0xFFAAB2C0),
      shadow = const Color(0xFF283C64),
      prominentStart = DesignTokens.blue,
      prominentEnd = DesignTokens.cyan;

  const AppPalette.dark()
    : page = const Color(0xFF101722),
      sidebarTop = const Color(0xFF182432),
      sidebarBottom = const Color(0xFF121B27),
      surface = const Color(0xFF213040),
      control = const Color(0xFF263647),
      border = const Color(0xFF334459),
      rowDivider = const Color(0xD1334459),
      title = const Color(0xFFF5F5F7),
      body = const Color(0xFFF1F4F8),
      secondary = const Color(0xFFA8B4C3),
      subtle = const Color(0xCFA8B4C3),
      iconChip = const Color(0xFF283D54),
      iconGlyph = const Color(0xFF8BC4FF),
      hoverFill = const Color(0xFF263647),
      searchFill = const Color(0xFF263647),
      searchPlaceholder = const Color(0xB8A8B4C3),
      shadow = Colors.black,
      prominentStart = const Color(0xFF397DBD),
      prominentEnd = const Color(0xFF277E98);

  final Color page;
  final Color sidebarTop;
  final Color sidebarBottom;
  final Color surface;
  final Color control;
  final Color border;
  final Color rowDivider;
  final Color title;
  final Color body;
  final Color secondary;
  final Color subtle;
  final Color iconChip;
  final Color iconGlyph;
  final Color hoverFill;
  final Color searchFill;
  final Color searchPlaceholder;
  final Color shadow;
  final Color prominentStart;
  final Color prominentEnd;

  LinearGradient get prominentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [prominentStart, prominentEnd],
  );

  @override
  AppPalette copyWith({
    Color? page,
    Color? sidebarTop,
    Color? sidebarBottom,
    Color? surface,
    Color? control,
    Color? border,
    Color? rowDivider,
    Color? title,
    Color? body,
    Color? secondary,
    Color? subtle,
    Color? iconChip,
    Color? iconGlyph,
    Color? hoverFill,
    Color? searchFill,
    Color? searchPlaceholder,
    Color? shadow,
    Color? prominentStart,
    Color? prominentEnd,
  }) => AppPalette(
    page: page ?? this.page,
    sidebarTop: sidebarTop ?? this.sidebarTop,
    sidebarBottom: sidebarBottom ?? this.sidebarBottom,
    surface: surface ?? this.surface,
    control: control ?? this.control,
    border: border ?? this.border,
    rowDivider: rowDivider ?? this.rowDivider,
    title: title ?? this.title,
    body: body ?? this.body,
    secondary: secondary ?? this.secondary,
    subtle: subtle ?? this.subtle,
    iconChip: iconChip ?? this.iconChip,
    iconGlyph: iconGlyph ?? this.iconGlyph,
    hoverFill: hoverFill ?? this.hoverFill,
    searchFill: searchFill ?? this.searchFill,
    searchPlaceholder: searchPlaceholder ?? this.searchPlaceholder,
    shadow: shadow ?? this.shadow,
    prominentStart: prominentStart ?? this.prominentStart,
    prominentEnd: prominentEnd ?? this.prominentEnd,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      page: Color.lerp(page, other.page, t)!,
      sidebarTop: Color.lerp(sidebarTop, other.sidebarTop, t)!,
      sidebarBottom: Color.lerp(sidebarBottom, other.sidebarBottom, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      control: Color.lerp(control, other.control, t)!,
      border: Color.lerp(border, other.border, t)!,
      rowDivider: Color.lerp(rowDivider, other.rowDivider, t)!,
      title: Color.lerp(title, other.title, t)!,
      body: Color.lerp(body, other.body, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      iconChip: Color.lerp(iconChip, other.iconChip, t)!,
      iconGlyph: Color.lerp(iconGlyph, other.iconGlyph, t)!,
      hoverFill: Color.lerp(hoverFill, other.hoverFill, t)!,
      searchFill: Color.lerp(searchFill, other.searchFill, t)!,
      searchPlaceholder: Color.lerp(
        searchPlaceholder,
        other.searchPlaceholder,
        t,
      )!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      prominentStart: Color.lerp(prominentStart, other.prominentStart, t)!,
      prominentEnd: Color.lerp(prominentEnd, other.prominentEnd, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get appPalette =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? const AppPalette.dark()
          : const AppPalette.light());
}
