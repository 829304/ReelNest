import 'package:flutter/material.dart';

/// Keeps the Material slider's value-indicator portal in its own subtree.
/// Flutter 3.47 can otherwise serialize orphan semantics nodes inside a route
/// or popup, corrupting the Windows accessibility tree (flutter/flutter#190357).
/// Keep the original slider, constraints, keyboard controls and semantics.
class SliderOverlayScope extends StatelessWidget {
  const SliderOverlayScope({required this.child, super.key});

  final Slider child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Overlay.wrap(
      alwaysSizeToContent: true,
      clipBehavior: Clip.none,
      child: child,
    ),
  );
}
