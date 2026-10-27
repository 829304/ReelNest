import 'dart:async';

import 'package:flutter/material.dart';

/// Paints a card's lifted shadow in the nearest overlay.
///
/// Flutter sliver grids paint children in index order, so a transformed card's
/// shadow can otherwise sit below a later sibling. MediaLib raises the hovered
/// poster with zIndex; this overlay is the desktop Flutter equivalent while the
/// real child remains responsible for hit testing, focus and pointer tilt.
class HoverLiftShadow extends StatefulWidget {
  const HoverLiftShadow({
    required this.active,
    required this.child,
    this.cornerRadius = 18,
    this.scale = 1.018,
    super.key,
  });

  final bool active;
  final Widget child;
  final double cornerRadius;
  final double scale;

  @override
  State<HoverLiftShadow> createState() => _HoverLiftShadowState();
}

class _HoverLiftShadowState extends State<HoverLiftShadow> {
  static const _motion = Duration(milliseconds: 180);
  final _controller = OverlayPortalController();
  final _link = LayerLink();
  final _targetKey = GlobalKey();
  Timer? _hideTimer;
  Size _size = Size.zero;
  bool _paintActive = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _scheduleActivation(true);
  }

  @override
  void didUpdateWidget(HoverLiftShadow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _scheduleActivation(widget.active);
    }
  }

  void _scheduleActivation(bool active) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || active != widget.active) return;
      if (active) {
        _hideTimer?.cancel();
        final render = _targetKey.currentContext?.findRenderObject();
        if (render is! RenderBox || !render.hasSize || render.size.isEmpty) {
          return;
        }
        _size = render.size;
        _controller.show();
        setState(() => _paintActive = true);
        return;
      }
      if (!_controller.isShowing) return;
      setState(() => _paintActive = false);
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      _hideTimer = Timer(reduceMotion ? Duration.zero : _motion, () {
        if (mounted && !widget.active) _controller.hide();
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _controller,
    overlayChildBuilder: (context) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: SizedBox.fromSize(
              size: _size,
              child: AnimatedOpacity(
                opacity: _paintActive ? 1 : 0,
                duration: reduceMotion ? Duration.zero : _motion,
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _paintActive && !reduceMotion ? widget.scale : 1,
                  alignment: Alignment.bottomCenter,
                  duration: reduceMotion ? Duration.zero : _motion,
                  curve: Curves.easeOutCubic,
                  child: DecoratedBox(
                    key: const ValueKey('media-card-hover-overlay-shadow'),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(widget.cornerRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .18),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: CompositedTransformTarget(
      key: _targetKey,
      link: _link,
      child: widget.child,
    ),
  );
}
