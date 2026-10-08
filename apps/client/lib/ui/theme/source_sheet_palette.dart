import 'package:flutter/material.dart';

import '../widgets/app_sheet.dart';

/// The original classic theme subset used by SourcesView's local form.
/// AppTheme.swift / AppColors.ResolvedColorSet; other presets migrate separately.
class SourceSheetPalette {
  SourceSheetPalette(this.dark);
  final bool dark;
  static Color _mix(Color a, Color b, double fraction) =>
      Color.lerp(a, b, fraction)!;
  static Color _lighten(Color c, double amount) =>
      _mix(c, Colors.white, amount);
  static Color _saturate(Color c, double factor) {
    final hsv = HSVColor.fromColor(c);
    return hsv.withSaturation((hsv.saturation * factor).clamp(0, 1)).toColor();
  }

  static Color _brightness(Color c, double factor) {
    final hsv = HSVColor.fromColor(c);
    return hsv.withValue((hsv.value * factor).clamp(0, 1)).toColor();
  }

  Color get _surface => const Color(0xFF172230);
  Color get _elevated => const Color(0xFF213040);
  Color get accent => dark ? const Color(0xFF8BC4FF) : const Color(0xFF2E90FA);
  Color get selectedTint =>
      dark ? const Color(0xFF78B7FF) : const Color(0xFF2C7CE0);
  Color get text => dark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
  Color get secondary =>
      dark ? const Color(0xFFA8B4C3) : const Color(0xFF5A6478);
  Color get page => dark
      ? _saturate(const Color(0xFF101722), .92).withValues(alpha: .98)
      : _saturate(const Color(0xFFF6F8FC), .56).withValues(alpha: .97);
  Color get card =>
      dark ? _lighten(_mix(_elevated, _surface, .18), .012) : Colors.white;
  Color get staticSurface => dark ? _elevated : Colors.white;
  Color get cleanPanelFill => dark
      ? _mix(_elevated, _surface, .18).withValues(alpha: .94)
      : _lighten(const Color(0xFFF6F8FC), .115).withValues(alpha: .90);
  Color get border => dark ? const Color(0xFF334459) : const Color(0xFFEDF0F5);
  Color get outline => dark ? border : const Color(0xFFE6EAF1);
  Color get shadow => dark ? Colors.black : const Color(0xFF283C64);
  Color get control => dark
      ? _lighten(_mix(_surface, _elevated, .42), .012)
      : const Color(0xFFF1F3F7);
  Color get iconChip =>
      dark ? _mix(accent, card, .78) : const Color(0xFFE7F0FD);
  Color get activePill => dark ? _lighten(card, .045) : Colors.white;
  Color get activePillText => dark ? text : const Color(0xFF0F172A);
  Color get idlePillText =>
      dark ? secondary.withValues(alpha: .86) : const Color(0xFF64748B);
  Color get menuText => dark ? text : const Color(0xFF334155);
  Color get hoverPill => dark
      ? control.withValues(alpha: .92)
      : Colors.white.withValues(alpha: .46);
  Color get panelBorder => dark
      ? const Color.fromRGBO(235, 224, 199, .13)
      : const Color.fromRGBO(138, 128, 107, .16);
  Color get pointer {
    if (dark) {
      return _brightness(
        _saturate(
          _mix(const Color(0xFF26394D), _lighten(selectedTint, .12), .34),
          .96,
        ),
        1.08,
      );
    }
    return _lighten(
      _saturate(
        _mix(const Color(0xFFE8F2FF), _lighten(selectedTint, .42), .24),
        .72,
      ),
      .08,
    );
  }

  Color get solar => _lighten(pointer, dark ? .08 : .18);
  LinearGradient get prominentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: dark
        ? [
            _brightness(_saturate(accent, 1.02), .58),
            _brightness(
              _saturate(_mix(const Color(0xFF87D0F4), accent, .30), 1.02),
              .50,
            ),
          ]
        : [const Color(0xFF2E90FA), const Color(0xFF36BFFA)],
  );
  AppSheetSectionColors get section => AppSheetSectionColors(
    card: card,
    border: border,
    shadow: shadow,
    iconChip: iconChip,
    iconGlyph: accent,
  );
}
