import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paths and colors translated from MediaLib VividIconLibrary.swift.
/// No SF Symbols font or Material glyph substitution is used here.
enum SourceGlyph {
  drive,
  plus,
  refresh,
  checkCircle,
  warning,
  folder,
  grid,
  sliders,
  info,
  search,
  chevronDown,
  eyeOff,
  dashboard,
}

class SourceLineIcon extends StatelessWidget {
  const SourceLineIcon(
    this.glyph, {
    this.size = 18,
    this.color,
    this.lineWidth = 2,
    super.key,
  });
  final SourceGlyph glyph;
  final double size;
  final double lineWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _LinePainter(
        glyph,
        color ?? IconTheme.of(context).color ?? Colors.black,
        lineWidth,
      ),
    ),
  );
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.glyph, this.color, this.lineWidth);
  final SourceGlyph glyph;
  final Color color;
  final double lineWidth;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final path = Path();
    switch (glyph) {
      case SourceGlyph.dashboard:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 4, 18, 16),
            const Radius.circular(2.5),
          ),
        );
        path.moveTo(7, 16);
        path.lineTo(7, 12);
        path.moveTo(12, 16);
        path.lineTo(12, 8);
        path.moveTo(17, 16);
        path.lineTo(17, 6);
        path.moveTo(7, 16);
        path.lineTo(17, 16);
      case SourceGlyph.info:
        path.addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9));
        path.moveTo(12, 16);
        path.lineTo(12, 12);
        path.moveTo(12, 8);
        path.lineTo(12.01, 8);
      case SourceGlyph.search:
        path.addOval(Rect.fromCircle(center: const Offset(11, 11), radius: 7));
        path.moveTo(20, 20);
        path.lineTo(17, 17);
      case SourceGlyph.chevronDown:
        path.moveTo(6, 9);
        path.lineTo(12, 15);
        path.lineTo(18, 9);
      case SourceGlyph.eyeOff:
        path.moveTo(3, 3);
        path.lineTo(21, 21);
        path.moveTo(10.5, 6.2);
        path.arcToPoint(
          const Offset(12, 5),
          radius: const Radius.circular(10.6),
        );
        path.cubicTo(18.5, 5, 22, 12, 22, 12);
        path.arcToPoint(
          const Offset(18.7, 16),
          radius: const Radius.circular(17),
        );
        path.moveTo(6.5, 8.2);
        path.arcToPoint(
          const Offset(2, 12),
          radius: const Radius.circular(17),
          clockwise: false,
        );
        path.cubicTo(2, 12, 5.5, 19, 12, 19);
        path.arcToPoint(
          const Offset(15.5, 18.4),
          radius: const Radius.circular(10.6),
          clockwise: false,
        );
      case SourceGlyph.sliders:
        for (final row in [(7.0, 10.0), (12.0, 16.0), (17.0, 13.0)]) {
          path.moveTo(4, row.$1);
          path.lineTo(row.$2 - 2, row.$1);
          path.addOval(
            Rect.fromCircle(center: Offset(row.$2, row.$1), radius: 2),
          );
          path.moveTo(row.$2 + 2, row.$1);
          path.lineTo(20, row.$1);
        }
      case SourceGlyph.folder:
        path.moveTo(3, 7.5);
        path.arcToPoint(
          const Offset(4.5, 6),
          radius: const Radius.circular(1.5),
        );
        path.lineTo(9, 6);
        path.lineTo(11, 8.5);
        path.lineTo(19.5, 8.5);
        path.arcToPoint(
          const Offset(21, 10),
          radius: const Radius.circular(1.5),
        );
        path.lineTo(21, 18);
        path.arcToPoint(
          const Offset(19.5, 19.5),
          radius: const Radius.circular(1.5),
        );
        path.lineTo(4.5, 19.5);
        path.arcToPoint(
          const Offset(3, 18),
          radius: const Radius.circular(1.5),
        );
        path.close();
      case SourceGlyph.grid:
        for (final x in [3.5, 13.5]) {
          for (final y in [3.5, 13.5]) {
            path.addRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 7, 7),
                const Radius.circular(1.5),
              ),
            );
          }
        }
      case SourceGlyph.drive:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 5, 18, 14),
            const Radius.circular(2),
          ),
        );
        path
          ..moveTo(3, 13)
          ..lineTo(21, 13);
        path.addOval(Rect.fromCircle(center: const Offset(7.5, 16), radius: 1));
      case SourceGlyph.plus:
        path
          ..moveTo(12, 5)
          ..lineTo(12, 19)
          ..moveTo(5, 12)
          ..lineTo(19, 12);
      case SourceGlyph.refresh:
        path
          ..moveTo(21, 12)
          ..arcToPoint(
            const Offset(18, 5.3),
            radius: const Radius.circular(9),
            largeArc: true,
          )
          ..moveTo(21, 4)
          ..lineTo(21, 9)
          ..lineTo(16, 9);
      case SourceGlyph.checkCircle:
        path.addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9));
        path
          ..moveTo(8.5, 12)
          ..lineTo(11, 14.5)
          ..lineTo(15.5, 9.5);
      case SourceGlyph.warning:
        path
          ..moveTo(21.7, 18)
          ..lineTo(13.7, 4)
          ..arcToPoint(
            const Offset(10.3, 4),
            radius: const Radius.circular(2),
            clockwise: false,
          )
          ..lineTo(2.3, 18)
          ..arcToPoint(
            const Offset(4, 21),
            radius: const Radius.circular(2),
            clockwise: false,
          )
          ..lineTo(20, 21)
          ..arcToPoint(
            const Offset(21.7, 18),
            radius: const Radius.circular(2),
            clockwise: false,
          )
          ..close()
          ..moveTo(12, 9)
          ..lineTo(12, 13)
          ..moveTo(12, 17)
          ..lineTo(12.01, 17);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        // Swift strokes the already-scaled shape with a fixed logical width.
        ..strokeWidth = lineWidth * 24 / size.width,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.glyph != glyph || old.color != color || old.lineWidth != lineWidth;
}

