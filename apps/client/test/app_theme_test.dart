import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/ui/theme/app_palette.dart';
import 'package:reelnest/ui/theme/app_theme.dart';
import 'package:reelnest/ui/theme/design_tokens.dart';

void main() {
  test('ordinary page menus share the compact desktop surface', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final palette = theme.extension<AppPalette>()!;
      final popup = theme.popupMenuTheme;
      expect(popup.color, palette.surface);
      expect(popup.surfaceTintColor, Colors.transparent);
      expect(popup.elevation, 7);
      expect(popup.menuPadding, const EdgeInsets.symmetric(vertical: 6));
      expect(popup.position, PopupMenuPosition.under);
      expect(popup.iconSize, 17);
      final popupShape = popup.shape! as RoundedRectangleBorder;
      expect(
        popupShape.borderRadius,
        BorderRadius.circular(DesignTokens.controlRadius),
      );
      expect(popupShape.side.color, palette.border);

      final menu = theme.menuTheme.style!;
      expect(menu.backgroundColor!.resolve({}), palette.surface);
      expect(menu.surfaceTintColor!.resolve({}), Colors.transparent);
      expect(menu.elevation!.resolve({}), 7);
      expect(
        menu.padding!.resolve({}),
        const EdgeInsets.symmetric(vertical: 6),
      );
      final menuShape = menu.shape!.resolve({})! as RoundedRectangleBorder;
      expect(
        menuShape.borderRadius,
        BorderRadius.circular(DesignTokens.controlRadius),
      );
      expect(menuShape.side.color, palette.border);

      final button = theme.menuButtonTheme.style!;
      expect(button.minimumSize!.resolve({}), const Size(0, 36));
      expect(button.foregroundColor!.resolve({}), palette.body);
      expect(
        button.foregroundColor!.resolve({WidgetState.disabled}),
        palette.subtle,
      );
      expect(
        button.overlayColor!.resolve({WidgetState.hovered}),
        palette.hoverFill,
      );
      expect(button.overlayColor!.resolve({}), Colors.transparent);
    }
  });
}
