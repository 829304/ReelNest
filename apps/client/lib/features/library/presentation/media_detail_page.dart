import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/media.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/status_notice.dart';
import '../application/library_providers.dart';
import 'authenticated_artwork.dart';
import 'browse_page.dart';

class MediaDetailPage extends ConsumerWidget {
  const MediaDetailPage({required this.type, required this.id,
    required this.isSeries, super.key});
  final String type;
  final String id;
  final bool isSeries;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('media-browse', pathParameters: {'type': type});
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(libraryScopeProvider);
    if (scope == null) return const LibraryLoginPrompt();
    final key = (scope: scope, id: id, isSeries: isSeries);
    final result = ref.watch(mediaDetailProvider(key));
    return PageContent(title: '媒体详情', subtitle: mediaTypes[type] ?? '媒体库', children: [
      Align(alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: () => _back(context),
          icon: const Icon(Icons.arrow_back), label: const Text('返回'))),
      const SizedBox(height: 24),
      if (result.isRefreshing) const LinearProgressIndicator(),
      result.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(32),
          child: CircularProgressIndicator())),
        error: (error, _) => StatusNotice(message: AppFailure.from(error).message,
          onRetry: () => ref.invalidate(mediaDetailProvider(key))),
        data: (detail) => Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailHero(scope: scope, detail: detail),
            const SizedBox(height: 24),
            Text('简介', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SelectableText(detail.overview?.trim().isNotEmpty == true
                ? detail.overview! : '暂无简介'),
            if (detail.seriesSummary case final summary?) ...[
              const SizedBox(height: 28),
              _EpisodesPanel(key: ValueKey('$scope:${detail.item.id}'),
                scope: scope, seriesId: detail.item.id,
                seriesTitle: detail.item.title, seasons: summary.seasons,
                category: type),
            ] else if (detail.episodeContext case final series?) ...[
              const SizedBox(height: 28),
              _EpisodesPanel(key: ValueKey('$scope:${series.seriesId}'),
                scope: scope, seriesId: series.seriesId,
                seriesTitle: series.seriesTitle, seasons: series.seasons,
                currentSeason: series.currentSeason, currentItemId: detail.item.id,
                category: type),
            ] else if (isSeries) ...[
              const SizedBox(height: 24),
              const Text('当前服务器尚未支持系列季列表。升级服务器后，刷新详情即可查看。'),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(onPressed: result.isRefreshing ? null
                : () => ref.invalidate(mediaDetailProvider(key)),
              icon: const Icon(Icons.refresh), label: const Text('刷新详情')),
          ]),
      ),
    ]);
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.scope, required this.detail});
  final int scope;
  final MediaDetail detail;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final metadata = <String>[
      if (item.year != null) '${item.year}',
      if (detail.communityRating != null) '★ ${detail.communityRating!.toStringAsFixed(1)} / 10',
      if (item.durationSeconds != null) '${(item.durationSeconds! / 60).ceil()} 分钟',
      if (detail.resolution?.isNotEmpty == true) detail.resolution!,
      if (detail.videoCodec?.isNotEmpty == true) detail.videoCodec!,
      if (detail.audioCodec?.isNotEmpty == true) detail.audioCodec!,
      if (item.watched) '已看',
      if (detail.seriesSummary case final summary?)
        '${summary.totalEpisodeCount} 集 · ${summary.seasons.length} 个季分组',
    ];
    final information = Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600)),
        if (detail.originalTitle?.isNotEmpty == true && detail.originalTitle != item.title) ...[
          const SizedBox(height: 10), Text(detail.originalTitle!),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8,
          children: metadata.map((text) => Chip(label: Text(text))).toList()),
        if (detail.genres.isNotEmpty) ...[
          const SizedBox(height: 14), Text(detail.genres.join(' · ')),
        ],
        const SizedBox(height: 20),
        const Text('播放功能尚未接入。'),
      ]);
    return LayoutBuilder(builder: (context, constraints) {
      final landscape = item.type == 'episode';
      final posterWidth = landscape ? 320.0 : 210.0;
      final poster = SizedBox(width: posterWidth, child: AspectRatio(
        aspectRatio: landscape ? 16 / 9 : item.posterRatio,
        child: ClipRRect(borderRadius: BorderRadius.circular(12),
          child: AuthenticatedArtwork(scope: scope, id: item.id,
            available: item.artworkAvailable)),
      ));
      if (constraints.maxWidth < 680) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: poster),
          const SizedBox(height: 24), information,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        poster, const SizedBox(width: 24), Expanded(child: information),
      ]);
    });
  }
}

