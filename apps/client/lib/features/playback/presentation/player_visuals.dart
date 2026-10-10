import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// PlayerView.swift VideoControlPalette. Missing artwork resolves to dark
/// content; poster luminance below .46 resolves to light content.
class PlayerPalette {
  const PlayerPalette({this.lightContent = false});
  final bool lightContent;
  Color get primary => (lightContent ? Colors.white : Colors.black).withValues(
    alpha: lightContent ? .95 : .82,
  );
  Color get secondary => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .72 : .58);
  Color get subdued => (lightContent ? Colors.white : Colors.black).withValues(
    alpha: lightContent ? .48 : .38,
  );
  Color get rowFill => (lightContent ? Colors.white : Colors.black).withValues(
    alpha: lightContent ? .045 : .040,
  );
  Color get selectedFill => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .16 : .11);
  Color get rowStroke => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .065 : .075);
  Color get selectedStroke => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .18 : .16);
  Color get choiceFill => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .12 : .07);
  Color get trackBase => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .18 : .16);
  Color get trackProgress => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .82 : .68);
  Color get divider => (lightContent ? Colors.white : Colors.black).withValues(
    alpha: lightContent ? .14 : .12,
  );
  List<Color> get barFill => lightContent
      ? [
          Colors.white.withValues(alpha: .24),
          Colors.white.withValues(alpha: .20),
        ]
      : [
          Colors.white.withValues(alpha: .68),
          Colors.white.withValues(alpha: .60),
        ];
  List<Color> get popoverFill => lightContent
      ? [
          Colors.white.withValues(alpha: .28),
          Colors.white.withValues(alpha: .23),
        ]
      : [
          Colors.white.withValues(alpha: .78),
          Colors.white.withValues(alpha: .68),
        ];
  List<Color> get border => lightContent
      ? [
          Colors.white.withValues(alpha: .34),
          Colors.white.withValues(alpha: .15),
        ]
      : [
          Colors.white.withValues(alpha: .72),
          Colors.black.withValues(alpha: .16),
        ];
  Color get opaqueBase => lightContent
      ? const Color.fromRGBO(41, 43, 48, 1)
      : const Color.fromRGBO(240, 242, 245, 1);

  static Future<PlayerPalette> forPoster(String? path) async {
    if (path == null) return const PlayerPalette();
    ui.Codec? codec;
    ui.Image? image;
    try {
      final file = File(path);
      if (await file.length() > 20 * 1024 * 1024) return const PlayerPalette();
      codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 36,
        targetHeight: 36,
      );
      image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return const PlayerPalette();
      var total = 0.0, count = 0;
      final samples = (image.width * image.height).clamp(0, 72);
      for (var i = 0; i < samples; i++) {
        final x = (i * 37) % image.width, y = (i * 53) % image.height;
        final at = (y * image.width + x) * 4;
        if (bytes.getUint8(at + 3) / 255 <= .08) continue;
        total +=
            (.2126 * bytes.getUint8(at) +
                .7152 * bytes.getUint8(at + 1) +
                .0722 * bytes.getUint8(at + 2)) /
            255;
        count++;
      }
      return PlayerPalette(lightContent: count > 0 && total / count < .46);
    } catch (_) {
      return const PlayerPalette();
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

/// Named for original SF Symbols. Cross-platform vector outlines are kept
/// separate from layout; their macOS pixel comparison remains an acceptance item.
enum PlayerSymbol {
  subtitle,
  audio,
  speaker,
  muted,
  device,
  timer,
  minus,
  plus,
  reset,
  check,
  circle,
  episodes,
  settings,
  quality,
}

class PlayerSymbolIcon extends StatelessWidget {
  const PlayerSymbolIcon(
    this.symbol, {
    required this.color,
    this.size = 17,
    super.key,
  });
  final PlayerSymbol symbol;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _SymbolPainter(symbol, color)),
  );
}

