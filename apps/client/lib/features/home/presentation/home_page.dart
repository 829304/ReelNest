import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../sources/application/source_providers.dart';
import '../application/home_providers.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';
import 'widgets/home_video_row.dart';
import 'widgets/home_hero.dart';
import 'widgets/home_page_background.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox();
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
    return CustomScrollView(
      key: const PageStorageKey('home-overview'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(36, 28, 36, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting，欢迎回来',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: '今天，'),
                      WidgetSpan(
                        child: ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (rect) => const LinearGradient(
                            colors: [
                              Color(0xFF36BFFA),
                              Color(0xFF2E90FA),
                              Color(0xFFFF9F45),
                              Color(0xFFFF5C8A),
                            ],
                          ).createShader(rect),
                          child: const Text(
                            '为你精选',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const TextSpan(text: '了一份片单'),
                    ],
                  ),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
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
        else ...[
          if (recommendation.value?.hero.isNotEmpty == true)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 22, 12, 0),
              sliver: SliverToBoxAdapter(
                child: HomeHero(board: recommendation.value!),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(36, 22, 36, 0),
            sliver: SliverToBoxAdapter(
              child: _stats(stats, palette, ready == 0 && eligible.isNotEmpty),
            ),
          ),
          if (loading || partial)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(36, 12, 36, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  loading ? '正在整理媒体库… 已有内容可先浏览。' : '显示已载入的内容；完整同步后将补齐统计与记录。',
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
                        ref.invalidate(homeRecommendationCandidatesProvider);
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          for (final c in HomeCollection.values)
            if (modules[c]!.items.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(36, 22, 36, 0),
                sliver: SliverToBoxAdapter(
                  child: HomeVideoRow(
                    key: ValueKey(c),
                    collection: c,
                    items: modules[c]!.items,
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
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

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
