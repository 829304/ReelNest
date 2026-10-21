import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/presentation/video_player_page.dart'
    show formatVideoTime;
import '../application/source_providers.dart';
import 'local_media_artwork.dart';
import 'emby_media_actions.dart';
import 'emby_video_context_menu.dart';
import 'marker_analysis_menu.dart';
import '../../../api/emby/emby_detail.dart';
import '../application/emby_providers.dart';
import 'emby_detail_extras.dart';
import 'emby_cache_actions.dart';
import '../../library/presentation/local_video_actions.dart';

/// Local-data counterpart of DetailView.swift / EpisodeListView.swift.
/// Playback delegates to the independent window; extras and native material
/// remain separate ports.
class LocalMediaDetailPage extends ConsumerStatefulWidget {
  const LocalMediaDetailPage({required this.identity, super.key});
  final MediaIdentity identity;
  @override
  ConsumerState<LocalMediaDetailPage> createState() =>
      _LocalMediaDetailPageState();
}

class _LocalMediaDetailPageState extends ConsumerState<LocalMediaDetailPage> {
  final _expanded = <String>{};
  String? _selectedEpisode;
  int _detailRefresh = 0;

  Widget _inset(Widget child, {double top = 8, double bottom = 8}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(32, top, 32, bottom),
        sliver: SliverToBoxAdapter(child: child),
      );

