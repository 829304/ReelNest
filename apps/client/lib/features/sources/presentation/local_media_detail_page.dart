import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/presentation/video_player_page.dart'
    show formatVideoTime;
import '../application/source_providers.dart';
import 'local_media_artwork.dart';
import 'emby_media_actions.dart';
import '../../../api/emby/emby_detail.dart';
import '../application/emby_providers.dart';
import 'emby_detail_extras.dart';

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
    final source = sources.asData?.value
        .where((s) => s.id == widget.identity.sourceId)
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
                Row(
                  children: [
                    Text(
                      source?.name ?? '媒体库',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const Spacer(),
                    TextButton(onPressed: _back, child: const Text('返回')),
                  ],
                ),
                top: 28,
              ),
              if (sources.hasError)
                _inset(Text(sourceErrorMessage(sources.error!)))
              else if (sources.hasValue && source == null)
                _inset(const Text('此媒体源已移除。'))
              else
                ...detail.when(
                  loading: () => [_inset(const LinearProgressIndicator())],
                  error: (error, stack) => [
                    _inset(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sourceErrorMessage(error)),
                          TextButton(
                            onPressed: () => ref.invalidate(
                              sourceMediaDetailProvider(widget.identity),
                            ),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  data: (item) {
                    if (source == null) {
                      return [_inset(const LinearProgressIndicator())];
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
                        ),
                      ),
                      if (extras != null)
                        _inset(
                          extras.when(
                            loading: () => const Text('正在整理演职人员、艺术照和相关作品…'),
                            error: (_, _) => Row(
                              children: [
                                const Expanded(
                                  child: Text('Emby 详情读取失败，基础信息和播放仍可使用。'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _detailRefresh++),
                                  child: const Text('重试'),
                                ),
                              ],
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
    final result = ref.watch(sourceSeasonsProvider(item.identity));
    return result.when(
      loading: () => [_inset(const LinearProgressIndicator())],
      error: (error, stack) => [
        _inset(
          Column(
            children: [
              Text(sourceErrorMessage(error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(sourceSeasonsProvider(item.identity)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ],
      data: (seasons) {
        final count = seasons.fold<int>(0, (n, s) => n + s.episodeCount);
        final grouped = seasons.length > 1;
        return [
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

class _DetailHero extends StatelessWidget {
  const _DetailHero({required this.source, required this.item, this.detail});
  final MediaSource source;
  final IndexedMedia item;
  final EmbyDetail? detail;
  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final landscape = item.type == 'episode';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: landscape ? 320 : 210,
              child: AspectRatio(
                aspectRatio: landscape ? 16 / 9 : 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LocalMediaArtwork(
                    source: source,
                    item: item,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (source.kind == MediaSourceKind.emby)
                        EmbyMediaActions(item: item, favoriteOnly: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.secondary.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      child: Text(
                        item.year?.toString() ?? '未知年份',
                        style: TextStyle(
                          color: palette.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  if (item.remote case final remote?) ...[
                    const SizedBox(height: 10),
                    Text(
                      [
                        if (remote.rating != null)
                          '评分 ${remote.rating!.toStringAsFixed(1)}',
                        if (remote.durationMs != null)
                          '${remote.durationMs! ~/ 60000} 分钟',
                        ?detail?.technical.resolution ?? remote.resolution,
                        ?detail?.status,
                        ?detail?.contentRating,
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: palette.secondary),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    detail?.overview ?? item.overview ?? '暂无简介。',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.secondary),
                  ),
                  if (item.remote case final remote?) ...[
                    if ((detail?.genres ?? remote.genres).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        children: (detail?.genres ?? remote.genres)
                            .map(
                              (genre) => DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.selectedTint.withValues(
                                    alpha: .12,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  child: Text(
                                    genre,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.selectedTint,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (detail?.companies.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      Text(
                        detail!.companies.take(4).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.secondary,
                        ),
                      ),
                    ],
                  ],
                  if (item.type != 'music' && item.type != 'photo') ...[
                    const SizedBox(height: 16),
                    _PlaybackButton(
                      item: item,
                      enabled:
                          source.kind.isFileSource ||
                          source.kind == MediaSourceKind.emby,
                    ),
                    if (source.kind == MediaSourceKind.emby && !item.isSeries)
                      EmbyMediaActions(item: item),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    return SizedBox(
      height: 40,
      child: TextButton(
        onPressed: onToggle,
        style: TextButton.styleFrom(
          backgroundColor: palette.card,
          foregroundColor: palette.text,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? .25 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: Text(
                '›',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: palette.secondary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              season.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Text(
              '${season.episodeCount} 集',
              style: TextStyle(fontSize: 11, color: palette.secondary),
            ),
            const Spacer(),
            ?actions,
          ],
        ),
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
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法打开播放器，请重试。')));
        }
      }
    }

    return GestureDetector(
      onSecondaryTapDown: source.kind == MediaSourceKind.emby
          ? (details) =>
                showEmbyEpisodeMenu(context, ref, item, details.globalPosition)
          : null,
      onDoubleTap:
          source.kind.isFileSource || source.kind == MediaSourceKind.emby
          ? () {
              onSelect();
              play();
            }
          : null,
      child: TextButton(
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
            Stack(
              children: [
                SizedBox(
                  width: 120,
                  height: 68,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LocalMediaArtwork(source: source, item: item),
                  ),
                ),
                if (source.kind == MediaSourceKind.emby &&
                    ref
                            .watch(playbackRecordProvider(item.identity))
                            .asData
                            ?.value
                            .watched ==
                        true)
                  const Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(
                      Icons.visibility,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    alignment: Alignment.topLeft,
                    children: [
                      const ExcludeSemantics(
                        child: Opacity(
                          opacity: 0,
                          child: Text('占位\n占位', style: TextStyle(fontSize: 11)),
                        ),
                      ),
                      if (item.overview != null)
                        Text(
                          item.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.secondary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
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
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is SourceFailure ? error.message : '无法打开播放器，请重试。',
            ),
          ),
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
    final technical = detail?.technical;
    final video = technical?.videoCodec ?? item.remote?.videoCodec;
    final audio = technical?.audioCodec ?? item.remote?.audioCodec;
    final bitrate = technical?.bitrate ?? item.remote?.bitrate;
    final size = technical?.size ?? item.bytes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
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
              const Icon(Icons.cloud_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Emby 流媒体 · ${item.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(playbackLauncherProvider)
                        .open(item.identity);
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('无法打开播放器，请重试。')),
                      );
                    }
                  }
                },
                child: const Text('打开'),
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
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _exists,
    builder: (context, snapshot) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
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
              if (snapshot.connectionState != ConnectionState.done)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                SourceLineIcon(
                  snapshot.data == true
                      ? SourceGlyph.checkCircle
                      : SourceGlyph.warning,
                  size: 18,
                  color: snapshot.data == true
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Colors.orange,
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
