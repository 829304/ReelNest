import 'package:flutter/material.dart';

/// DesignSystemTokens.swift / AppSheetMetrics. Chrome, material and button
/// styles migrate separately; these primitives do not use Material Dialog defaults.
abstract final class AppSheetMetrics {
  static const compactWidth = 430.0;
  static const standardWidth = 560.0;
  static const wideWidth = 620.0;
  static const horizontalPadding = 24.0;
  static const verticalPadding = 24.0;
  static const headerIconSize = 42.0;
  static const headerIconContainerSize = 52.0;
  static const sectionCornerRadius = 18.0;
  static const sectionContentPadding = 16.0;
}

/// AppColors.swift / AppSheetHeader. The caller supplies the matching original
/// VividPageIcon, allowing its artwork to overflow the 52-point layout frame.
class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    required this.title,
    required this.icon,
    this.subtitle,
    this.subtitleLineLimit = 2,
    super.key,
  });
  final String title;
  final Widget icon;
  final String? subtitle;
  final int subtitleLineLimit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(
      children: [
        ExcludeSemantics(
          child: SizedBox.square(
            dimension: AppSheetMetrics.headerIconContainerSize,
            child: icon,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: subtitleLineLimit,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// AppColors.AppInfoNote without a shadow, as used by SourceSettingsSheet.
class AppInfoNote extends StatelessWidget {
  const AppInfoNote({
    required this.text,
    required this.icon,
    required this.surface,
    required this.border,
    required this.iconTint,
    required this.textColor,
    super.key,
  });
  final String text;
  final Widget icon;
  final Color surface;
  final Color border;
  final Color iconTint;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(10),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconTint.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? .12
                    : .09,
              ),
            ),
            child: icon,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 11, color: textColor)),
        ),
      ],
    ),
  );
}

/// Resolved AppColors inputs. Kept explicit until the original theme resolver
/// is migrated, so Material-generated colors cannot silently substitute for it.
class AppSheetSectionColors {
  const AppSheetSectionColors({
    required this.card,
    required this.border,
    required this.shadow,
    required this.iconChip,
    required this.iconGlyph,
  });
  final Color card;
  final Color border;
  final Color shadow;
  final Color iconChip;
  final Color iconGlyph;
}

/// AppColors.swift / AppSheetSection. Caller supplies a 17-point AppGlyph.
class AppSheetSection extends StatelessWidget {
  const AppSheetSection({
    required this.title,
    required this.icon,
    required this.colors,
    required this.child,
    this.subtitle,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget icon;
  final AppSheetSectionColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppSheetMetrics.sectionCornerRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: dark ? .10 : .05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: radius,
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(
              AppSheetMetrics.sectionContentPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.iconChip,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconTheme(
                          data: IconThemeData(
                            size: 17,
                            color: colors.iconGlyph,
                          ),
                          child: icon,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// AppColors.swift / AppSheetActionFooter. Buttons retain their own focus,
/// keyboard shortcuts and styles; the footer only owns alignment and separator.
class AppSheetActionFooter extends StatelessWidget {
  const AppSheetActionFooter({
    required this.actions,
    required this.panelBorder,
    required this.solarLightTint,
    super.key,
  });
  final List<Widget> actions;
  final Color panelBorder;
  final Color solarLightTint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                actions[index],
              ],
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: .7,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    panelBorder.withValues(
                      alpha: panelBorder.a * (dark ? .46 : .62),
                    ),
                    solarLightTint.withValues(
                      alpha: solarLightTint.a * (dark ? .16 : .22),
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