enum SourceTitleIconKind {
  sources,
  connected,
  disconnected,
  settings,
  dashboard,
}

/// VividTitleIcon.sourcesObj/sourceOnObj/sourceOffObj/gearObj on the 48 grid.
class SourceTitleIcon extends StatelessWidget {
  const SourceTitleIcon({
    this.kind = SourceTitleIconKind.sources,
    this.size = 56,
    super.key,
  });
  final SourceTitleIconKind kind;
  final double size;
  @override
  Widget build(BuildContext context) {
    final glow = switch (kind) {
      SourceTitleIconKind.sources => const Color(0xFF0EA5E9),
      SourceTitleIconKind.connected => const Color(0xFF10B981),
      SourceTitleIconKind.disconnected => const Color(0xFFF97316),
      SourceTitleIconKind.settings => const Color(0xFF0EA5E9),
      SourceTitleIconKind.dashboard => const Color(0xFF10B981),
    };
    Widget shape() =>
        CustomPaint(size: Size.square(size), painter: _TitlePainter(kind));
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final shadow in [(0.28, 0.05, 0.045), (0.20, 0.13, 0.11)])
              Transform.translate(
                offset: Offset(0, size * shadow.$3),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: size * shadow.$2,
                    sigmaY: size * shadow.$2,
                  ),
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      glow.withValues(alpha: shadow.$1),
                      BlendMode.srcIn,
                    ),
                    child: shape(),
                  ),
                ),
              ),
            shape(),
          ],
        ),
      ),
    );
  }
}

