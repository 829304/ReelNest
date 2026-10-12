import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/home_snapshot.dart';
import 'home_video_card.dart';

class HomeVideoRow extends StatefulWidget {
  const HomeVideoRow({
    required this.collection,
    required this.items,
    super.key,
  });
  final HomeCollection collection;
  final List<HomeVideo> items;
  @override
  State<HomeVideoRow> createState() => _HomeVideoRowState();
}

class _HomeVideoRowState extends State<HomeVideoRow> {
  final _scroll = ScrollController();
  Timer? _timer;
  bool _hover = false, _dragging = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 4800), (_) {
      if (!mounted ||
          _hover ||
          _dragging ||
          !TickerMode.valuesOf(context).enabled ||
          MediaQuery.disableAnimationsOf(context) ||
          !_scroll.hasClients ||
          ModalRoute.of(context)?.isCurrent == false ||
          _scroll.position.maxScrollExtent <= 0) {
        return;
      }
      final step = widget.collection == HomeCollection.continueWatching
          ? 250.0
          : 172.0;
      _move(
        (_scroll.offset + step) > _scroll.position.maxScrollExtent
            ? 0
            : _scroll.offset + step,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _move(double offset) => _scroll.animateTo(
    offset.clamp(0, _scroll.position.maxScrollExtent),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    curve: Curves.easeOut,
  );
  @override
  Widget build(BuildContext context) {
    final progress = widget.collection == HomeCollection.continueWatching;
    final items = widget.items.take(12).toList();
    final colors = switch (widget.collection) {
      HomeCollection.seriesRecommendations => [
        const Color(0xFFFF9F45),
        const Color(0xFFFF5C8A),
      ],
      HomeCollection.highRated => [
        const Color(0xFFFF9F45),
        const Color(0xFFD946EF),
      ],
      HomeCollection.continueWatching => [
        const Color(0xFF36BFFA),
        const Color(0xFF2E90FA),
      ],
      HomeCollection.recentlyPlayed => [
        const Color(0xFF36BFFA),
        const Color(0xFF5B6CFF),
      ],
      HomeCollection.watchlist => [
        const Color(0xFFFF9F45),
        const Color(0xFFFF5C8A),
      ],
      HomeCollection.favorites => [
        const Color(0xFFFF5C8A),
        const Color(0xFFD946EF),
      ],
      HomeCollection.recentSeries => [
        const Color(0xFF5B6CFF),
        const Color(0xFF2E90FA),
      ],
    };
    final step = progress ? 500.0 : 516.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                widget.collection.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              key: ValueKey('home-more-${widget.collection.name}'),
              onPressed: () =>
                  context.push('/home/collection/${widget.collection.name}'),
              child: const Text(
                '查看全部 ›',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: SizedBox(
            height: progress ? 146 : 244,
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification) _dragging = true;
                    if (n is ScrollEndNotification) _dragging = false;
                    return false;
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.touch,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: ListView.separated(
                      key: PageStorageKey(
                        'home-strip-${widget.collection.name}',
                      ),
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, i) =>
                          HomeVideoCard(video: items[i], progress: progress),
                    ),
                  ),
                ),
                if (_hover && items.length > 1) ...[
                  Positioned(
                    left: 0,
                    top: progress ? 50 : 100,
                    child: IconButton.filledTonal(
                      onPressed: () => _move(_scroll.offset - step),
                      tooltip: '上一页',
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: progress ? 50 : 100,
                    child: IconButton.filledTonal(
                      onPressed: () => _move(_scroll.offset + step),
                      tooltip: '下一页',
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
