import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../domain/media_source.dart';
import 'emby_library_selection_bar.dart';
import 'emby_video_context_menu.dart';
import '../application/emby_library_providers.dart';
import '../application/source_providers.dart';
import '../application/emby_providers.dart';
import '../domain/emby_library.dart';
import '../data/emby_browse_repository.dart';
import '../data/artwork_image_pipeline.dart';
import 'emby_detail_extras.dart';
import 'local_media_artwork.dart';

class EmbyVideoLibraryPage extends ConsumerStatefulWidget {
  const EmbyVideoLibraryPage({required this.destination, super.key});
  final EmbyVideoDestination destination;
  @override
  ConsumerState<EmbyVideoLibraryPage> createState() =>
      _EmbyVideoLibraryPageState();
}

class _EmbyVideoLibraryPageState extends ConsumerState<EmbyVideoLibraryPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  VideoLibrarySettings? _settings;
  Timer? _debounce;
  Future<void> _saving = Future.value();
  int _generation = 0;
  String? _error;
  bool _selectionMode = false;
  bool _batchBusy = false;
  bool _suppressPosterHover = false;
  double _contentOpacity = 1;
  int _contentBreath = 0;
  final _selected = <MediaIdentity>{};
  Object? _warmWindow;
  Object? _controlsSnapshot;
  EmbyVideoDestination? _controlsDestination;
  List<String> _genres = const [];
  List<VideoLibrarySort> _sorts = const [];

  EmbyBrowseCursor? _browse;
  ScanCancellation? _browseToken;
  bool _browseLoading = false;
  String? _browseError;

  Future<void> _prepareBrowse(int generation) async {
    final token = ScanCancellation();
    _browseToken?.cancel();
    _browseToken = token;
    try {
      final source = await ref
          .read(sourceRepositoryProvider)
          .source(widget.destination.sourceId);
      if (!mounted || generation != _generation || source.lastScan != null) {
        return;
      }
      final cursor = await ref
          .read(embyBrowseRepositoryProvider)
          .open(
            source.id,
            libraryId: widget.destination.libraryId,
            cancellation: token,
          );
      if (!mounted || generation != _generation) return;
      _browse = cursor;
      await _loadNext();
    } on ScanCancelled {
      // Navigation cancels only foreground browsing, never the background sync.
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _browseError = sourceErrorMessage(error));
      }
    }
  }

  void _nearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
      unawaited(_loadNext());
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final suppress = switch (notification) {
      ScrollStartNotification() => true,
      ScrollEndNotification() => false,
      UserScrollNotification(direction: ScrollDirection.idle) => false,
      _ => _suppressPosterHover,
    };
    if (suppress != _suppressPosterHover) {
      setState(() => _suppressPosterHover = suppress);
    }
    return false;
  }

  Future<void> _loadNext() async {
    final cursor = _browse;
    if (_browseLoading || cursor == null || !cursor.hasMore) return;
    final current = ref
        .read(embyVideoSnapshotProvider(widget.destination.sourceId))
        .value;
    if (current?.source.lastScan != null) return;
    final generation = _generation;
    setState(() {
      _browseLoading = true;
      _browseError = null;
    });
    try {
      await cursor.next();
    } on ScanCancelled {
      // Disposed or superseded page.
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _browseError = sourceErrorMessage(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _browseLoading = false);
      }
    }
  }

  void _prewarm(
    List<VideoLibraryEntry> entries,
    int index,
    int columns,
    MediaSource source,
    ({int width, int height}) target,
  ) {
    if (index % (columns * 2) != 0) return;
    final revision = source.lastScan?.millisecondsSinceEpoch ?? 0;
    final stamp = (
      widget.destination,
      _settings,
      index,
      columns,
      revision,
      target,
    );
    if (_warmWindow == stamp) return;
    _warmWindow = stamp;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || _warmWindow != stamp) return;
      final cache = ref.read(embyCacheProvider);
      final pipeline = ref.read(embyImagePipelineProvider);
      unawaited(
        pipeline.prewarm([
          for (final entry in entries.skip(index).take(columns * 2))
            if (entry.item.posterPath case final String path)
              (
                key: (
                  sourceId: source.id,
                  itemId: path,
                  backdrop: false,
                  index: 0,
                  width: target.width,
                  height: target.height,
                  revision: revision,
                ),
                bytes: () => cache.artwork(source.id, path, revision: revision),
              ),
        ]),
      );
    });
  }

  Future<void> _batch(Future<String> Function(List<MediaIdentity>) work) async {
    if (_batchBusy || _selected.isEmpty) return;
    final ids = _selected.toList();
    final generation = _generation;
    setState(() => _batchBusy = true);
    try {
      final message = await work(ids);
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(sourceErrorMessage(error))));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _mark(bool watched, {bool clear = false}) {
    final library = ref.read(embyLibraryRepositoryProvider);
    final connections = ref.read(embyConnectionProvider);
    return _batch((ids) async {
      await prepareEmbySeries(ref, ids);
      final targets = await library.targets(ids, descendants: true);
      final failed = await connections.markPlayed(
        targets.map((i) => i.identity),
        watched,
        clearHistory: clear,
      );
      return failed > 0
          ? '本机状态已保存，$failed 个条目未能写回服务器，请检查连接后重试。'
          : clear
          ? '播放记录已清除'
          : watched
          ? '已标记为已观看'
          : '已标记为未观看';
    });
  }

  Future<void> _remove() async {
    final ids = _selected.toList();
    final generation = _generation;
    final library = ref.read(embyLibraryRepositoryProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移出所选 ${ids.length} 个条目？'),
        content: const Text('仅从媒体库索引移除，不会删除服务器上的内容；下次同步可能重新入库。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移出媒体库'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || generation != _generation) return;
    await _batch((_) async {
      await library.removeFromLibrary(ids);
      if (mounted && generation == _generation) {
        setState(() {
          _selected.clear();
          _selectionMode = false;
        });
      }
      return '已移出媒体库';
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _load();
  }

  void _load() {
    final generation = ++_generation;
    unawaited(_prepareBrowse(generation));
    final repository = ref.read(embyLibraryRepositoryProvider);
    final destination = widget.destination;
    _saving
        .then((_) => repository.settings(destination))
        .then((value) {
          if (mounted && generation == _generation) {
            setState(() {
              _settings = value;
              _error = null;
            });
          }
        })
        .catchError((Object error) {
          if (mounted && generation == _generation) {
            setState(() => _error = sourceErrorMessage(error));
          }
        });
  }

  @override
  void didUpdateWidget(EmbyVideoLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination) {
      _browseToken?.cancel();
      _browse = null;
      _browseLoading = false;
      _browseError = null;
      _debounce?.cancel();
      _search.clear();
      _selected.clear();
      _selectionMode = false;
      _batchBusy = false;
      _contentOpacity = 1;
      _contentBreath++;
      _settings = null;
      _error = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _load();
    }
  }

  @override
  void dispose() {
    _browseToken?.cancel();
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VideoLibrarySettings value, {bool persist = true}) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    final breath = ++_contentBreath;
    setState(() {
      _settings = value;
      _contentOpacity = animate ? .34 : 1;
    });
    if (animate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && breath == _contentBreath) {
          setState(() => _contentOpacity = 1);
        }
      });
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (!persist) return;
    final id = widget.destination;
    final repository = ref.read(embyLibraryRepositoryProvider);
    // Persist changes in selection order, even when the user switches routes
    // before an earlier SQLite write has completed.
    _saving = _saving
        .then((_) => repository.saveSettings(id, value))
        .catchError((Object _) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('浏览设置保存失败，请重试。')));
          }
        });
  }

  void _commitSearch() {
    _debounce?.cancel();
    if (_settings != null) {
      _change(_settings!.copyWith(search: _search.text.trim()), persist: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destination = widget.destination;
    final snapshot = ref.watch(embyVideoSnapshotProvider(destination.sourceId));
    final data = snapshot.value;
    final settings = _settings;
    if (data != null && _selected.isNotEmpty) {
      if (_selected.any((id) => data.entryFor(id) == null)) {
        final generation = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) {
            setState(
              () => _selected.removeWhere((id) => data.entryFor(id) == null),
            );
          }
        });
      }
    }
    final cachedVideos =
        ref.watch(embyCachedVideosProvider).asData?.value ?? const [];
    final cachedIds = cachedVideos
        .where((entry) => entry.identity.sourceId == destination.sourceId)
        .map((entry) => entry.identity)
        .toSet();
    final hasCached = cachedIds.isNotEmpty;
    final library = data?.libraries
        .where((v) => v.id == destination.libraryId)
        .firstOrNull;
    final title = destination.libraryId != null
        ? (library?.name ?? '远程分类')
        : destination.section.label;
    if (!identical(_controlsSnapshot, data) ||
        _controlsDestination != destination) {
      _controlsSnapshot = data;
      _controlsDestination = destination;
      final scoped = data?.scope(destination) ?? [];
      _genres =
          scoped
              .expand((e) => e.item.remote?.genres ?? <String>[])
              .where((g) => g.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort(libraryTitleCompare);
      _sorts = VideoLibrarySort.values
          .where(
            (mode) => switch (mode) {
              VideoLibrarySort.runtime => scoped.any(
                (e) => (e.item.remote?.durationMs ?? 0) > 0,
              ),
              VideoLibrarySort.score => scoped.any(
                (e) => e.item.remote?.rating != null,
              ),
              VideoLibrarySort.rating => scoped.any(
                (e) => e.userRating != null,
              ),
              _ => true,
            },
          )
          .toList();
    }
    final genres = _genres;
    final sorts = _sorts;
    if (data != null && settings != null && !sorts.contains(settings.sort)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_settings, settings)) {
          _change(
            settings.copyWith(
              sort: VideoLibrarySort.recentlyUpdated,
              reverse: false,
            ),
          );
        }
      });
    }
    final results = settings == null
        ? null
        : ref.watch(
            embyVideoResultsProvider((
              destination: destination,
              settings: settings,
            )),
          );
    final scan =
        ref.watch(sourceScansProvider)[destination.sourceId] ??
        const SourceScanState();
    final busy = scan.busy;
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    SliverPadding inset(Widget child, {double bottom = 16}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(32, 16, 32, bottom),
      sliver: SliverToBoxAdapter(child: child),
    );
    return ColoredBox(
      color: palette.page,
      child: Stack(
        children: [
          AnimatedOpacity(
            key: const ValueKey('emby-library-content-breath'),
            opacity: _contentOpacity,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: CustomScrollView(
                controller: _scroll,
                key: PageStorageKey(destination),
                slivers: [
                  inset(
                    _libraryHeader(
                      context,
                      title: title,
                      settingsReady: settings != null,
                      busy: busy,
                      palette: palette,
                      sourceId: destination.sourceId,
                    ),
                  ),
                  if (data != null && settings != null)
                    inset(
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.card,
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: palette.border, width: .8),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 2, right: 2),
                              child: Icon(
                                Icons.filter_alt_outlined,
                                size: 17,
                                color: palette.secondary,
                              ),
                            ),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                for (final filter in LibraryWatchFilter.values)
                                  _capsule(
                                    filter.label,
                                    settings.filter == filter,
                                    () => _change(
                                      settings.copyWith(filter: filter),
                                    ),
                                    palette,
                                  ),
                              ],
                            ),
                            if (hasCached || settings.cachedOnly)
                              _capsule(
                                '已缓存',
                                settings.cachedOnly,
                                () => _change(
                                  settings.copyWith(
                                    cachedOnly: !settings.cachedOnly,
                                  ),
                                  persist: false,
                                ),
                                palette,
                              ),
                            if (genres.isNotEmpty)
                              _menu(
                                settings.genre.isEmpty
                                    ? '全部类型'
                                    : settings.genre,
                                <String>['', ...genres],
                                (value) => value.isEmpty ? '全部类型' : value,
                                (value) =>
                                    _change(settings.copyWith(genre: value)),
                                palette,
                              ),
                            _menu(
                              '${settings.sort.label} · ${settings.reverse ? '倒序' : '正序'}',
                              sorts,
                              (value) => value.label,
                              (mode) => _change(
                                settings.copyWith(
                                  sort: mode,
                                  reverse: mode == settings.sort
                                      ? !settings.reverse
                                      : false,
                                ),
                              ),
                              palette,
                            ),
                          ],
                        ),
                      ),
                      bottom: 8,
                    ),
                  if (busy || scan.message != null)
                    inset(
                      Text(
                        busy ? '正在同步服务端媒体库…' : scan.message!,
                        style: TextStyle(color: palette.secondary),
                      ),
                      bottom: 8,
                    ),
                  if (_error != null)
                    inset(
                      _libraryStatus(
                        palette,
                        icon: Icons.cloud_off_rounded,
                        title: _error!,
                        message: '媒体库状态未能刷新，现有本地内容不会被删除。',
                        actionLabel: '重试',
                        onAction: _load,
                      ),
                    )
                  else if (snapshot.hasError)
                    inset(
                      _libraryStatus(
                        palette,
                        icon: Icons.cloud_off_rounded,
                        title: sourceErrorMessage(snapshot.error!),
                        message: '无法读取这个 Emby 媒体库，请检查连接后重试。',
                        actionLabel: '重试',
                        onAction: () => ref.invalidate(
                          embyVideoSnapshotProvider(destination.sourceId),
                        ),
                      ),
                    )
                  else if ((snapshot.isLoading && data == null) ||
                      settings == null ||
                      results == null)
                    inset(
                      _libraryStatus(
                        palette,
                        icon: Icons.video_library_outlined,
                        title: '正在读取媒体库…',
                        message: '正在准备筛选条件和已同步的视频内容。',
                        loading: true,
                      ),
                    )
                  else if (destination.libraryId != null && library == null)
                    inset(
                      _libraryStatus(
                        palette,
                        icon: Icons.folder_off_outlined,
                        title: '此媒体库已移除或未在同步范围内。',
                        message: '可以返回媒体源管理，重新选择需要同步的 Emby 媒体库。',
                      ),
                    )
                  else
                    ...results.when(
                      skipLoadingOnReload: true,
                      loading: () => [
                        inset(
                          _libraryStatus(
                            palette,
                            icon: Icons.auto_awesome_motion_outlined,
                            title: '正在整理媒体…',
                            message: '正在应用观看状态、类型和排序条件。',
                            loading: true,
                          ),
                        ),
                      ],
                      error: (error, _) => [
                        inset(
                          _libraryStatus(
                            palette,
                            icon: Icons.error_outline_rounded,
                            title: sourceErrorMessage(error),
                            message: '筛选结果生成失败，媒体索引本身仍然保留。',
                            actionLabel: '重试',
                            onAction: () =>
                                ref.invalidate(embyVideoResultsProvider),
                          ),
                        ),
                      ],
                      data: (entries) => [
                        inset(
                          Text(
                            data!.source.lastScan == null
                                ? '已载入 ${entries.length} 项 · 同步尚未完成，筛选仅包含已载入内容'
                                : '共 ${entries.length} 项',
                            style: TextStyle(
                              color: palette.secondary,
                              fontSize: 12,
                            ),
                          ),
                          bottom: 8,
                        ),
                        if (entries.isEmpty)
                          inset(
                            _libraryStatus(
                              palette,
                              icon: settings.search.isNotEmpty
                                  ? Icons.search_off_rounded
                                  : Icons.movie_creation_outlined,
                              title: settings.search.isNotEmpty
                                  ? '没有匹配的内容'
                                  : data.source.lastScan == null
                                  ? _browseLoading
                                        ? '正在读取服务端视频…'
                                        : '暂无已载入的视频'
                                  : '暂无${settings.filter == LibraryWatchFilter.all ? title : settings.filter.label}',
                              message: settings.search.isNotEmpty
                                  ? '尝试缩短关键词，或清除部分筛选条件。'
                                  : '同步完成后，符合当前条件的视频会显示在这里。',
                              loading: _browseLoading,
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              32,
                              8,
                              32,
                              _selectionMode ? 130 : 28,
                            ),
                            sliver: SliverLayoutBuilder(
                              builder: (context, constraints) {
                                final columns =
                                    ((constraints.crossAxisExtent + 20) / 170)
                                        .floor()
                                        .clamp(1, 100);
                                final target = posterDecodeSize(
                                  (constraints.crossAxisExtent -
                                          20 * (columns - 1)) /
                                      columns,
                                  MediaQuery.devicePixelRatioOf(context),
                                );
                                return SliverGrid.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        crossAxisSpacing: 20,
                                        mainAxisSpacing: 30,
                                        childAspectRatio: 2 / 3,
                                      ),
                                  itemCount: entries.length,
                                  itemBuilder: (context, index) {
                                    _prewarm(
                                      entries,
                                      index,
                                      columns,
                                      data.source,
                                      target,
                                    );
                                    return EmbyVideoContextMenu(
                                      key: ValueKey(
                                        entries[index].item.identity,
                                      ),
                                      item: entries[index].item,
                                      child: LocalMediaCard(
                                        source: data.source,
                                        item: entries[index].item,
                                        progress: entries[index].progress,
                                        rating:
                                            entries[index].item.remote?.rating,
                                        badges: _posterBadges(
                                          entries[index],
                                          cachedIds.contains(
                                            entries[index].item.identity,
                                          ),
                                        ),
                                        selectionMode: _selectionMode,
                                        selected: _selected.contains(
                                          entries[index].item.identity,
                                        ),
                                        suppressHover: _suppressPosterHover,
                                        onOpen: () {
                                          final id =
                                              entries[index].item.identity;
                                          if (_selectionMode) {
                                            setState(() {
                                              if (!_selected.remove(id)) {
                                                _selected.add(id);
                                              }
                                            });
                                          } else {
                                            openIndexedDetail(context, id);
                                          }
                                        },
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  if (data?.source.lastScan == null &&
                      (_browse?.hasMore == true || _browseError != null))
                    inset(
                      TextButton(
                        onPressed: _browseLoading
                            ? null
                            : () {
                                if (_browse == null) {
                                  unawaited(_prepareBrowse(_generation));
                                } else {
                                  unawaited(_loadNext());
                                }
                              },
                        child: Text(
                          _browseLoading
                              ? '正在加载更多视频…'
                              : _browseError == null
                              ? '加载更多'
                              : '$_browseError 重试',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedPositioned(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            right: 22,
            bottom: _selectionMode ? 94 : 18,
            child: _scrollToTopButton(palette),
          ),
          if (_selectionMode)
            Positioned(
              left: 32,
              right: 32,
              bottom: 16,
              child: EmbyLibrarySelectionBar(
                count: _selected.length,
                allSelected:
                    results?.asData?.value.isNotEmpty == true &&
                    results!.asData!.value.every(
                      (e) => _selected.contains(e.item.identity),
                    ),
                busy: _batchBusy,
                onSelectAll: () => setState(() {
                  final visible =
                      results?.asData?.value
                          .map((e) => e.item.identity)
                          .toSet() ??
                      <MediaIdentity>{};
                  if (visible.isNotEmpty && visible.every(_selected.contains)) {
                    _selected.removeAll(visible);
                  } else {
                    _selected.addAll(visible);
                  }
                }),
                onWatched: _mark,
                onWatchlist: () {
                  final library = ref.read(embyLibraryRepositoryProvider);
                  _batch((ids) async {
                    await library.setWatchlistMany(ids, true);
                    return '已加入想看';
                  });
                },
                onRating: (rating) {
                  final library = ref.read(embyLibraryRepositoryProvider);
                  _batch((ids) async {
                    await library.setRating(ids, rating);
                    return rating == null ? '已清除评级' : '评级已更新';
                  });
                },
                onClearHistory: () => _mark(false, clear: true),
                onRemove: _remove,
              ),
            ),
        ],
      ),
    );
  }

  Widget _scrollToTopButton(SourceSheetPalette palette) => Material(
    key: const ValueKey('emby-library-scroll-to-top'),
    color: palette.card.withValues(alpha: .94),
    elevation: 0,
    shadowColor: Colors.black.withValues(alpha: .18),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
      side: BorderSide(color: palette.border, width: .8),
    ),
    clipBehavior: Clip.antiAlias,
    child: IconButton(
      tooltip: '返回顶部',
      onPressed: () {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      },
      icon: Icon(Icons.arrow_upward_rounded, size: 18, color: palette.menuText),
      constraints: const BoxConstraints.tightFor(width: 38, height: 38),
      padding: EdgeInsets.zero,
      splashRadius: 19,
    ),
  );

  Widget _libraryHeader(
    BuildContext context, {
    required String title,
    required bool settingsReady,
    required bool busy,
    required SourceSheetPalette palette,
    required String sourceId,
  }) {
    final search = TextField(
      controller: _search,
      enabled: settingsReady,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: '搜索$title',
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        prefixIconColor: palette.secondary.withValues(alpha: .9),
        suffixIconColor: palette.secondary.withValues(alpha: .9),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _search.clear();
                  _selected.clear();
                  _selectionMode = false;
                  _batchBusy = false;
                  _commitSearch();
                },
              ),
        filled: true,
        fillColor: palette.control,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
      onChanged: (_) {
        setState(() {});
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 180), _commitSearch);
      },
      onSubmitted: (_) => _commitSearch(),
    );
    final scan = OutlinedButton.icon(
      onPressed: busy
          ? null
          : () async {
              await ref.read(sourceScansProvider.notifier).scan(sourceId);
            },
      icon: busy
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded, size: 17),
      label: Text(busy ? '同步中' : '扫描'),
    );
    final selection = OutlinedButton.icon(
      onPressed: _batchBusy
          ? null
          : () => setState(() {
              _selectionMode = !_selectionMode;
              if (!_selectionMode) _selected.clear();
            }),
      icon: Icon(
        _selectionMode
            ? Icons.check_circle_rounded
            : Icons.check_circle_outline_rounded,
        size: 17,
      ),
      label: Text(_selectionMode ? '完成' : '选择'),
    );
    final manage = IconButton.outlined(
      tooltip: '管理媒体源',
      onPressed: () => context.go('/sources'),
      style: IconButton.styleFrom(
        foregroundColor: palette.secondary,
        side: BorderSide(color: palette.border),
      ),
      icon: const Icon(Icons.tune_rounded, size: 18),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border, width: .8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? .18
                  : .055,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 30,
                  height: 1.08,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.45,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '浏览与管理 Emby 视频内容',
                style: TextStyle(
                  color: palette.secondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
          if (constraints.maxWidth >= 820) {
            return Row(
              children: [
                Expanded(child: titleBlock),
                SizedBox(width: 280, child: search),
                const SizedBox(width: 10),
                scan,
                const SizedBox(width: 8),
                selection,
                const SizedBox(width: 8),
                manage,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 12),
                  manage,
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth.clamp(220, 360),
                    child: search,
                  ),
                  scan,
                  selection,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _libraryStatus(
    SourceSheetPalette palette, {
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool loading = false,
  }) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 190),
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: palette.border, width: .8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: palette.selectedTint.withValues(alpha: .10),
                shape: BoxShape.circle,
              ),
            ),
            Icon(icon, size: 26, color: palette.selectedTint),
            if (loading)
              SizedBox.square(
                dimension: 54,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.selectedTint.withValues(alpha: .72),
                  backgroundColor: palette.border,
                ),
              ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.secondary,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(actionLabel),
          ),
        ],
      ],
    ),
  );

  Widget _capsule(
    String title,
    bool selected,
    VoidCallback action,
    SourceSheetPalette palette,
  ) => Material(
    color: selected ? palette.activePill : palette.control,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? palette.activePillText : palette.idlePillText,
          ),
        ),
      ),
    ),
  );
  Widget _menu<T>(
    String title,
    List<T> items,
    String Function(T) label,
    void Function(T) select,
    SourceSheetPalette palette,
  ) => PopupMenuButton<T>(
    tooltip: title,
    onSelected: select,
    itemBuilder: (_) => items
        .map((v) => PopupMenuItem(value: v, child: Text(label(v))))
        .toList(),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 12, color: palette.menuText),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 13),
          ],
        ),
      ),
    ),
  );

  List<String> _posterBadges(VideoLibraryEntry entry, bool cached) {
    final item = entry.item;
    final remote = item.remote;
    return [
      if (cached) '已缓存',
      if (entry.watchlist) '想看',
      if (remote?.favorite == true) '喜欢',
      if (item.type != 'music')
        entry.record.watched || remote?.watched == true ? '已看' : '未看',
      if (item.year != null) '${item.year}',
      ?_resolutionLabel(remote?.resolution),
    ];
  }

  String? _resolutionLabel(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.contains('8k')) return '8K';
    if (normalized.contains('4k')) return '4K';
    if (normalized.contains('2160')) return '4K';
    if (normalized.contains('2k') || normalized.contains('1440')) return '2K';
    if (normalized.contains('1080')) return '1080P';
    if (normalized.contains('720')) return '720P';
    if (normalized.contains('480')) return '480P';
    return value!.trim().toUpperCase();
  }
}