class _TitlePainter extends CustomPainter {
  const _TitlePainter(this.kind);
  final SourceTitleIconKind kind;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 48, 48));
    void fill(Path path, int start, int end, {bool vertical = false}) {
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [Color(start), Color(end)],
            begin: Alignment.topLeft,
            end: vertical ? Alignment.bottomCenter : Alignment.bottomRight,
          ).createShader(path.getBounds()),
      );
    }

    void stroke(Path path, Color color, double width) => canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    void dot(double x, double y, double radius, Color color) =>
        canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
    if (kind == SourceTitleIconKind.dashboard) {
      stroke(
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(24, 24), radius: 15)),
        const Color(0xFFA7F3D0),
        6,
      );
      final arc = Path()
        ..moveTo(24, 9)
        ..arcToPoint(
          const Offset(10.5, 32),
          radius: const Radius.circular(15),
          largeArc: true,
        );
      canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..shader = const LinearGradient(
            colors: [Color(0xFF34D399), Color(0xFF059669)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(const Rect.fromLTWH(0, 0, 48, 48)),
      );
      stroke(
        Path()
          ..moveTo(14, 25)
          ..lineTo(19, 25)
          ..lineTo(21.5, 19)
          ..lineTo(25, 31)
          ..lineTo(27, 25)
          ..lineTo(34, 25),
        const Color(0xFF047857),
        2.6,
      );
      dot(24, 9, 3, const Color(0xFFFDE047));
    } else if (kind == SourceTitleIconKind.settings) {
      final paint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(0, 0, 48, 48));
      for (var i = 0; i < 8; i++) {
        canvas.save();
        canvas.translate(24, 24);
        canvas.rotate(i * math.pi / 4);
        canvas.translate(-24, -24);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(21, 5, 6, 10),
            const Radius.circular(2),
          ),
          paint,
        );
        canvas.restore();
      }
      canvas.drawCircle(const Offset(24, 24), 13, paint);
      dot(24, 24, 5.5, Colors.white);
      canvas.drawCircle(const Offset(24, 24), 2.4, paint);
    } else if (kind == SourceTitleIconKind.sources) {
      stroke(
        Path()
          ..moveTo(16, 8)
          ..cubicTo(21, 3, 27, 3, 32, 8),
        const Color(0xFF38BDF8),
        2.5,
      );
      stroke(
        Path()
          ..moveTo(19, 12)
          ..cubicTo(22, 9, 26, 9, 29, 12),
        const Color(0xFF60A5FA),
        2.2,
      );
      fill(
        Path()
          ..moveTo(24, 15)
          ..lineTo(39, 23)
          ..lineTo(24, 31)
          ..lineTo(9, 23)
          ..close(),
        0xFFE0F2FE,
        0xFF7DD3FC,
      );
      fill(
        Path()
          ..moveTo(9, 23)
          ..lineTo(24, 31)
          ..lineTo(24, 45)
          ..lineTo(9, 37)
          ..close(),
        0xFF38BDF8,
        0xFF0284C7,
        vertical: true,
      );
      fill(
        Path()
          ..moveTo(24, 31)
          ..lineTo(39, 23)
          ..lineTo(39, 37)
          ..lineTo(24, 45)
          ..close(),
        0xFF8B5CF6,
        0xFF4F46E5,
        vertical: true,
      );
      dot(14, 26, 1.5, const Color(0xFF34D399));
      dot(19, 28.5, 1.5, const Color(0xFF34D399));
      dot(32, 30, 1.8, const Color(0xFFFDE047));
    } else {
      final connected = kind == SourceTitleIconKind.connected;
      for (final y in [10.0, 24.0]) {
        fill(
          Path()..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(8, y, 30, 12),
              const Radius.circular(3),
            ),
          ),
          connected ? 0xFF38BDF8 : 0xFF94A3B8,
          connected ? 0xFF2563EB : 0xFF64748B,
        );
        dot(
          13,
          y + 6,
          1.6,
          Colors.white.withValues(alpha: connected ? 1 : 0.9),
        );
        stroke(
          Path()
            ..moveTo(18, y + 6)
            ..lineTo(32, y + 6),
          Colors.white.withValues(alpha: connected ? 0.55 : 0.45),
          1.6,
        );
      }
      if (connected) {
        fill(
          Path()
            ..addOval(Rect.fromCircle(center: const Offset(35, 34), radius: 8)),
          0xFF34D399,
          0xFF059669,
        );
        stroke(
          Path()
            ..moveTo(31.4, 34)
            ..lineTo(34, 36.6)
            ..lineTo(38.6, 31.4),
          Colors.white,
          2.4,
        );
      } else {
        fill(
          Path()
            ..moveTo(34, 25)
            ..lineTo(42, 39)
            ..lineTo(26, 39)
            ..close(),
          0xFFFBBF24,
          0xFFF97316,
        );
        stroke(
          Path()
            ..moveTo(34, 30)
            ..lineTo(34, 34),
          Colors.white,
          2,
        );
        dot(34, 36.6, 1.1, Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_TitlePainter old) => old.kind != kind;
}