class _EpisodesPanel extends ConsumerStatefulWidget {
  const _EpisodesPanel({required this.scope, required this.seriesId,
    required this.seriesTitle, required this.seasons, required this.category,
    this.currentSeason, this.currentItemId, super.key});
  final int scope;
  final String seriesId;
  final String seriesTitle;
  final List<MediaSeason> seasons;
  final int? currentSeason;
  final String? currentItemId;
  final String category;
  @override
  ConsumerState<_EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends ConsumerState<_EpisodesPanel> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final seasons = widget.seasons;
    if (seasons.isEmpty) return const Text('此系列暂未提供季集信息。');
    final preferred = _selected ?? (widget.currentItemId == null
        ? seasons.first.selector : widget.currentSeason?.toString() ?? 'unspecified');
    final selected = seasons.any((season) => season.selector == preferred)
        ? preferred : seasons.first.selector;
    final season = seasons.firstWhere((season) => season.selector == selected);
    final key = (scope: widget.scope, type: 'episode', sort: MediaSort.title,
      seriesId: widget.seriesId as String?, season: selected as String?);
    final state = ref.watch(browseProvider(key));
    final controller = ref.read(browseProvider(key).notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.seriesTitle, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text('已看 ${season.watchedCount} 集 · 观看中 ${season.inProgressCount} 集'),
      const SizedBox(height: 8),
      DropdownButton<String>(value: selected, isExpanded: true,
        items: seasons.map((season) => DropdownMenuItem(value: season.selector,
          child: Text('${season.title} · ${season.episodeCount} 集',
            maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (value) => setState(() => _selected = value)),
      const SizedBox(height: 12),
      Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('已加载 ${state.items.length} / ${state.total} 集'),
        TextButton(onPressed: state.loading ? null : controller.refresh,
          child: const Text('刷新剧集')),
      ]),
      if (state.loading) const LinearProgressIndicator(),
      if (state.failure case final failure?)
        StatusNotice(message: failure.message,
          onRetry: state.appendFailure ? controller.loadMore : controller.refresh),
      if (!state.loading && state.failure == null && state.items.isEmpty)
        const Text('这一季暂时没有可访问的剧集。'),
      for (final episode in state.items)
        Card(child: ListTile(
          selected: episode.id == widget.currentItemId,
          title: Text(episode.title),
          subtitle: Text([
            if (episode.episodeNumber != null) '第 ${episode.episodeNumber} 集',
            if (episode.durationSeconds != null) '${(episode.durationSeconds! / 60).ceil()} 分钟',
            if (episode.watched) '已看',
            if (!episode.watched && episode.progress > 0)
              '已观看 ${(episode.progress * 100).round()}%',
            if (episode.id == widget.currentItemId) '当前单集',
          ].join(' · ')),
          trailing: Icon(episode.id == widget.currentItemId
              ? Icons.check_circle_outline : Icons.chevron_right),
          onTap: episode.id == widget.currentItemId ? null
              : () => context.pushNamed('media-detail',
            pathParameters: {'type': widget.category, 'id': episode.id}),
        )),
      if (state.hasMore)
        OutlinedButton(onPressed: state.loading || state.loadingMore
            ? null : controller.loadMore,
          child: Text(state.loadingMore ? '正在加载…' : '加载更多剧集')),
      if (state.limitReached) const Text('已达到服务器分页上限。'),
    ]);
  }
}
