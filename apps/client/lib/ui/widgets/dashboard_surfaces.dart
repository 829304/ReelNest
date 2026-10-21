import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/source_sheet_palette.dart';

class DashboardPageHeader extends StatelessWidget {
  const DashboardPageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: DesignTokens.pageHeaderHorizontal,
      vertical: DesignTokens.pageHeaderVertical,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final titleBlock = Row(
          children: [
            SizedBox(
              width: 62,
              height: 68,
              child: Align(alignment: Alignment.centerLeft, child: icon),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: DesignTokens.largeTitle,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.body,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final actionBlock = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: actions,
        );
        final scaled = MediaQuery.textScalerOf(context).scale(13) > 19.5;
        if (constraints.maxWidth < 760 || scaled) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                actionBlock,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: titleBlock),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 20),
              Flexible(child: actionBlock),
            ],
          ],
        );
      },
    ),
  );
}

class DashboardSectionHeading extends StatelessWidget {
  const DashboardSectionHeading({
    required this.title,
    required this.subtitle,
    this.icon,
    this.badge,
    this.tint,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final String? badge;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final color = tint ?? palette.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: palette.dark ? .16 : .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: DesignTokens.sectionTitle,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: DesignTokens.callout,
                    color: palette.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 12),
            DashboardStatusBadge(label: badge!, tint: color),
          ],
        ],
      ),
    );
  }
}

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.radius = 18,
    this.accent,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.staticSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color:
              accent?.withValues(alpha: palette.dark ? .28 : .18) ??
              palette.border,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: palette.dark ? .14 : .055),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DashboardStatusBadge extends StatelessWidget {
  const DashboardStatusBadge({
    required this.label,
    required this.tint,
    this.icon,
    super.key,
  });

  final String label;
  final Color tint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: tint.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? .17 : .10,
      ),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: tint.withValues(alpha: .16)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: tint),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: tint,
          ),
        ),
      ],
    ),
  );
}

class DashboardEmptyState extends StatelessWidget {
  const DashboardEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return DashboardPanel(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 270),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.accent.withValues(alpha: .18),
                      const Color(0xFF34C759).withValues(alpha: .12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 27, color: palette.accent),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: palette.secondary),
                ),
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardIconAction extends StatelessWidget {
  const DashboardIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final foreground = danger
        ? Color(palette.dark ? 0xFFFF8E8E : 0xFFD92D20)
        : palette.secondary;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      color: foreground,
      disabledColor: foreground.withValues(alpha: .4),
      style: IconButton.styleFrom(
        minimumSize: const Size.square(32),
        maximumSize: const Size.square(32),
        padding: EdgeInsets.zero,
        backgroundColor: palette.control.withValues(alpha: .78),
        hoverColor: foreground.withValues(alpha: .08),
        focusColor: foreground.withValues(alpha: .10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: palette.border),
      ),
    );
  }
}
