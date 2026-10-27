import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// Flutter translation of MediaLib's PageHeader plus the `tv` vivid title icon.
///
/// The original header is deliberately not a card: its 68-point title cluster
/// and the actions share a bottom edge, while the surrounding page supplies the
/// whitespace. Compact layouts keep the actions on one horizontal rail instead
/// of wrapping individual buttons onto arbitrary rows.
class VideoLibraryPageHeader extends StatelessWidget {
  const VideoLibraryPageHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: DesignTokens.pageHeaderHorizontal,
      vertical: DesignTokens.pageHeaderVertical,
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final titleCluster = SizedBox(
          height: 68,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(
                width: 62,
                height: 68,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: VideoLibraryTitleIcon(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: DesignTokens.largeTitle,
                          height: 1.08,
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: DesignTokens.body,
                          fontWeight: FontWeight.w500,
                          height: 1.18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        final scaled = MediaQuery.textScalerOf(context).scale(13) > 19.5;
        if (constraints.maxWidth < 720 || scaled) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleCluster,
              const SizedBox(height: 12),
              SingleChildScrollView(
                key: const ValueKey('video-library-header-action-scroll'),
                scrollDirection: Axis.horizontal,
                child: actions,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: titleCluster),
            const SizedBox(width: 20),
            actions,
          ],
        );
      },
    ),
  );
}

/// Exact geometry and palette of VividIconLibrary.swift's `tvObj` on a 48 grid.
class VideoLibraryTitleIcon extends StatelessWidget {
  const VideoLibraryTitleIcon({this.size = 56, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: .22),
            blurRadius: size * .30,
            spreadRadius: -size * .12,
            offset: Offset(0, size * .08),
          ),
        ],
      ),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: const _VideoLibraryTitleIconPainter()),
      ),
    ),
  );
}

class _VideoLibraryTitleIconPainter extends CustomPainter {
  const _VideoLibraryTitleIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48, size.height / 48);
    final screen = RRect.fromRectAndRadius(
      const Rect.fromLTWH(5, 9, 38, 25),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      screen,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF38BDF8), Color(0xFF4F46E5)],
        ).createShader(screen.outerRect),
    );
    final highlight = Path()
      ..moveTo(5, 15)
      ..cubicTo(5, 12, 7, 10, 10, 10)
      ..lineTo(38, 10)
      ..cubicTo(40, 10, 41, 11, 41, 13)
      ..lineTo(41, 16)
      ..lineTo(5, 23)
      ..close();
    canvas.drawPath(
      highlight,
      Paint()..color = Colors.white.withValues(alpha: .28),
    );
    final stand = Path()
      ..moveTo(20, 34)
      ..lineTo(18, 41)
      ..lineTo(30, 41)
      ..lineTo(28, 34)
      ..close();
    canvas.drawPath(
      stand,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF64748B), Color(0xFF334155)],
        ).createShader(const Rect.fromLTWH(18, 34, 12, 7)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 40, 22, 3.4),
        const Radius.circular(1.7),
      ),
      Paint()..color = const Color(0xFF475569),
    );
    final play = Path()
      ..moveTo(20, 15)
      ..lineTo(31, 21)
      ..lineTo(20, 27)
      ..close();
    canvas.drawPath(play, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_VideoLibraryTitleIconPainter oldDelegate) => false;
}
