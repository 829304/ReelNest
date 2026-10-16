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
  Color get choiceSelectedFill => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .82 : .72);
  Color get choiceForeground => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .76 : .66);
  Color get choiceSelectedForeground =>
      (lightContent ? Colors.black : Colors.white).withValues(
        alpha: lightContent ? .78 : .94,
      );
  Color get controlKnob =>
      lightContent ? Colors.white : Colors.black.withValues(alpha: .82);
  Color get trackBase => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .18 : .16);
  Color get trackProgress => (lightContent ? Colors.white : Colors.black)
      .withValues(alpha: lightContent ? .82 : .68);
  Color get divider => (lightContent ? Colors.white : Colors.black).withValues(
    alpha: lightContent ? .14 : .12,
  );
  Color get shadow => Colors.black.withValues(alpha: lightContent ? .42 : .10);
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
      ? [const Color(0xF21D2026), const Color(0xFA0C0E12)]
      : [
          Colors.white.withValues(alpha: .78),
          Colors.white.withValues(alpha: .68),
        ];
  List<Color> get border => lightContent
      ? [
          Colors.white.withValues(alpha: .22),
          Colors.white.withValues(alpha: .08),
        ]
      : [
          Colors.white.withValues(alpha: .72),
          Colors.black.withValues(alpha: .16),
        ];
  Color get opaqueBase => lightContent
      ? const Color(0xFF101217)
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

/// Keeps nested player menus on the same dark material as the playback dock.
/// This local theme is intentionally not applied to the rest of the app.
ThemeData playerOverlayThemeData(ThemeData base) => base.copyWith(
  colorScheme: base.colorScheme.copyWith(
    surface: const Color(0xFF15181D),
    onSurface: const Color(0xF2FFFFFF),
  ),
  dividerColor: const Color(0x24FFFFFF),
  popupMenuTheme: PopupMenuThemeData(
    color: const Color(0xFF15181D),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    textStyle: base.textTheme.bodyMedium?.copyWith(
      color: const Color(0xE8FFFFFF),
      fontSize: 12,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0x29FFFFFF), width: .8),
    ),
  ),
);

/// Shared player panel material translated from PlayerView.swift.
///
/// Large and scrollable panels stay opaque so a continuously redrawn video
/// surface is not sampled for blur on every frame. Small transient surfaces
/// may opt into [liveMaterial].
class PlayerPanelSurface extends StatelessWidget {
  const PlayerPanelSurface({
    required this.palette,
    required this.child,
    this.radius = 18,
    this.liveMaterial = false,
    this.shadowRadius = 9,
    this.shadowOffset = const Offset(0, 4),
    super.key,
  });

  final PlayerPalette palette;
  final Widget child;
  final double radius;
  final bool liveMaterial;
  final double shadowRadius;
  final Offset shadowOffset;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final background = DecoratedBox(
      decoration: BoxDecoration(
        color: liveMaterial ? Colors.transparent : palette.opaqueBase,
        gradient: LinearGradient(
          colors: palette.popoverFill,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: borderRadius,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: shadowRadius,
            offset: shadowOffset,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: .07),
            blurRadius: 1,
            offset: const Offset(0, -.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: liveMaterial
                  ? BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: background,
                    )
                  : background,
            ),
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  foregroundPainter: _PlayerGradientBorderPainter(
                    start: palette.border.first,
                    end: palette.border.last,
                    radius: radius,
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

/// A short entrance transition that leaves route dismissal immediate. Player
/// popovers must disappear on the first Escape key event, matching the
/// original window-level shortcut behavior.
class PlayerPanelEntrance extends StatelessWidget {
  const PlayerPanelEntrance({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: disableAnimations == true
          ? Duration.zero
          : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 5),
          child: child,
        ),
      ),
    );
  }
}

/// Circular/capsule player control with explicit hover, focus and selected
/// states. The selected state is used while a related popover is open.
class PlayerControlSurface extends StatefulWidget {
  const PlayerControlSurface({
    required this.palette,
    required this.enabled,
    required this.child,
    this.selected = false,
    this.chrome = false,
    this.capsule = false,
    this.danger = false,
    super.key,
  });

  final PlayerPalette palette;
  final bool enabled;
  final bool selected;
  final bool chrome;
  final bool capsule;
  final bool danger;
  final Widget child;

