import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/source_sheet_palette.dart';

/// AppSheetPrimary/SecondaryButtonStyle -> LiquidGlassButtonStyle.
/// Geometry and state colors follow the original. Spring/material parity still
/// requires comparison with the macOS renderer.
class SourceSheetButton extends StatefulWidget {
  const SourceSheetButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.prominent = false,
    this.outlined = false,
    this.height = 41,
    this.horizontalPadding = 18,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool prominent;
  final bool outlined;
  final double height;
  final double horizontalPadding;

  @override
  State<SourceSheetButton> createState() => _SourceSheetButtonState();
}

class _SourceSheetButtonState extends State<SourceSheetButton> {
  final _states = WidgetStatesController();
  bool _scheduled = false;
  @override
  void initState() {
    super.initState();
    _states.addListener(_stateChanged);
  }

  void _stateChanged() {
    // TextButton updates its disabled state during its own build. Rebuild the
    // surrounding decoration after that frame, not an ancestor mid-layout.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scheduled) return;
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _states.removeListener(_stateChanged);
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final enabled = widget.onPressed != null;
    final pressed = enabled && _states.value.contains(WidgetState.pressed);
    final hovered = enabled && _states.value.contains(WidgetState.hovered);
    final focused = enabled && _states.value.contains(WidgetState.focused);
    final foreground = widget.prominent ? Colors.white : palette.secondary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: AnimatedScale(
        scale: widget.prominent && pressed && !reduceMotion ? .98 : 1,
        duration: Duration(milliseconds: reduceMotion ? 0 : 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.prominent
                ? null
                : (widget.outlined ? palette.card : palette.control),
            gradient: widget.prominent ? palette.prominentGradient : null,
          ),
          child: TextButton(
            statesController: _states,
            onPressed: widget.onPressed,
            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(foreground),
              textStyle: WidgetStatePropertyAll(
                TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.fontFamily,
                ),
              ),
              minimumSize: WidgetStatePropertyAll(Size(0, widget.height)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? Colors.black.withValues(alpha: .07)
                    : states.contains(WidgetState.hovered)
                    ? Colors.black.withValues(alpha: .035)
                    : Colors.transparent,
              ),
              side: WidgetStatePropertyAll(
                BorderSide(
                  color: focused
                      ? palette.selectedTint
                      : widget.prominent
                      ? Colors.white.withValues(
                          alpha: hovered || pressed ? .30 : .18,
                        )
                      : widget.outlined
                      ? palette.outline
                      : palette.border,
                  width: focused
                      ? 1.35
                      : MediaQuery.highContrastOf(context)
                      ? 1.15
                      : 1,
                ),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            child: IconTheme(
              data: IconThemeData(color: foreground, size: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    widget.icon!,
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