  @override
  void didUpdateWidget(LocalMediaDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _expanded.clear();
      _selectedEpisode = null;
      _detailRefresh = 0;
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/sources/${Uri.encodeComponent(widget.identity.sourceId)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(sourceMediaDetailProvider(widget.identity));
    final sources = ref.watch(sourcesProvider);
    final source = sources.value
        ?.where((s) => s.id == widget.identity.sourceId)
        .firstOrNull;
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: palette.page,
          child: CustomScrollView(
            slivers: [
              _inset(
                _DetailPageHeader(
                  key: const ValueKey('media-detail-header'),
                  title: source?.name ?? '媒体库',
                  remote: source?.kind == MediaSourceKind.emby,
                  onBack: _back,
                  palette: palette,
                ),
                top: 28,
              ),
              if (sources.hasError && source == null)
                _inset(
                  _DetailStatusCard(
                    palette: palette,
                    icon: Icons.cloud_off_rounded,
                    title: sourceErrorMessage(sources.error!),
                    message: '媒体源状态读取失败，现有媒体数据不会被删除。',
                  ),
                )
              else if (!sources.isLoading && sources.hasValue && source == null)
                _inset(
                  _DetailStatusCard(
                    palette: palette,
                    icon: Icons.folder_off_outlined,
                    title: '此媒体源已移除。',
                    message: '可以返回媒体库，选择其他仍然可用的内容。',
                  ),
                )
              else
                ...detail.when(
                  skipLoadingOnReload: true,
                  loading: () => [
                    _inset(
                      _DetailLoadingCard(
                        key: const ValueKey('media-detail-loading'),
                        palette: palette,
                      ),
                    ),
                  ],
                  error: (error, stack) => [
                    _inset(
                      _DetailStatusCard(
                        palette: palette,
                        icon: Icons.error_outline_rounded,
                        title: sourceErrorMessage(error),
                        message: '详情读取失败，可以返回媒体库或重新尝试。',
                        actionLabel: '重试',
                        onAction: () => ref.invalidate(
                          sourceMediaDetailProvider(widget.identity),
                        ),
                      ),
                    ),
                  ],
                  data: (item) {
                    if (source == null) {
                      return [
                        _inset(
                          _DetailLoadingCard(
                            key: const ValueKey('media-detail-loading'),
                            palette: palette,
                          ),
                        ),
                      ];
                    }
                    final extras = source.kind == MediaSourceKind.emby
                        ? ref.watch(
                            embyDetailProvider((
                              identity: item.identity,
                              refresh: _detailRefresh,
                            )),
                          )
                        : null;
                    return [
                      _inset(
                        _DetailHero(
                          source: source,
                          item: item,
                          detail: extras?.asData?.value.detail,
                          // Reading metadata is not an artwork invalidation.
                          // Explicit refresh still fetches a new generation.
                          artworkRevision: _detailRefresh == 0
                              ? null
                              : extras
                                    ?.asData
                                    ?.value
                                    .fetchedAt
                                    .millisecondsSinceEpoch,
                        ),
                      ),
                      if (extras != null)
                        _inset(
                          extras.when(
                            loading: () => _DetailInlineNotice(
                              palette: palette,
                              icon: Icons.auto_awesome_motion_outlined,
                              title: '正在整理演职人员、艺术照和相关作品…',
                              loading: true,
                            ),
                            error: (_, _) => _DetailInlineNotice(
                              palette: palette,
                              icon: Icons.cloud_off_rounded,
                              title: 'Emby 详情读取失败，基础信息和播放仍可使用。',
                              actionLabel: '重试',
                              onAction: () => setState(() => _detailRefresh++),
                            ),
                            data: (snapshot) => EmbyDetailExtras(
                              key: ValueKey(item.identity),
                              source: source,
                              item: item,
                              snapshot: snapshot,
                              onRefresh: () => setState(() => _detailRefresh++),
                            ),
                          ),
                        ),
                      if (item.isSeries)
                        ..._series(source, item)
                      else
                        _inset(
                          source.kind.isFileSource
                              ? _LocalFileStatus(source: source, item: item)
                              : _RemoteFileStatus(
                                  item: item,
                                  detail: extras?.asData?.value.detail,
                                ),
                          top: 12,
                          bottom: 28,
                        ),
                    ];
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _series(MediaSource source, IndexedMedia item) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final foreground =
        source.kind == MediaSourceKind.emby && source.lastScan == null
        ? ref.watch(embySeriesEpisodesProvider(item.identity))
        : null;
    final result = ref.watch(sourceSeasonsProvider(item.identity));
    return result.when(
      loading: () => [
        _inset(
          _DetailInlineNotice(
            palette: palette,
            icon: Icons.list_rounded,
            title: '正在读取剧集…',
            loading: true,
          ),
        ),
      ],
      error: (error, stack) => [
        _inset(
          _DetailInlineNotice(
            palette: palette,
            icon: Icons.error_outline_rounded,
            title: sourceErrorMessage(error),
            actionLabel: '重试',
            onAction: () =>
                ref.invalidate(sourceSeasonsProvider(item.identity)),
          ),
        ),
      ],
      data: (seasons) {
        final count = seasons.fold<int>(0, (n, s) => n + s.episodeCount);
        final grouped = seasons.length > 1;
        return [
          if (foreground?.isLoading == true)
            _inset(
              _DetailInlineNotice(
                palette: palette,
                icon: Icons.cloud_sync_outlined,
                title: '正在读取服务端剧集…',
                loading: true,
              ),
            ),
          if (foreground?.hasError == true)
            _inset(
              _DetailInlineNotice(
                palette: palette,
                icon: Icons.cloud_off_rounded,
                title: '剧集读取失败',
                actionLabel: '重试',
                onAction: () =>
                    ref.invalidate(embySeriesEpisodesProvider(item.identity)),
              ),
            ),
          _inset(
            Row(
              children: [
                const Text(
                  '剧集',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text('$count 集'),
                if (source.kind == MediaSourceKind.emby) ...[
                  const SizedBox(width: 10),
                  EmbyBatchWatchedButton(series: item.identity),
                ],
              ],
            ),
            top: 12,
            bottom: 6,
          ),
          for (final season in seasons) ...[
            if (grouped)
              _inset(
                _SeasonHeader(
                  season: season,
                  expanded: _expanded.contains(season.key),
                  onToggle: () => setState(() {
                    if (!_expanded.remove(season.key)) {
                      _expanded.add(season.key);
                    }
                  }),
                  actions: source.kind == MediaSourceKind.emby
                      ? EmbyBatchWatchedButton(
                          series: item.identity,
                          oneSeason: true,
                          season: season.number,
                        )
                      : null,
                ),
                top: 5,
                bottom: 5,
              ),
            if (!grouped || _expanded.contains(season.key))
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                sliver: SliverList.builder(
                  itemCount: season.episodeCount,
                  itemBuilder: (context, index) => _EpisodeAtIndex(
                    key: ValueKey((item.identity, season.key, index)),
                    source: source,
                    series: item.identity,
                    season: season.number,
                    index: index,
                    selectedId: _selectedEpisode,
                    onSelect: (id) => setState(() => _selectedEpisode = id),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ];
      },
    );
  }
}

class _DetailPageHeader extends StatelessWidget {
  const _DetailPageHeader({
    required this.title,
    required this.remote,
    required this.onBack,
    required this.palette,
    super.key,
  });

  final String title;
  final bool remote;
  final VoidCallback onBack;
  final SourceSheetPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: palette.border, width: .8),
      boxShadow: [
        BoxShadow(
          color: palette.shadow.withValues(alpha: palette.dark ? .16 : .045),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: palette.iconChip,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border, width: .8),
          ),
          child: Icon(
            remote ? Icons.video_library_outlined : Icons.folder_outlined,
            size: 20,
            color: palette.selectedTint,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.08,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '媒体详情',
                style: TextStyle(
                  color: palette.secondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SourceSheetButton(
          key: const ValueKey('media-detail-back'),
          label: '返回',
          icon: const Icon(Icons.chevron_left_rounded, size: 17),
          height: 36,
          horizontalPadding: 12,
          outlined: true,
          onPressed: onBack,
        ),
      ],
    ),
  );
}

class _DetailStatusCard extends StatelessWidget {
  const _DetailStatusCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final SourceSheetPalette palette;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 250),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: palette.border, width: .8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.selectedTint.withValues(alpha: .10),
          ),
          child: Icon(icon, size: 27, color: palette.selectedTint),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.secondary, fontSize: 12.5),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          SourceSheetButton(
            label: actionLabel!,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            height: 34,
            horizontalPadding: 12,
            outlined: true,
            onPressed: onAction,
          ),
        ],
      ],
    ),
  );
}

