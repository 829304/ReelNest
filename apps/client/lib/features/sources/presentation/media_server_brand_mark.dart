import 'package:flutter/material.dart';

import '../../../domain/media_source.dart';

Color mediaServerBrandColor(MediaSourceKind kind) => switch (kind) {
  MediaSourceKind.emby => const Color(0xFF21CFA7),
  MediaSourceKind.jellyfin => const Color(0xFFAA5CC3),
  MediaSourceKind.plex => const Color(0xFFEBAF00),
  _ => const Color(0xFF5C7CFA),
};

/// Connector identity used by the source picker, source rows and sidebar.
/// Emby and Plex keep their bundled official raster marks. Jellyfin uses the
/// exact official icon geometry from jellyfin-ux, rendered locally so it stays
/// sharp without adding a runtime SVG dependency.
class MediaServerBrandMark extends StatelessWidget {
  const MediaServerBrandMark({required this.kind, this.size = 20, super.key});

  final MediaSourceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => switch (kind) {
    MediaSourceKind.emby => Image.asset(
      'assets/brands/emby.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
    MediaSourceKind.jellyfin => Semantics(
      label: 'Jellyfin',
      image: true,
      child: CustomPaint(
        key: const ValueKey('jellyfin-brand-mark'),
        size: Size.square(size),
        painter: const _JellyfinMarkPainter(),
      ),
    ),
    MediaSourceKind.plex => Image.asset(
      'assets/brands/plex.png',
      key: const ValueKey('plex-brand-mark'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
    _ => Icon(Icons.dns_outlined, size: size),
  };
}

class _JellyfinMarkPainter extends CustomPainter {
  const _JellyfinMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 72;
    final scaleY = size.height / 72;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(scaleX, scaleY);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-2 / 3, -1 / 6),
        end: Alignment(1, 3 / 4),
        colors: [Color(0xFFAA5CC3), Color(0xFF00A4DC)],
      ).createShader(const Rect.fromLTWH(0, 0, 72, 72));

    // Official Jellyfin icon paths, normalized from its 72 x 72 SVG:
    // https://github.com/jellyfin/jellyfin-ux/blob/master/logos/SVG/
    // jellyfin-icon--color-on-dark.svg
    final core = Path()
      ..moveTo(24.2116, 49.1581)
      ..cubicTo(22.6599, 46.0424, 32.8378, 27.5879, 35.9999, 27.5879)
      ..cubicTo(39.1666, 27.5895, 49.3228, 46.0764, 47.7882, 49.1581)
      ..cubicTo(46.2536, 52.2398, 25.7632, 52.2738, 24.2116, 49.1581)
      ..close();
    canvas.drawPath(core, paint);

    final outer = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(0.481861, 64.9951)
      ..cubicTo(-4.19479, 55.6047, 26.4765, 0, 36, 0)
      ..cubicTo(45.5328, 0, 76.153, 55.713, 71.5274, 64.9951)
      ..cubicTo(66.9018, 74.2773, 5.15852, 74.3856, 0.481861, 64.9951)
      ..close()
      ..moveTo(12.7358, 56.847)
      ..cubicTo(15.8005, 62.9995, 56.2536, 62.9314, 59.2843, 56.847)
      ..cubicTo(62.3149, 50.761, 42.2515, 14.2605, 36.0093, 14.2605)
      ..cubicTo(29.767, 14.2605, 9.67118, 50.6944, 12.7358, 56.847)
      ..close();
    canvas.drawPath(outer, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JellyfinMarkPainter oldDelegate) => false;
}
