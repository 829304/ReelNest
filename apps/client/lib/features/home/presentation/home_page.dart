import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../sources/application/source_providers.dart';
import '../application/home_providers.dart';
import '../application/home_layout_provider.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';
import '../domain/home_layout.dart';
import '../domain/home_recommendation.dart';
import 'widgets/home_video_row.dart';
import 'widgets/home_hero.dart';
import 'widgets/home_page_background.dart';
import 'widgets/home_header.dart';
import 'widgets/home_search_results.dart';
import 'widgets/home_runtime_status.dart';
import 'widgets/home_layout_editor.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  HomeModule? _dragged;
  Timer? _dragScroll;
  double _dragVelocity = 0;
  Timer? _debounce;
  String _query = '';
  void _submit() {
    _debounce?.cancel();
    final query = _search.text.trim();
    if (_query != query) setState(() => _query = query);
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _submit);
  }

  void _endDrag() {
    _dragScroll?.cancel();
    _dragScroll = null;
    _dragVelocity = 0;
    if (mounted && _dragged != null) setState(() => _dragged = null);
  }

  void _updateDrag(DragUpdateDetails details) {
    final box = _viewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !_scroll.hasClients) return;
    final y = box.globalToLocal(details.globalPosition).dy;
    const edge = 64.0;
    final bottom = box.size.height - 64;
    _dragVelocity = y < edge
        ? -((edge - y) / 3).clamp(2.0, 22.0)
        : y > bottom
        ? ((y - bottom) / 3).clamp(2.0, 22.0)
        : 0.0;
    _dragScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _dragged == null || !_scroll.hasClients) return;
      final next = (_scroll.offset + _dragVelocity).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (next != _scroll.offset) _scroll.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _dragScroll?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return HomePageBackground(
      color: palette.page,
      child: ref
          .watch(sidebarSourcesProvider)
          .when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: Text('正在整理媒体库…')),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sourceErrorMessage(error)),
                  TextButton(
                    onPressed: () => ref.invalidate(sidebarSourcesProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (sources) => _content(context, ref, sources, palette),
          ),
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    List<MediaSource> sources,
    SourceSheetPalette palette,
  ) {
    final layoutState = ref.watch(homeLayoutProvider);
    final layoutController = ref.read(homeLayoutProvider.notifier);
    final eligible = sources.where(HomeRepository.accepts).toList();
    final recommendation = ref.watch(homeRecommendationProvider);
    final modules = {
      for (final c in HomeCollection.values)
        c: ref.watch(homeCollectionProvider(c)),
    };
    var stats = const HomeStats();
    var ready = 0, loading = false;
    final errors = <String, String>{};
    for (final source in eligible) {
      final seed = ref.watch(homeSeedProvider(source.id));
      final summary = ref.watch(homeSourceStatsProvider(source.id));
      if (summary.value case final value?) {
        stats += value;
        ready++;
      }
      loading |= summary.isLoading || seed.isLoading;
      if (seed.hasError) {
        errors[source.id] = '${source.name}：${sourceErrorMessage(seed.error!)}';
      }
      if (summary.hasError) {
        errors[source.id] =
            '${source.name}：${sourceErrorMessage(summary.error!)}';
      }
    }
    for (final m in modules.values) {
      errors.addAll(m.errors);
      loading |= m.loading;
    }
    final partial = eligible.any(
      (s) => s.kind == MediaSourceKind.emby && s.lastScan == null,
    );
    final hasCards =
        modules.values.any((m) => m.items.isNotEmpty) ||
        recommendation.value?.hero.isNotEmpty == true;
    final h = DateTime.now().hour;
    final greeting = h >= 5 && h < 12
        ? '早上好'
        : h >= 12 && h < 14
        ? '中午好'
        : h >= 14 && h < 18
        ? '下午好'
        : h >= 18 && h < 23
        ? '晚上好'
        : '夜深了';
    return Stack(
      key: _viewportKey,
      children: [
        CustomScrollView(
          key: const PageStorageKey('home-overview'),
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(36, 28, 36, 0),
              sliver: SliverToBoxAdapter(
                child: HomeHeader(
                  greeting: greeting,
                  controller: _search,
                  onChanged: _changed,
                  onSubmit: _submit,
                ),
              ),
            ),
            if (sources.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(36),
                sliver: SliverToBoxAdapter(
                  child: _empty(
                    context,
                    palette,
                    '媒体源待添加',
                    '接入本地文件夹、移动硬盘、网络挂载或 Emby 媒体库后，ReelNest 会整理索引。',
                  ),
                ),
              )
            else if (_query.isNotEmpty)
              HomeSearchResults(key: ValueKey(_query), query: _query)
            else ...[
              if (loading || partial)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(36, 12, 36, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      loading
                          ? '正在整理媒体库… 已有内容可先浏览。'
                          : '显示已载入的内容；完整同步后将补齐统计与记录。',
                      style: TextStyle(fontSize: 12, color: palette.secondary),
                    ),
                  ),
                ),
              if (errors.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(36, 12, 36, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final error in errors.values)
                          Text(error, style: const TextStyle(fontSize: 12)),
                        TextButton(
                          onPressed: () {
                            ref.invalidate(homeVideoPageProvider);
                            ref.invalidate(homeSourceStatsProvider);
                            ref.invalidate(homeSeedProvider);
                            ref.invalidate(
                              homeRecommendationCandidatesProvider,
                            );
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final module in layoutState.layout.added)
                if (layoutState.editing ||
                    _hasModuleContent(module, recommendation.value, modules))
                  SliverToBoxAdapter(
                    key: ValueKey('home-module-${module.name}'),
                    child: HomeEditableModule(
                      module: module,
                      editing: layoutState.editing,
                      enabled: !layoutState.finishing,
                      canHide: layoutState.layout.added.length > 1,
                      dragged: _dragged,
                      onStart: () => setState(() => _dragged = module),
                      onMove: layoutController.move,
                      onEnd: _endDrag,
                      onUpdate: _updateDrag,
                      onHide: () => layoutController.hide(module),
                      padding: EdgeInsets.fromLTRB(
                        module == HomeModule.hero ? 12 : 36,
                        22,
                        module == HomeModule.hero ? 12 : 36,
                        0,
                      ),
                      child: _moduleContent(
                        module,
                        recommendation.value,
                        modules,
                        stats,
                        palette,
                        ready == 0 && eligible.isNotEmpty,
                      ),
                    ),
                  ),
              if (!hasCards &&
                  !loading &&
                  errors.isEmpty &&
                  stats.movies + stats.series == 0)
                SliverPadding(
                  padding: const EdgeInsets.all(36),
                  sliver: SliverToBoxAdapter(
                    child: _empty(
                      context,
                      palette,
                      '还没有可展示的视频',
                      '媒体源中的公开影视内容会在这里汇总。',
                    ),
                  ),
                ),
              if (!layoutState.editing)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
                  sliver: SliverToBoxAdapter(
                    child: HomeLayoutFooter(
                      state: layoutState,
                      onEdit: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        layoutController.begin();
                      },
                      onRetry: layoutController.retryLoad,
                    ),
                  ),
                ),
              if (layoutState.editing)
                const SliverToBoxAdapter(child: SizedBox(height: 82)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
        if (layoutState.editing && _query.isEmpty && sources.isNotEmpty)
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Center(
              child: HomeLayoutEditorDock(
                state: layoutState,
                controller: layoutController,
              ),
            ),
          ),
      ],
    );
  }

  bool _hasModuleContent(
    HomeModule module,
    HomeRecommendation? board,
    Map<HomeCollection, HomeCollectionState> collections,
  ) => switch (module) {
    HomeModule.hero => board?.hero.isNotEmpty == true,
    HomeModule.stats || HomeModule.dashboard => true,
    _ => collections[module.collection]?.items.isNotEmpty == true,
  };

  Widget _moduleContent(
    HomeModule module,
    HomeRecommendation? board,
    Map<HomeCollection, HomeCollectionState> collections,
    HomeStats stats,
    SourceSheetPalette palette,
    bool loading,
  ) => switch (module) {
    HomeModule.hero =>
      board?.hero.isNotEmpty == true
          ? HomeHero(board: board!)
          : const SizedBox.shrink(),
    HomeModule.stats => _stats(stats, palette, loading),
    HomeModule.dashboard => const HomeRuntimeStatus(),
    _ =>
      collections[module.collection]?.items.isNotEmpty == true
          ? HomeVideoRow(
              key: ValueKey(module.collection!),
              collection: module.collection!,
              items: collections[module.collection]!.items,
            )
          : const SizedBox.shrink(),
  };

  Widget _empty(
    BuildContext context,
    SourceSheetPalette palette,
    String title,
    String subtitle,
  ) => Container(
    constraints: const BoxConstraints(minHeight: 480),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_to_drive_outlined, size: 62, color: palette.accent),
        const SizedBox(height: 32),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.secondary),
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => context.go('/sources'),
          icon: const Icon(Icons.arrow_circle_right),
          label: const Text('前往媒体源添加'),
        ),
      ],
    ),
  );
  Widget _stats(HomeStats stats, SourceSheetPalette p, bool loading) {
    final tiles = [
      (stats.movies, '影片', Icons.movie_outlined, const Color(0xFF2E90FA)),
      (stats.series, '系列', Icons.layers_outlined, const Color(0xFF22D3A8)),
      (
        stats.episodes,
        '剧集',
        Icons.video_library_outlined,
        const Color(0xFFFF9F45),
      ),
      (
        stats.unwatched,
        '未观看',
        Icons.visibility_outlined,
        const Color(0xFFFF5C8A),
      ),
    ];
    return LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth < 650 ? 2 : 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final t in tiles)
              Container(
                width: (size.maxWidth - 16 * (columns - 1)) / columns,
                height: 87,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.$4,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(t.$3, color: Colors.white, size: 21),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                loading ? '—' : _count(t.$1),
                                key: ValueKey('home-stat-${t.$2}'),
                                style: TextStyle(
                                  fontSize: 27,
                                  height: 1.1,
                                  fontWeight: FontWeight.w900,
                                  color: t.$4,
                                ),
                              ),
                            ),
                          ),
                          Text(
                            t.$2,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: p.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _count(int value) =>
      value >= 10000 ? '${value ~/ 1000}K' : value.toString();
}