class _DetailInlineNotice extends StatelessWidget {
  const _DetailInlineNotice({
    required this.palette,
    required this.icon,
    required this.title,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final SourceSheetPalette palette;
  final IconData icon;
  final String title;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border, width: .8),
    ),
    child: Row(
      children: [
        if (loading)
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              value: .72,
              strokeWidth: 2,
              color: palette.selectedTint,
            ),
          )
        else
          Icon(icon, size: 18, color: palette.selectedTint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.secondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(width: 10),
          SourceSheetButton(
            label: actionLabel!,
            height: 30,
            horizontalPadding: 10,
            outlined: true,
            onPressed: onAction,
          ),
        ],
      ],
    ),
  );
}

class _DetailLoadingCard extends StatelessWidget {
  const _DetailLoadingCard({required this.palette, super.key});

  final SourceSheetPalette palette;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 1100),
    curve: Curves.easeInOut,
    builder: (context, shimmer, _) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border, width: .8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final poster = _DetailSkeletonBlock(
            palette: palette,
            shimmer: shimmer,
            radius: 12,
            width: constraints.maxWidth < 620 ? 150 : 210,
            height: constraints.maxWidth < 620 ? 225 : 315,
          );
          final information = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailSkeletonBlock(
                palette: palette,
                shimmer: shimmer,
                radius: 6,
                height: 30,
                widthFactor: .72,
              ),
              const SizedBox(height: 18),
              _DetailSkeletonBlock(
                palette: palette,
                shimmer: shimmer,
                radius: 12,
                height: 28,
                widthFactor: .58,
              ),
              const SizedBox(height: 20),
              for (final width in [.96, .88, .74]) ...[
                _DetailSkeletonBlock(
                  palette: palette,
                  shimmer: shimmer,
                  radius: 4,
                  height: 10,
                  widthFactor: width,
                ),
                const SizedBox(height: 9),
              ],
              const SizedBox(height: 18),
              _DetailSkeletonBlock(
                palette: palette,
                shimmer: shimmer,
                radius: 12,
                height: 34,
                width: 104,
              ),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [poster, const SizedBox(height: 22), information],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              poster,
              const SizedBox(width: 24),
              Expanded(child: information),
            ],
          );
        },
      ),
    ),
  );
}

