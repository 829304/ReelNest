import 'package:flutter/material.dart';

import '../ui/theme/app_palette.dart';
import '../ui/theme/design_tokens.dart';

class AppSidebarSectionHeader extends StatelessWidget {
  const AppSidebarSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      left: DesignTokens.sidebarSectionLeading,
      top: 14,
      bottom: 4,
    ),
    child: Text(
      title,
      style: TextStyle(
        color: context.appPalette.searchPlaceholder,
        fontSize: 10.5,
        height: 1.2,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.6,
      ),
    ),
  );
}

class AppSidebarIconChip extends StatelessWidget {
  const AppSidebarIconChip({
    required this.icon,
    this.active = false,
    super.key,
  });

  final Widget icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : DesignTokens.sidebarSelectionMotion,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        color: active ? null : palette.iconChip,
        gradient: active ? palette.prominentGradient : null,
        boxShadow: active
            ? [
                BoxShadow(
                  color: palette.prominentStart.withValues(alpha: .32),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ]
            : const [],
      ),
      child: IconTheme(
        data: IconThemeData(
          size: 16,
          color: active ? Colors.white : palette.iconGlyph,
        ),
        child: Center(child: icon),
      ),
    );
  }
}

class AppSidebarCountBadge extends StatelessWidget {
  const AppSidebarCountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.iconGlyph.withValues(alpha: dark ? .18 : .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        child: Text(
          '$count',
          style: TextStyle(
            color: palette.iconGlyph.withValues(alpha: .95),
            fontSize: DesignTokens.caption,
            height: 1.15,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class AppSidebarRow extends StatefulWidget {
  const AppSidebarRow({
    required this.label,
    required this.leading,
    required this.onTap,
    this.selected = false,
    this.indented = false,
    this.trailing,
    this.emphasized = false,
    this.onSecondaryTapDown,
    super.key,
  });

  final String label;
  final Widget leading;
  final VoidCallback? onTap;
  final bool selected;
  final bool indented;
  final Widget? trailing;
  final bool emphasized;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<AppSidebarRow> createState() => _AppSidebarRowState();
}

class _AppSidebarRowState extends State<AppSidebarRow> {
  bool _hovering = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : DesignTokens.sidebarSelectionMotion;
    final interactive = widget.onTap != null;
    final showHover = interactive && (_hovering || _pressed);
    return Padding(
      padding: EdgeInsets.only(
        left: widget.indented ? DesignTokens.sidebarChildIndent : 0,
      ),
      child: Semantics(
        button: interactive,
        selected: widget.selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            onHover: (value) => setState(() => _hovering = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            borderRadius: BorderRadius.circular(DesignTokens.sidebarPillRadius),
            child: AnimatedOpacity(
              opacity: _pressed ? .82 : (interactive ? 1 : .5),
              duration: reduceMotion ? Duration.zero : DesignTokens.fastMotion,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: duration,
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.sidebarRowHorizontal,
                      vertical: DesignTokens.sidebarRowVertical,
                    ),
                    decoration: BoxDecoration(
                      color: widget.selected
                          ? null
                          : showHover
                          ? palette.hoverFill.withValues(
                              alpha: _pressed ? .95 : .82,
                            )
                          : Colors.transparent,
                      gradient: widget.selected
                          ? LinearGradient(
                              colors: [
                                DesignTokens.blue.withValues(
                                  alpha: dark ? .22 : .14,
                                ),
                                DesignTokens.pink.withValues(
                                  alpha: dark ? .16 : .10,
                                ),
                              ],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.sidebarPillRadius,
                      ),
                      border: widget.selected
                          ? Border.all(
                              color: DesignTokens.blue.withValues(
                                alpha: dark ? .28 : .18,
                              ),
                              width: .8,
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: widget.leading is AppSidebarIconChip ? 28 : 18,
                          height: widget.leading is AppSidebarIconChip
                              ? 28
                              : 18,
                          child: IconTheme(
                            data: IconThemeData(
                              size: 18,
                              color: widget.selected
                                  ? palette.iconGlyph
                                  : palette.secondary,
                            ),
                            child: widget.leading,
                          ),
                        ),
                        const SizedBox(width: DesignTokens.sidebarRowGap),
                        Expanded(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.selected
                                  ? palette.iconGlyph
                                  : widget.emphasized
                                  ? palette.body
                                  : palette.secondary,
                              fontSize: DesignTokens.sidebarItemFont,
                              height: 1.2,
                              fontWeight: widget.selected || widget.emphasized
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.trailing case final trailing?) ...[
                          const SizedBox(width: 6),
                          trailing,
                        ],
                      ],
                    ),
                  ),
                  if (_focused)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : DesignTokens.fastMotion,
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.sidebarPillRadius - 1,
                            ),
                            border: Border.all(
                              color: DesignTokens.blue.withValues(alpha: .72),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSidebarGroupHeader extends StatelessWidget {
  const AppSidebarGroupHeader({
    required this.label,
    required this.leading,
    required this.expanded,
    required this.onTap,
    this.count = 0,
    this.onSecondaryTapDown,
    super.key,
  });

  final String label;
  final Widget leading;
  final bool expanded;
  final VoidCallback? onTap;
  final int count;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AppSidebarRow(
      label: label,
      emphasized: true,
      leading: leading,
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!expanded && count > 0) ...[
            AppSidebarCountBadge(count),
            const SizedBox(width: 5),
          ],
          AnimatedRotation(
            turns: expanded ? .25 : 0,
            duration: reduceMotion ? Duration.zero : DesignTokens.sidebarMotion,
            curve: Curves.easeOut,
            child: Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: context.appPalette.subtle.withValues(alpha: .82),
            ),
          ),
        ],
      ),
    );
  }
}
