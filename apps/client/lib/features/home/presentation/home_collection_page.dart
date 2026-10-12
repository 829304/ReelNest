import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../sources/application/source_providers.dart';
import '../application/home_providers.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';
import 'widgets/home_video_card.dart';

class HomeCollectionPage extends ConsumerStatefulWidget {
  const HomeCollectionPage({required this.collection, super.key});
  final HomeCollection collection;
  @override
  ConsumerState<HomeCollectionPage> createState() => _HomeCollectionPageState();
}

class _HomeCollectionPageState extends ConsumerState<HomeCollectionPage> {
  int _visible = 36;
  final _offsets = <String, List<int>>{};
  final _scroll = ScrollController();
  Map<String, int> _more = {};
  bool _loading = true;
  int _loaded = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
  }

  void _loadNearEnd() {
    if (!mounted ||
        _loading ||
        !_scroll.hasClients ||
        _scroll.position.extentAfter > 500 ||
        (_more.isEmpty && _loaded <= _visible)) {
      return;
    }
    setState(() {
      _visible += 36;
      for (final source in _more.entries) {
        _offsets[source.key]!.add(source.value);
      }
      _loading = true;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sidebarSourcesProvider);
    final videos = <HomeVideo>[], errors = <String>[];
    final more = <String, int>{};
    var loading = sources.isLoading;
    final recommended =
        widget.collection == HomeCollection.seriesRecommendations ||
        widget.collection == HomeCollection.highRated ||
        widget.collection == HomeCollection.recentSeries;
    if (recommended) {
      final board = ref.watch(homeCollectionProvider(widget.collection));
      videos.addAll(board.items);
      errors.addAll(board.errors.values);
      loading |= board.loading;
    }
    for (final source
        in (sources.value ?? [])
            .where(HomeRepository.accepts)
            .where((_) => !recommended)) {
      final offsets = _offsets.putIfAbsent(source.id, () => [0]);
      for (final offset in offsets) {
        final page = ref.watch(
          homeVideoPageProvider((
            sourceId: source.id,
            collection: widget.collection,
            offset: offset,
          )),
        );
        videos.addAll(page.value?.items ?? []);
        loading |= page.isLoading;
        if (page.hasError) {
          errors.add('${source.name}：${sourceErrorMessage(page.error!)}');
        }
        if (offset == offsets.last && page.value?.hasMore == true) {
          more[source.id] = page.value!.nextOffset;
        }
      }
    }
    if (sources.hasError) errors.add(sourceErrorMessage(sources.error!));
    final items = recommended
        ? videos
        : HomeVideoPolicy.merge(widget.collection, videos);
    final shown = items.take(_visible).toList();
    _more = more;
    _loading = loading;
    _loaded = items.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNearEnd());
    return CustomScrollView(
      controller: _scroll,
      key: PageStorageKey('home-collection-${widget.collection.name}'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 22),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.collection.title,
                        style: const TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      child: const Text('返回'),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '已载入 ${items.length} 项',
                  style: const TextStyle(fontSize: 12.5),
                ),
                for (final error in errors) Text(error),
                if (errors.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      ref.invalidate(homeVideoPageProvider);
                      ref.invalidate(homeRecommendationCandidatesProvider);
                    },
                    child: const Text('重试'),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 158 / 236,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => HomeVideoCard(video: shown[i]),
              childCount: shown.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(22),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: loading
                  ? const Text('正在读取…')
                  : more.isNotEmpty || items.length > _visible
                  ? const SizedBox.shrink()
                  : Text(
                      items.isEmpty && errors.isEmpty ? '暂无内容' : '已显示全部已载入内容',
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