class _DetailSkeletonBlock extends StatelessWidget {
  const _DetailSkeletonBlock({
    required this.palette,
    required this.shimmer,
    required this.radius,
    required this.height,
    this.width,
    this.widthFactor,
  });

  final SourceSheetPalette palette;
  final double shimmer;
  final double radius;
  final double height;
  final double? width;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(-2.6 + shimmer * 4, 0),
          end: Alignment(-1.2 + shimmer * 4, 0),
          colors: [
            palette.control,
            Colors.white.withValues(alpha: palette.dark ? .10 : .58),
            palette.control,
          ],
        ),
      ),
    );
    if (widthFactor == null) return block;
    return FractionallySizedBox(widthFactor: widthFactor, child: block);
  }
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.source,
    required this.item,
    this.detail,
    this.artworkRevision,
  });
  final MediaSource source;
  final IndexedMedia item;
  final EmbyDetail? detail;
  final int? artworkRevision;
  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final landscape = item.type == 'episode';
    final remote = item.remote;
    final metadata = <({IconData icon, String label})>[
      (
        icon: Icons.calendar_today_outlined,
        label: item.year?.toString() ?? '未知年份',
      ),
      if (remote?.rating case final rating?)
        (icon: Icons.star_rounded, label: rating.toStringAsFixed(1)),
      if (remote?.durationMs case final duration?)
        (icon: Icons.schedule_rounded, label: '${duration ~/ 60000} 分钟'),
      if ((detail?.technical.resolution ?? remote?.resolution)
          case final resolution?)
        (icon: Icons.aspect_ratio_rounded, label: resolution),
      if (detail?.status case final status?)
        (icon: Icons.podcasts_rounded, label: status),
      if (detail?.contentRating case final contentRating?)
        (icon: Icons.person_outline_rounded, label: contentRating),
    ];
    final titleActions = source.kind == MediaSourceKind.emby
        ? EmbyMediaActions(item: item, favoriteOnly: true)
        : source.kind.isFileSource
        ? LocalVideoActions(identity: item.identity)
        : null;
    final artwork = MarkerAnalysisContextMenu(
      identity: item.identity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .24),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: AspectRatio(
          aspectRatio: landscape ? 16 / 9 : 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                LocalMediaArtwork(
                  source: source,
                  item: item,
                  fit: BoxFit.cover,
                  revision: artworkRevision,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x20FFFFFF), Color(0x00000000)],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .30),
                      width: .85,
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 34,
                  height: 1.10,
                  letterSpacing: -.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (titleActions != null) ...[
              const SizedBox(width: 12),
              _DetailTitleActions(palette: palette, child: titleActions),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: metadata
              .map(
                (entry) => _DetailMetadataChip(
                  icon: entry.icon,
                  label: entry.label,
                  palette: palette,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 15),
        Text(
          detail?.overview ?? item.overview ?? '暂无简介。',
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.secondary,
            fontSize: 13,
            height: 1.48,
          ),
        ),
        if (remote != null && (detail?.genres ?? remote.genres).isNotEmpty) ...[
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: (detail?.genres ?? remote.genres)
                .map(
                  (genre) => _DetailGenreChip(label: genre, palette: palette),
                )
                .toList(),
          ),
        ],
        if (detail?.companies.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.business_outlined, size: 15, color: palette.secondary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  detail!.companies.take(4).join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.secondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (item.type != 'music' && item.type != 'photo') ...[
          const SizedBox(height: 18),
          _DetailActionBar(
            key: const ValueKey('media-detail-actions'),
            palette: palette,
            children: [
              _PlaybackButton(
                item: item,
                enabled:
                    source.kind.isFileSource ||
                    source.kind == MediaSourceKind.emby,
              ),
              if (source.kind == MediaSourceKind.emby && !item.isSeries)
                EmbyMediaActions(item: item),
              if (source.kind == MediaSourceKind.emby)
                EmbyCacheActions(item: item),
            ],
          ),
        ],
      ],
    );
    return Container(
      key: const ValueKey('media-detail-hero'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border, width: .9),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: palette.dark ? .17 : .05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: landscape
                        ? constraints.maxWidth.clamp(240, 360)
                        : 180,
                    child: artwork,
                  ),
                ),
                const SizedBox(height: 24),
                information,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: landscape ? 320 : 210, child: artwork),
              const SizedBox(width: 24),
              Expanded(child: information),
            ],
          );
        },
      ),
    );
  }
}

