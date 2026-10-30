import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/source_sheet_palette.dart';

/// Compact desktop menu control translated from the original
/// `GlassMenuButton` / `adaptiveMenuControl` pair.
class AppMenuControl<T> extends StatefulWidget {
  const AppMenuControl({
    required this.value,
    required this.label,
    required this.values,
    required this.itemLabel,
    required this.onSelected,
    this.enabled = true,
    this.busy = false,
    this.tooltip,
    this.minWidth = 76,
    this.maxWidth = 360,
    super.key,
  });

  final T value;
  final String label;
  final List<T> values;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onSelected;
  final bool enabled;
  final bool busy;
  final String? tooltip;
  final double minWidth;
  final double maxWidth;

  @override
  State<AppMenuControl<T>> createState() => _AppMenuControlState<T>();
}

class _AppMenuControlState<T> extends State<AppMenuControl<T>> {
  bool _hovered = false;
  bool _focused = false;
  bool _open = false;

  bool get _enabled => widget.enabled && !widget.busy;

  void _setOpen(bool value) {
    if (_open != value) setState(() => _open = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highlighted = _enabled && (_hovered || _focused || _open);
    return Semantics(
      button: true,
      enabled: _enabled,
      expanded: _open,
      label: widget.tooltip ?? widget.label,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (_enabled) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: Focus(
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
          },
          child: PopupMenuButton<T>(
            enabled: _enabled,
            initialValue: widget.value,
            tooltip: widget.tooltip ?? widget.label,
            onOpened: () => _setOpen(true),
            onCanceled: () => _setOpen(false),
            onSelected: (value) {
              _setOpen(false);
              widget.onSelected(value);
            },
            itemBuilder: (_) => [
              for (final value in widget.values)
                PopupMenuItem<T>(
                  value: value,
                  height: 36,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        child: value == widget.value
                            ? Icon(
                                Icons.check_rounded,
                                key: ValueKey('app-menu-selected-$value'),
                                size: 16,
                                color: palette.selectedTint,
                              )
                            : null,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          widget.itemLabel(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : DesignTokens.fastMotion,
              curve: Curves.easeOutCubic,
              height: DesignTokens.defaultButtonHeight,
              constraints: BoxConstraints(
                minWidth: widget.minWidth,
                maxWidth: widget.maxWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: highlighted ? palette.hoverPill : palette.card,
                borderRadius: BorderRadius.circular(DesignTokens.controlRadius),
                border: Border.all(
                  color: _focused
                      ? palette.selectedTint.withValues(alpha: .68)
                      : palette.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.busy) ...[
                    SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.7,
                        color: palette.selectedTint,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: _enabled
                            ? palette.menuText
                            : palette.secondary.withValues(alpha: .62),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : DesignTokens.fastMotion,
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.unfold_more_rounded,
                      size: 15,
                      color: palette.secondary,
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
