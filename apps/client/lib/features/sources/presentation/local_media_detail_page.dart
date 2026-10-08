import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/source_icons.dart';
import '../application/source_providers.dart';
import 'local_media_artwork.dart';

/// Local-data counterpart of DetailView.swift / EpisodeListView.swift.
/// Playback, watched state, extras and native material remain separate ports.
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
                    return [
                      _inset(_DetailHero(source: source, item: item)),
                      if (item.isSeries)
                        ..._series(source, item)
                      else
                        _inset(
                          _LocalFileStatus(source: source, item: item),
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
  const _DetailHero({required this.source, required this.item});
  final MediaSource source;
  final IndexedMedia item;
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
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                    ),
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
                  const SizedBox(height: 14),
                  Text(
                    item.overview ?? '暂无简介。',
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.secondary),
                  ),
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
  });
  final IndexedSeason season;
  final bool expanded;
  final VoidCallback onToggle;
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

class _EpisodeRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return TextButton(
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
          SizedBox(
            width: 120,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LocalMediaArtwork(source: source, item: item),
            ),
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