  @override
  State<PlayerControlSurface> createState() => _PlayerControlSurfaceState();
}

class _PlayerControlSurfaceState extends State<PlayerControlSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.enabled && (_hovered || _focused);
    final base = widget.chrome
        ? const [Color(0x8A202329), Color(0x66121519)]
        : widget.selected
        ? [widget.palette.selectedFill, widget.palette.choiceFill]
        : widget.palette.barFill;
    final overlay = widget.danger && highlighted
        ? const Color(0xFFD84A4A).withValues(alpha: .34)
        : (widget.chrome ? Colors.white : widget.palette.primary).withValues(
            alpha: highlighted ? .09 : 0,
          );
    final colors = base
        .map((color) => Color.alphaBlend(overlay, color))
        .toList(growable: false);
    final border = widget.danger && highlighted
        ? const Color(0xFFFF8A8A).withValues(alpha: .54)
        : widget.selected
        ? widget.palette.primary.withValues(alpha: .42)
        : widget.chrome
        ? Colors.white.withValues(alpha: highlighted ? .30 : .19)
        : highlighted
        ? widget.palette.primary.withValues(alpha: .28)
        : widget.palette.border.first;
    final radius = BorderRadius.circular(widget.capsule ? 15 : 999);
    final scale = widget.selected ? 1.035 : (highlighted ? 1.018 : 1.0);
    return Focus(
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: widget.enabled ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1 : .46,
            duration: const Duration(milliseconds: 140),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
                borderRadius: radius,
                border: Border.all(
                  color: border,
                  width: widget.selected || _focused ? 1.1 : .85,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.chrome
                        ? Colors.black.withValues(alpha: .28)
                        : widget.palette.shadow,
                    blurRadius: widget.selected ? 5 : (highlighted ? 4 : 2),
                    offset: Offset(0, widget.selected || highlighted ? 2 : 1),
                  ),
                ],
              ),
              child: ClipRRect(borderRadius: radius, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reusable row material for player popovers and context menus. It keeps the
/// hover/focus transition on the static row background instead of relying on
/// an ancestor Material hidden below the panel fill.
class PlayerMenuRowSurface extends StatefulWidget {
  const PlayerMenuRowSurface({
    required this.palette,
    required this.child,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.radius = 9,
    this.minHeight = 32,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.fill,
    this.stroke,
    super.key,
  });

  final PlayerPalette palette;
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final double radius;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final Color? fill;
  final Color? stroke;

  @override
  State<PlayerMenuRowSurface> createState() => _PlayerMenuRowSurfaceState();
}

class _PlayerMenuRowSurfaceState extends State<PlayerMenuRowSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && widget.onTap != null;
    final highlighted = interactive && (_hovered || _focused);
    final baseFill = widget.selected
        ? widget.palette.selectedFill
        : widget.fill ?? widget.palette.rowFill;
    final fill = highlighted
        ? Color.alphaBlend(
            widget.palette.primary.withValues(alpha: .07),
            baseFill,
          )
        : baseFill;
    final stroke = widget.selected
        ? widget.palette.selectedStroke
        : highlighted
        ? widget.palette.primary.withValues(alpha: .18)
        : widget.stroke ?? widget.palette.rowStroke;
    final borderRadius = BorderRadius.circular(widget.radius);
    return Focus(
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: MouseRegion(
        cursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
        onExit: interactive ? (_) => setState(() => _hovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: Border.all(
              color: stroke,
              width: widget.selected || _focused ? .9 : .7,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: interactive ? widget.onTap : null,
              borderRadius: borderRadius,
              overlayColor: WidgetStatePropertyAll(
                widget.palette.primary.withValues(alpha: .045),
              ),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerGradientBorderPainter extends CustomPainter {
  const _PlayerGradientBorderPainter({
    required this.start,
    required this.end,
    required this.radius,
  });

  final Color start;
  final Color end;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const width = .9;
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlayerGradientBorderPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.radius != radius;
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
  bookmark,
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
      case PlayerSymbol.bookmark:
        path.moveTo(6, 3);
        path.lineTo(18, 3);
        path.lineTo(18, 21);
        path.lineTo(12, 17);
        path.lineTo(6, 21);
        path.close();
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