class _DetailTitleActions extends StatelessWidget {
  const _DetailTitleActions({required this.palette, required this.child});

  final SourceSheetPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.control,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: palette.border, width: .8),
    ),
    clipBehavior: Clip.antiAlias,
    child: IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.menuText,
          minimumSize: const Size(34, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          hoverColor: palette.hoverPill,
          focusColor: palette.selectedTint.withValues(alpha: .10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    ),
  );
}

class _DetailActionBar extends StatelessWidget {
  const _DetailActionBar({
    required this.palette,
    required this.children,
    super.key,
  });

  final SourceSheetPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          if (index == 0)
            children[index]
          else
            _DetailSecondaryActionSurface(
              palette: palette,
              child: children[index],
            ),
        ],
      ],
    ),
  );
}

class _DetailSecondaryActionSurface extends StatelessWidget {
  const _DetailSecondaryActionSurface({
    required this.palette,
    required this.child,
  });

  final SourceSheetPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: palette.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: palette.border, width: .9),
    ),
    clipBehavior: Clip.antiAlias,
    child: TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.menuText,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
      ),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: palette.menuText,
            minimumSize: const Size(32, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            hoverColor: palette.hoverPill,
          ),
        ),
        child: child,
      ),
    ),
  );
}

class _DetailMetadataChip extends StatelessWidget {
  const _DetailMetadataChip({
    required this.icon,
    required this.label,
    required this.palette,
  });
  final IconData icon;
  final String label;
  final SourceSheetPalette palette;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.control.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: palette.border, width: .75),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: palette.secondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: palette.secondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailGenreChip extends StatelessWidget {
  const _DetailGenreChip({required this.label, required this.palette});
  final String label;
  final SourceSheetPalette palette;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.selectedTint.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: palette.selectedTint.withValues(alpha: .20),
        width: .7,
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: palette.selectedTint,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _SeasonHeader extends StatelessWidget {
  const _SeasonHeader({
    required this.season,
    required this.expanded,
    required this.onToggle,
    this.actions,
  });
  final IndexedSeason season;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? actions;
  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                hoverColor: palette.hoverPill,
                focusColor: palette.selectedTint.withValues(alpha: .10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: expanded ? .25 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: palette.secondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        season.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${season.episodeCount} 集',
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.secondary,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (actions != null)
            Padding(padding: const EdgeInsets.only(right: 4), child: actions!),
        ],
      ),
    );
  }
}

