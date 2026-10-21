import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/media.dart';
import '../../../sources/presentation/local_media_artwork.dart';
import '../../application/home_actions.dart';
import '../../application/home_artwork_provider.dart';
import '../../domain/home_artwork_palette.dart';
import '../../domain/home_recommendation.dart';
import '../../domain/home_snapshot.dart';

/// HomeVividHeroCarousel/HomeVividHero: 246pt tall, 24pt radius, seven slides.
class HomeHero extends ConsumerStatefulWidget {
  const HomeHero({required this.board, super.key});
  final HomeRecommendation board;
  @override
  ConsumerState<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends ConsumerState<HomeHero>
    with WidgetsBindingObserver {
  Timer? _timer;
  int _index = 0;
  bool _hover = false, _focused = false, _busy = false, _active = true;
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);
  double _scrollX = 0, _dragX = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _active =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted &&
          _active &&
          !_hover &&
          !_focused &&
          !_busy &&
          TickerMode.valuesOf(context).enabled &&
          ModalRoute.of(context)?.isCurrent != false &&
          !MediaQuery.disableAnimationsOf(context)) {
        _step(1);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _active = state == AppLifecycleState.resumed;
  @override
  void didUpdateWidget(HomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.board.hero;
    if (old.isEmpty || widget.board.hero.isEmpty) {
      _index = 0;
      return;
    }
    final id = old[_index % old.length].item.identity;
    final current = widget.board.hero.indexWhere((v) => v.item.identity == id);
    _index = current >= 0 ? current : 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _step(int delta, {bool clamp = false}) {
    final count = widget.board.hero.length;
    final now = DateTime.now();
    if (count < 2 || now.difference(_lastStep).inMilliseconds <= 480) return;
    _lastStep = now;
    setState(
      () => _index = clamp
          ? (_index + delta).clamp(0, count - 1)
          : (_index + delta) % count,
    );
  }

  Future<void> _action(HomeVideo video, String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await homeVideoAction(context, ref, video, action);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.board.hero;
    if (slides.isEmpty) return const SizedBox.shrink();
    final current = _index % slides.length;
    final video = slides[current];
    final reduced = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent &&
              event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()) {
            GestureBinding.instance.pointerSignalResolver.register(event, (
              event,
            ) {
              _scrollX += (event as PointerScrollEvent).scrollDelta.dx;
              if (_scrollX.abs() > 42) {
                _step(_scrollX > 0 ? 1 : -1);
                _scrollX = 0;
              }
            });
          }
        },
        child: GestureDetector(
          onHorizontalDragStart: (_) => _dragX = 0,
          onHorizontalDragUpdate: (details) => _dragX += details.delta.dx,
          onHorizontalDragEnd: (details) {
            if (_dragX.abs() > 42) {
              _step(_dragX < 0 ? 1 : -1);
            }
          },
          child: AnimatedScale(
            scale: (_hover || _focused) && !reduced ? 1.008 : 1,
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 140),
            child: SizedBox(
              height: 246,
              child: Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    left: 24,
                    right: 24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _focused
                              ? Colors.white.withValues(alpha: .78)
                              : Colors.transparent,
                          width: _focused ? 1.5 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: (_hover || _focused) ? .24 : .18,
                            ),
                            blurRadius: (_hover || _focused) ? 32 : 24,
                            offset: Offset(0, (_hover || _focused) ? 12 : 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AnimatedSwitcher(
                              duration: reduced
                                  ? Duration.zero
                                  : const Duration(milliseconds: 400),
                              child: Material(
                                key: ValueKey(video.item.identity),
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      context.push(homeDetailLocation(video)),
                                  onFocusChange: (focused) {
                                    if (_focused != focused) {
                                      setState(() => _focused = focused);
                                    }
                                  },
                                  splashColor: Colors.white.withValues(
                                    alpha: .08,
                                  ),
                                  hoverColor: Colors.transparent,
                                  highlightColor: Colors.white.withValues(
                                    alpha: .04,
                                  ),
                                  child: _slide(video),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 30,
                              bottom: 30,
                              child: Row(
                                children: [
                                  _button(
                                    '立即播放',
                                    () => _action(video, 'play'),
                                    primary: true,
                                  ),
                                  const SizedBox(width: 12),
                                  _button(
                                    video.entry.watchlist ? '✓ 已想看' : '＋ 加入想看',
                                    () => _action(video, 'watchlist'),
                                  ),
                                ],
                              ),
                            ),
                            if (slides.length > 1)
                              Positioned(
                                right: 18,
                                bottom: 16,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var dot = 0;
                                      dot < slides.length;
                                      dot++
                                    )
                                      Semantics(
                                        label: '推荐 ${dot + 1}',
                                        button: true,
                                        selected: dot == current,
                                        child: GestureDetector(
                                          key: ValueKey('home-hero-dot-$dot'),
                                          onTap: () =>
                                              setState(() => _index = dot),
                                          behavior: HitTestBehavior.opaque,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                              vertical: 8,
                                            ),
                                            child: Container(
                                              width: dot == current ? 19 : 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: dot == current
                                                      ? .92
                                                      : .42,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if ((_hover || _focused) && slides.length > 1) ...[
                    Positioned(
                      left: 0,
                      top: 90,
                      child: _sideButton(
                        previous: true,
                        onPressed: current > 0
                            ? () => _step(-1, clamp: true)
                            : null,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 90,
                      child: _sideButton(
                        previous: false,
                        onPressed: current < slides.length - 1
                            ? () => _step(1, clamp: true)
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sideButton({required bool previous, VoidCallback? onPressed}) =>
      MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        child: Tooltip(
          message: previous ? '上一项推荐' : '下一项推荐',
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              minimumSize: const Size(24, 64),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
              foregroundColor: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: .68),
            ),
            child: CustomPaint(
              size: const Size(14, 40),
              painter: _SideLine(
                previous,
                Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: onPressed == null ? .34 : .68),
              ),
            ),
          ),
        ),
      );

  Widget _slide(HomeVideo video) {
    final item = video.item;
    final palette =
        ref.watch(homeArtworkPaletteProvider(video)).value ??
        HomeArtworkPalette.fallback;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.backdrop,
            palette.glowPrimary.withValues(alpha: .82),
            palette.glowAccent.withValues(alpha: .70),
          ],
        ),
      ),
    );
    final genre = item.remote?.genres.join('、');
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        if (item.backdropPath?.isNotEmpty == true)
          Transform.scale(
            scale: 1.025,
            child: LocalMediaArtwork(
              source: video.source,
              item: item,
              backdrop: true,
              placeholder: fallback,
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.68, -.68),
              radius: 1.1,
              colors: [
                palette.glowAccent.withValues(alpha: .22),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.16, .88),
              radius: 1.3,
              colors: [
                palette.glowPrimary.withValues(alpha: .18),
                Colors.transparent,
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 560,
            height: double.infinity,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xC2000000),
                    Color(0x7A000000),
                    Color(0x29000000),
                    Color(0x0A000000),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 86),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .22),
                  ),
                ),
                child: const Text(
                  '★  今日精选',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD0DD),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                key: ValueKey('home-hero-title-${item.identity}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 20,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if ((item.remote?.rating ?? 0) > 0)
                    '★ ${item.remote!.rating!.toStringAsFixed(1)}',
                  mediaTypes[item.displayType] ?? '媒体',
                  if (item.year != null) '${item.year}',
                ].join(' · '),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xD1FFFFFF),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  genre?.isNotEmpty == true ? genre! : widget.board.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0x9EFFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _button(String text, VoidCallback action, {bool primary = false}) =>
      SizedBox(
        height: 44,
        child: TextButton(
          onPressed: _busy ? null : action,
          style: TextButton.styleFrom(
            foregroundColor: primary ? const Color(0xFF1A0A2E) : Colors.white,
            backgroundColor: primary
                ? Colors.white
                : Colors.white.withValues(alpha: .12),
            padding: EdgeInsets.symmetric(horizontal: primary ? 24 : 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: primary
                  ? BorderSide.none
                  : BorderSide(color: Colors.white.withValues(alpha: .25)),
            ),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 14,
              fontWeight: primary ? FontWeight.w900 : FontWeight.bold,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (primary) ...[
                const Icon(Icons.play_arrow, size: 20),
                const SizedBox(width: 9),
              ],
              Text(text),
            ],
          ),
        ),
      );
}

class _SideLine extends CustomPainter {
  const _SideLine(this.previous, this.color);
  final bool previous;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.width * .28;
    final path = Path()
      ..moveTo(previous ? size.width - inset : inset, 0)
      ..lineTo(previous ? inset : size.width - inset, size.height / 2)
      ..lineTo(previous ? size.width - inset : inset, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.45
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SideLine old) =>
      old.previous != previous || old.color != color;
}
