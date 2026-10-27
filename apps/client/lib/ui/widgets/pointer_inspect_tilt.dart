import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Desktop equivalent of MediaLib's `pointerInspectTilt` modifier.
///
/// The original modifier samples the pointer within the surface, applies at
/// most 2.6 degrees of tilt on each axis, and adds a directional highlight.
/// Reduced-motion users always receive the untransformed child.
class PointerInspectTilt extends StatefulWidget {
  const PointerInspectTilt({
    required this.child,
    this.enabled = true,
    this.cornerRadius = 10,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final double cornerRadius;

  @override
  State<PointerInspectTilt> createState() => _PointerInspectTiltState();
}

class _PointerInspectTiltState extends State<PointerInspectTilt> {
  final _surfaceKey = GlobalKey();
  Offset? _pointer;
  Size _surfaceSize = Size.zero;

  @override
  void didUpdateWidget(PointerInspectTilt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.enabled && !reduceMotion;
    final pointer = enabled ? _pointer : null;
    final active =
        pointer != null &&
        _surfaceSize.width > 0 &&
        _surfaceSize.height > 0 &&
        _surfaceSize.isFinite;
    final normalizedX = active
        ? (pointer.dx / _surfaceSize.width).clamp(0.0, 1.0) - .5
        : 0.0;
    final normalizedY = active
        ? (pointer.dy / _surfaceSize.height).clamp(0.0, 1.0) - .5
        : 0.0;
    final transform = active
        ? (Matrix4.identity()
            ..setEntry(3, 2, .0014)
            ..rotateX(-normalizedY * 5.2 * math.pi / 180)
            ..rotateY(normalizedX * 5.2 * math.pi / 180))
        : Matrix4.identity();

    return MouseRegion(
      key: _surfaceKey,
      onHover: enabled
          ? (event) {
              final render = _surfaceKey.currentContext?.findRenderObject();
              final size = render is RenderBox && render.hasSize
                  ? render.size
                  : Size.zero;
              final previous = _pointer;
              if (previous != null &&
                  _surfaceSize == size &&
                  (previous - event.localPosition).distance < 1.5) {
                return;
              }
              setState(() {
                _surfaceSize = size;
                _pointer = event.localPosition;
              });
            }
          : null,
      onExit: enabled
          ? (_) {
              if (_pointer != null) setState(() => _pointer = null);
            }
          : null,
      child: AnimatedContainer(
        key: const ValueKey('pointer-inspect-tilt-transform'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: transform,
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.cornerRadius),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .10),
                    blurRadius: 12,
                    offset: Offset(-normalizedX * 4, 6),
                  ),
                ]
              : const [],
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  key: const ValueKey('pointer-inspect-tilt-highlight'),
                  opacity: active ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(widget.cornerRadius),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(normalizedX * 2, normalizedY * 2),
                          end: Alignment(-normalizedX * 2, -normalizedY * 2),
                          colors: [
                            Colors.white.withValues(alpha: .30),
                            Colors.transparent,
                            Colors.black.withValues(alpha: .10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