/// Paging is internal: scrolling loads visible rows without changing the
/// original expandable season interaction into previous/next page controls.
class _EpisodeAtIndex extends ConsumerWidget {
  const _EpisodeAtIndex({
    required this.source,
    required this.series,
    required this.season,
    required this.index,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });
  final MediaSource source;
  final MediaIdentity series;
  final int? season;
  final int index;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (series: series, season: season, offset: (index ~/ 60) * 60);
    final result = ref.watch(sourceEpisodesProvider(key));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: result.when(
        loading: () => const SizedBox(
          height: 88,
          child: Center(
            child: SizedBox(width: 120, child: LinearProgressIndicator()),
          ),
        ),
        error: (error, stack) => SizedBox(
          height: 88,
          child: TextButton(
            onPressed: () => ref.invalidate(sourceEpisodesProvider(key)),
            child: Text('${sourceErrorMessage(error)} 重试'),
          ),
        ),
        data: (page) {
          final position = index % 60;
          if (position >= page.items.length) return const SizedBox.shrink();
          final item = page.items[position];
          return _EpisodeRow(
            source: source,
            item: item,
            selected: selectedId == item.identity.localId,
            onSelect: () => onSelect(item.identity.localId),
          );
        },
      ),
    );
  }
}

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({
    required this.source,
    required this.item,
    required this.selected,
    required this.onSelect,
  });
  final MediaSource source;
  final IndexedMedia item;
  final bool selected;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    Future<void> play() async {
      if (!source.kind.isFileSource && source.kind != MediaSourceKind.emby) {
        return;
      }
      try {
        await ref.read(playbackLauncherProvider).open(item.identity);
      } catch (_) {
        if (context.mounted) {
          showAppToast(context, '无法打开播放器，请重试。', kind: AppFeedbackKind.error);
        }
      }
    }

    final record = ref
        .watch(playbackRecordProvider(item.identity))
        .asData
        ?.value;
    final watched = record?.watched == true;
    final progress = record?.progress ?? 0;
    final inProgress = !watched && progress > .015;
    final row = GestureDetector(
      onDoubleTap:
          source.kind.isFileSource || source.kind == MediaSourceKind.emby
          ? () {
              onSelect();
              play();
            }
          : null,
      child: Stack(
        children: [
          TextButton(
            onPressed: onSelect,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.all(10),
              foregroundColor: palette.text,
              backgroundColor: selected
                  ? palette.selectedTint.withValues(alpha: .08)
                  : palette.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected
                      ? palette.selectedTint.withValues(alpha: .42)
                      : Colors.transparent,
                  width: 1.2,
                ),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 120,
                    height: 68,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LocalMediaArtwork(source: source, item: item),
                        if (watched)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: .30),
                          ),
                        if (inProgress)
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress.clamp(0, 1),
                              child: Container(
                                height: 4,
                                color: palette.selectedTint,
                              ),
                            ),
                          ),
                        if (watched)
                          Positioned(
                            right: 5,
                            top: 5,
                            child: Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: palette.selectedTint,
                              shadows: const [
                                Shadow(
                                  color: Colors.black45,
                                  blurRadius: 3,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .18),
                                width: .7,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Opacity(
                                    opacity: watched ? .7 : 1,
                                    child: Text(
                                      item.cardTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                if (inProgress) ...[
                                  const SizedBox(width: 7),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: palette.selectedTint.withValues(
                                        alpha: .13,
                                      ),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text(
                                      '继续观看',
                                      style: TextStyle(
                                        color: palette.selectedTint,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (item.remote?.durationMs case final duration?) ...[
                            const SizedBox(width: 10),
                            Text(
                              '${duration ~/ 60000} 分钟',
                              style: TextStyle(
                                color: palette.secondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 31,
                        child: item.overview == null
                            ? Align(
                                alignment: Alignment.topLeft,
                                child: Text(
                                  '暂无本集简介',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.secondary.withValues(
                                      alpha: .68,
                                    ),
                                  ),
                                ),
                              )
                            : Text(
                                item.overview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.35,
                                  color: palette.secondary,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                if (source.kind == MediaSourceKind.emby)
                  EmbyCacheActions(item: item, compact: true),
                if (selected)
                  SourceLineIcon(
                    SourceGlyph.checkCircle,
                    size: 20,
                    color: palette.selectedTint,
                  )
                else
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.secondary),
                    ),
                  ),
              ],
            ),
          ),
          if (selected)
            Positioned(
              left: 3,
              top: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: palette.selectedTint.withValues(alpha: .82),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return source.kind == MediaSourceKind.emby
        ? EmbyVideoContextMenu(item: item, child: row)
        : source.kind.isFileSource
        ? MarkerAnalysisContextMenu(identity: item.identity, child: row)
        : row;
  }
}

class _PlaybackButton extends ConsumerStatefulWidget {
  const _PlaybackButton({required this.item, required this.enabled});
  final IndexedMedia item;
  final bool enabled;
  @override
  ConsumerState<_PlaybackButton> createState() => _PlaybackButtonState();
}

class _PlaybackButtonState extends ConsumerState<_PlaybackButton> {
  bool _opening = false;
  Future<void> _play() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      var identity = widget.item.identity;
      if (widget.item.isSeries) {
        await prepareEmbySeries(ref, [identity]);
        final repository = ref.read(sourceRepositoryProvider);
        final seasons = await repository.seasons(identity);
        if (seasons.isEmpty) throw const SourceFailure('此媒体没有可播放文件。');
        final episodes = await repository.episodes(
          identity,
          seasonNumber: seasons.first.number,
          limit: 1,
        );
        if (episodes.items.isEmpty) throw const SourceFailure('此媒体没有可播放文件。');
        identity = episodes.items.first.identity;
      }
      await ref.read(playbackLauncherProvider).open(identity);
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          error is SourceFailure ? error.message : '无法打开播放器，请重试。',
          kind: AppFeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.item.isSeries
        ? null
        : ref.watch(playbackRecordProvider(widget.item.identity)).asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SourceSheetButton(
          label: '播放',
          icon: const Icon(Icons.play_arrow, size: 15),
          prominent: true,
          height: 34,
          horizontalPadding: 14,
          onPressed: _opening || !widget.enabled ? null : _play,
        ),
        if (record?.lastPlayedAt != null || record?.watched == true) ...[
          const SizedBox(height: 8),
          Text(
            record!.watched ? '已看' : '观看至 ${formatVideoTime(record.position)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _RemoteFileStatus extends ConsumerWidget {
  const _RemoteFileStatus({required this.item, this.detail});
  final IndexedMedia item;
  final EmbyDetail? detail;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final technical = detail?.technical;
    final video = technical?.videoCodec ?? item.remote?.videoCodec;
    final audio = technical?.audioCodec ?? item.remote?.audioCodec;
    final bitrate = technical?.bitrate ?? item.remote?.bitrate;
    final size = technical?.size ?? item.bytes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '文件',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: palette.iconChip,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.cloud_outlined,
                  size: 17,
                  color: palette.selectedTint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Emby 流媒体 · ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SourceSheetButton(
                label: '打开',
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                height: 32,
                horizontalPadding: 11,
                outlined: true,
                onPressed: () async {
                  try {
                    await ref
                        .read(playbackLauncherProvider)
                        .open(item.identity);
                  } catch (_) {
                    if (context.mounted) {
                      showAppToast(
                        context,
                        '无法打开播放器，请重试。',
                        kind: AppFeedbackKind.error,
                      );
                    }
                  }
                },
              ),
            ],
          ),
          if (video != null || audio != null || bitrate != null || size > 0)
            Text(
              [
                if (video != null) video.toUpperCase(),
                if (audio != null) audio.toUpperCase(),
                if (bitrate != null)
                  '${(bitrate / 1000000).toStringAsFixed(1)} Mbps',
                if (size > 0) '${(size / 1024 / 1024).toStringAsFixed(1)} MiB',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: palette.secondary),
            ),
        ],
      ),
    );
  }
}

