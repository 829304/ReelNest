import 'package:flutter/material.dart';

/// HomeVividPageBackground: three stationary radial gradients behind scrolling.
class HomePageBackground extends StatelessWidget {
  const HomePageBackground({
    required this.color,
    required this.child,
    super.key,
  });
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final side = size.biggest.shortestSide.clamp(1.0, double.infinity);
      return ColoredBox(
        color: color,
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final glow in [
              (
                const Alignment(-.88, -1.12),
                const Color(0xFF36BFFA),
                .07,
                620.0,
              ),
              (
                const Alignment(.98, -.88),
                const Color(0xFFFF5C8A),
                .055,
                580.0,
              ),
              (const Alignment(.04, .56), const Color(0xFF2E90FA), .035, 560.0),
            ])
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: glow.$1,
                      radius: glow.$4 / side,
                      colors: [
                        glow.$2.withValues(alpha: glow.$3),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
      );
    },
  );
}