class _SymbolPainter extends CustomPainter {
  const _SymbolPainter(this.symbol, this.color);
  final PlayerSymbol symbol;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (symbol) {
      case PlayerSymbol.quality:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 2, 20, 20),
            const Radius.circular(4),
          ),
        );
        path.moveTo(6, 8);
        path.lineTo(8, 8);
        path.moveTo(13, 8);
        path.lineTo(18, 8);
        path.addOval(const Rect.fromLTWH(8, 6, 4, 4));
        path.moveTo(6, 16);
        path.lineTo(12, 16);
        path.moveTo(17, 16);
        path.lineTo(18, 16);
        path.addOval(const Rect.fromLTWH(13, 14, 4, 4));
      case PlayerSymbol.episodes:
        for (final y in [5.0, 12.0, 19.0]) {
          path.moveTo(3, y);
          path.lineTo(15, y);
        }
        path.moveTo(18, 8);
        path.lineTo(23, 12);
        path.lineTo(18, 16);
        path.close();
      case PlayerSymbol.settings:
        path.addOval(const Rect.fromLTWH(5, 5, 14, 14));
        path.addOval(const Rect.fromLTWH(9, 9, 6, 6));
        for (var i = 0; i < 8; i++) {
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(i * 3.141592653589793 / 4);
          canvas.drawLine(const Offset(0, -9), const Offset(0, -11), pen);
          canvas.restore();
        }
      case PlayerSymbol.subtitle:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 4, 20, 15),
            const Radius.circular(3),
          ),
        );
        path.moveTo(6, 19);
        path.lineTo(6, 22);
        path.lineTo(10, 19);
        for (final x in [6.0, 13.0]) {
          path.moveTo(x + 4, 9);
          path.lineTo(x, 9);
          path.lineTo(x, 14);
          path.lineTo(x + 4, 14);
        }
      case PlayerSymbol.audio:
        path.addOval(const Rect.fromLTWH(1, 1, 22, 22));
        for (final pair in [
          (6.0, 3.0),
          (9.0, 6.0),
          (12.0, 8.0),
          (15.0, 5.0),
          (18.0, 2.0),
        ]) {
          path.moveTo(pair.$1, 12 - pair.$2 / 2);
          path.lineTo(pair.$1, 12 + pair.$2 / 2);
        }
      case PlayerSymbol.speaker:
      case PlayerSymbol.muted:
        path.moveTo(3, 9);
        path.lineTo(7, 9);
        path.lineTo(12, 5);
        path.lineTo(12, 19);
        path.lineTo(7, 15);
        path.lineTo(3, 15);
        path.close();
        if (symbol == PlayerSymbol.muted) {
          path.moveTo(16, 9);
          path.lineTo(22, 15);
          path.moveTo(22, 9);
          path.lineTo(16, 15);
        } else {
          path.moveTo(16, 8);
          path.quadraticBezierTo(21, 12, 16, 16);
          path.moveTo(19, 5);
          path.quadraticBezierTo(26, 12, 19, 19);
        }
      case PlayerSymbol.device:
        path.addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 2, 14, 20),
            const Radius.circular(2),
          ),
        );
        path.addOval(const Rect.fromLTWH(9, 5, 6, 6));
        path.addOval(const Rect.fromLTWH(8, 13, 8, 7));
      case PlayerSymbol.timer:
        path.addOval(const Rect.fromLTWH(3, 4, 18, 18));
        path.moveTo(9, 1);
        path.lineTo(15, 1);
        path.moveTo(12, 1);
        path.lineTo(12, 4);
        path.moveTo(12, 8);
        path.lineTo(12, 13);
        path.lineTo(16, 13);
      case PlayerSymbol.minus:
      case PlayerSymbol.plus:
        path.moveTo(5, 12);
        path.lineTo(19, 12);
        if (symbol == PlayerSymbol.plus) {
          path.moveTo(12, 5);
          path.lineTo(12, 19);
        }
      case PlayerSymbol.reset:
        path.moveTo(5, 7);
        path.cubicTo(16, -2, 28, 16, 15, 21);
        path.cubicTo(7, 24, 2, 16, 4, 12);
        path.moveTo(5, 2);
        path.lineTo(5, 7);
        path.lineTo(10, 7);
      case PlayerSymbol.check:
      case PlayerSymbol.circle:
        path.addOval(const Rect.fromLTWH(2, 2, 20, 20));
        if (symbol == PlayerSymbol.check) {
          canvas.drawCircle(const Offset(12, 12), 10, Paint()..color = color);
          pen.color = color.computeLuminance() > .5
              ? Colors.black
              : Colors.white;
          path.reset();
          path.moveTo(7, 12);
          path.lineTo(10.5, 15.5);
          path.lineTo(17, 8.5);
        }
    }
    canvas.drawPath(path, pen);
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      symbol != old.symbol || color != old.color;
}
