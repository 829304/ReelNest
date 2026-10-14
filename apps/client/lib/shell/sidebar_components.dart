import 'package:flutter/material.dart';

import '../ui/theme/app_palette.dart';
import '../ui/theme/design_tokens.dart';

/// Lets adjacent rows hand hover ownership to each other without leaving two
/// fading pills behind. Selection remains owned by the route and is never
/// changed by this coordinator.
class AppSidebarHoverRegion extends StatefulWidget {
  const AppSidebarHoverRegion({required this.child, super.key});

  final Widget child;

  static _AppSidebarHoverController? _of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_AppSidebarHoverScope>()
      ?.notifier;

  @override
  State<AppSidebarHoverRegion> createState() => _AppSidebarHoverRegionState();
}

class _AppSidebarHoverRegionState extends State<AppSidebarHoverRegion> {
  final _controller = _AppSidebarHoverController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AppSidebarHoverScope(controller: _controller, child: widget.child);
}

class _AppSidebarHoverController extends ChangeNotifier {
  Object? activeRow;

  void setHovered(Object row, bool hovered) {
    final next = hovered ? row : (activeRow == row ? null : activeRow);
    if (identical(next, activeRow)) return;
    activeRow = next;
    notifyListeners();
  }

  void release(Object row) {
    if (activeRow == row) activeRow = null;
  }
}

class _AppSidebarHoverScope
    extends InheritedNotifier<_AppSidebarHoverController> {
  const _AppSidebarHoverScope({
    required _AppSidebarHoverController controller,
    required super.child,
  }) : super(notifier: controller);
}

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
  final Object _hoverToken = Object();
  _AppSidebarHoverController? _hoverController;
  bool _hovering = false;
  bool _pressed = false;
  bool _focused = false;
  bool _animateHoverExit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hoverController = AppSidebarHoverRegion._of(context);
  }

  @override
  void didUpdateWidget(covariant AppSidebarRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _animateHoverExit = false;
  }

  @override
  void dispose() {
    _hoverController?.release(_hoverToken);
    super.dispose();
  }

  void _handleTap() {
    // A click ends the press, not the pointer's presence in this row.
    if (_pressed) setState(() => _pressed = false);
    widget.onTap?.call();
  }

  void _handleHover(bool value) {
    if (_hovering == value && (value || !_pressed)) return;
    _hoverController?.setHovered(_hoverToken, value);
    setState(() {
      _hovering = value;
      _animateHoverExit = !value;
      // A route change can rebuild the sidebar before InkWell delivers the
      // matching highlight=false callback. Leaving the row must always clear
      // that stale pressed state or previously visited libraries form a trail.
      if (!value) _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final interactive = widget.onTap != null;
    // Selection is route state; hovering a different row must not hide it.
    final showSelected = widget.selected;
    final showHover =
        interactive && !widget.selected && (_hovering || _pressed);
    final activeHoverRow = _hoverController?.activeRow;
    final anotherRowHovered =
        activeHoverRow != null && activeHoverRow != _hoverToken;
    final animateExit =
        _animateHoverExit && !showSelected && !showHover && !anotherRowHovered;
    final backgroundDuration = reduceMotion
        ? Duration.zero
        : showSelected
        ? DesignTokens.sidebarSelectionMotion
        : showHover
        ? DesignTokens.sidebarHoverEnterMotion
        : animateExit
        ? DesignTokens.sidebarHoverExitMotion
        : Duration.zero;
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
            onTap: interactive ? _handleTap : null,
            onSecondaryTapDown: widget.onSecondaryTapDown,
            onHover: _handleHover,
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
                    duration: backgroundDuration,
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.sidebarRowHorizontal,
                      vertical: DesignTokens.sidebarRowVertical,
                    ),
                    decoration: BoxDecoration(
                      color: showSelected
                          ? null
                          : showHover
                          ? palette.hoverFill.withValues(
                              alpha: _pressed ? .95 : .82,
                            )
                          : Colors.transparent,
                      gradient: showSelected
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
                      border: showSelected
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