class _LocalFileStatus extends StatefulWidget {
  const _LocalFileStatus({required this.source, required this.item});
  final MediaSource source;
  final IndexedMedia item;
  @override
  State<_LocalFileStatus> createState() => _LocalFileStatusState();
}

class _LocalFileStatusState extends State<_LocalFileStatus> {
  late Future<bool> _exists;
  String get _path => p.joinAll([
    widget.source.location,
    ...p.posix.split(widget.item.filePath!),
  ]);
  @override
  void initState() {
    super.initState();
    _exists = File(_path).exists();
  }

  @override
  void didUpdateWidget(_LocalFileStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.location != widget.source.location ||
        oldWidget.item != widget.item) {
      _exists = File(_path).exists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return FutureBuilder<bool>(
      future: _exists,
      builder: (context, snapshot) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border, width: .8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '文件',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: palette.iconChip,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: snapshot.connectionState != ConnectionState.done
                        ? SizedBox.square(
                            dimension: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.selectedTint,
                            ),
                          )
                        : SourceLineIcon(
                            snapshot.data == true
                                ? SourceGlyph.checkCircle
                                : SourceGlyph.warning,
                            size: 18,
                            color: snapshot.data == true
                                ? palette.selectedTint
                                : Colors.orange,
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(_path, maxLines: 1)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
