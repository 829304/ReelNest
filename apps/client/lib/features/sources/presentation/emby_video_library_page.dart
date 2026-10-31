import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_menu_control.dart';
import '../../../ui/widgets/app_confirmation_dialog.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/scroll_hover_scope.dart';
import '../../../ui/widgets/video_library_page_header.dart';
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
  bool _browsePreparing = false;
  bool _browseLoading = false;
  String? _browseError;

  Future<void> _prepareBrowse(int generation) async {
    final token = ScanCancellation();
    _browseToken?.cancel();
    _browseToken = token;
    if (mounted && generation == _generation) {
      setState(() {
        _browsePreparing = true;
        _browseError = null;
      });
    }
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
      setState(() {
        _browse = cursor;
        _browsePreparing = false;
      });
      await _loadNext();
    } on ScanCancelled {
      // Navigation cancels only foreground browsing, never the background sync.
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _browsePreparing = false;
          _browseError = sourceErrorMessage(error);
        });
      }
    } finally {
      if (mounted && generation == _generation && _browsePreparing) {
        setState(() => _browsePreparing = false);
      }
    }
  }

  void _nearEnd() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) {
      unawaited(_loadNext());
    }
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
        showAppToast(context, message, kind: AppFeedbackKind.success);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        showAppToast(
          context,
          sourceErrorMessage(error),
          kind: AppFeedbackKind.error,
        );
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
      builder: (context) => AppConfirmationDialog(
        title: '移出所选 ${ids.length} 个条目？',
        message: '仅从媒体库索引移除，不会删除服务器上的内容；下次同步可能重新入库。',
        confirmLabel: '移出媒体库',
        destructive: true,
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
      _browsePreparing = false;
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
            showAppToast(context, '浏览设置保存失败，请重试。', kind: AppFeedbackKind.error);
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
    final source = ref
        .watch(sourcesProvider)
        .value
        ?.where((value) => value.id == destination.sourceId)
        .firstOrNull;
    final brand = source?.kind.label ?? '远程媒体库';
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
    final visibleCount = results?.asData?.value.length ?? 0;
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
            child: ScrollHoverScope(
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
                      visibleCount: visibleCount,
                      partiallyLoaded: data?.source.lastScan == null,
                    ),
                  ),
                  if (data != null && settings != null)
                    inset(
                      _LibraryControlBar(
                        key: const ValueKey('emby-library-control-bar'),
                        palette: palette,
                        watchFilters: [
                          for (final filter in LibraryWatchFilter.values)
                            _capsule(
                              filter.label,
                              settings.filter == filter,
                              () => _change(settings.copyWith(filter: filter)),
                              palette,
                              key: ValueKey(
                                'emby-library-filter-${filter.name}',
                              ),
                            ),
                        ],
                        trailing: [
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
                              key: const ValueKey('emby-library-filter-cached'),
                            ),
                          if (genres.isNotEmpty)
                            _menu(
                              settings.genre.isEmpty ? '全部类型' : settings.genre,
                              settings.genre,
                              <String>['', ...genres],
                              (value) => value.isEmpty ? '全部类型' : value,
                              (value) =>
                                  _change(settings.copyWith(genre: value)),
                              key: const ValueKey('emby-library-genre-menu'),
                            ),
                          _menu(
                            '${settings.sort.label} · ${settings.reverse ? '倒序' : '正序'}',
                            settings.sort,
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
                            key: const ValueKey('emby-library-sort-menu'),
                          ),
                        ],
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
                        message: '无法读取这个 $brand 媒体库，请检查连接后重试。',
                        actionLabel: '重试',
                        onAction: () => ref.invalidate(
                          embyVideoContentProvider(destination.sourceId),
                        ),
                      ),
                    )
                  else if ((snapshot.isLoading && data == null) ||
                      settings == null ||
                      results == null)
                    inset(
                      _LibraryLoadingView(
                        key: const ValueKey('emby-library-loading'),
                        palette: palette,
                        icon: Icons.video_library_outlined,
                        title: '正在载入$title',
                      ),
                    )
                  else if (destination.libraryId != null && library == null)
                    inset(
                      _libraryStatus(
                        palette,
                        icon: Icons.folder_off_outlined,
                        title: '此媒体库已移除或未在同步范围内。',
                        message: '可以返回媒体源管理，重新选择需要同步的 $brand 媒体库。',
                      ),
                    )
                  else
                    ...results.when(
                      skipLoadingOnReload: true,
                      loading: () => [
                        inset(
                          _LibraryLoadingView(
                            key: const ValueKey('emby-library-loading'),
                            palette: palette,
                            icon: settings.search.isNotEmpty
                                ? Icons.search_rounded
                                : Icons.video_library_outlined,
                            title: settings.search.isNotEmpty
                                ? '正在搜索$title'
                                : '正在载入$title',
                            subtitle: settings.search.isNotEmpty
                                ? '正在匹配标题、演职人员、题材、简介和子集标题'
                                : '正在准备当前页面',
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
                        if (entries.isEmpty)
                          inset(
                            _libraryStatus(
                              palette,
                              icon: settings.search.isNotEmpty
                                  ? Icons.search_off_rounded
                                  : Icons.movie_creation_outlined,
                              title: settings.search.isNotEmpty
                                  ? '没有匹配的内容'
                                  : data!.source.lastScan == null
                                  ? _browsePreparing || _browseLoading
                                        ? '正在读取服务端视频…'
                                        : '暂无已载入的视频'
                                  : '暂无${settings.filter == LibraryWatchFilter.all ? title : settings.filter.label}',
                              message: settings.search.isNotEmpty
                                  ? '尝试缩短关键词，或清除部分筛选条件。'
                                  : '同步完成后，符合当前条件的视频会显示在这里。',
                              loading: _browsePreparing || _browseLoading,
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
                                      data!.source,
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
                  if (data?.source.lastScan == null)
                    inset(
                      _BrowseFooter(
                        palette: palette,
                        preparing: _browsePreparing,
                        loading: _browseLoading,
                        hasMore: _browse?.hasMore == true,
                        error: _browseError,
                        onRetry: () {
                          if (_browse == null) {
                            unawaited(_prepareBrowse(_generation));
                          } else {
                            unawaited(_loadNext());
                          }
                        },
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
    required int visibleCount,
    required bool partiallyLoaded,
  }) {
    final search = TextField(
      controller: _search,
      enabled: settingsReady,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: '搜索$title',
        isDense: true,
        prefixIcon: SourceLineIcon(
          SourceGlyph.search,
          size: 17,
          color: palette.secondary.withValues(alpha: .9),
          lineWidth: 1.9,
        ),
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
          : SourceLineIcon(
              SourceGlyph.refresh,
              size: 17,
              color: palette.menuText,
              lineWidth: 1.9,
            ),
      label: Text(busy ? '同步中' : '扫描'),
    );
    final selection = OutlinedButton.icon(
      onPressed: _batchBusy
          ? null
          : () => setState(() {
              _selectionMode = !_selectionMode;
              if (!_selectionMode) _selected.clear();
            }),
      icon: SourceLineIcon(
        SourceGlyph.checkCircle,
        size: 17,
        color: palette.menuText,
        lineWidth: _selectionMode ? 2.3 : 1.9,
      ),
      label: Text(_selectionMode ? '完成' : '选择'),
    );
    return VideoLibraryPageHeader(
      title: title,
      subtitle: partiallyLoaded
          ? '浏览、筛选和管理已载入内容 · $visibleCount 项'
          : '浏览、筛选和管理当前内容 · $visibleCount 项',
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(width: 226, child: search),
          const SizedBox(width: 10),
          scan,
          const SizedBox(width: 10),
          selection,
        ],
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
    SourceSheetPalette palette, {
    Key? key,
  }) => _LibraryFilterChip(
    key: key,
    title: title,
    selected: selected,
    onPressed: action,
    palette: palette,
  );
  Widget _menu<T>(
    String title,
    T value,
    List<T> items,
    String Function(T) label,
    void Function(T) select, {
    Key? key,
  }) => AppMenuControl<T>(
    key: key,
    value: value,
    label: title,
    values: items,
    itemLabel: label,
    onSelected: select,
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

class _BrowseFooter extends StatelessWidget {
  const _BrowseFooter({
    required this.palette,
    required this.preparing,
    required this.loading,
    required this.hasMore,
    required this.error,
    required this.onRetry,
  });

  final SourceSheetPalette palette;
  final bool preparing;
  final bool loading;
  final bool hasMore;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final busy = preparing || loading;
    final content = busy
        ? Row(
            key: const ValueKey('emby-browse-footer-loading'),
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.selectedTint,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                preparing ? '正在读取服务端视频…' : '正在加载更多视频…',
                style: TextStyle(color: palette.secondary, fontSize: 12.5),
              ),
            ],
          )
        : error != null
        ? TextButton.icon(
            key: const ValueKey('emby-browse-footer-error'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text('$error 重试', maxLines: 1),
          )
        : hasMore
        ? TextButton(
            key: const ValueKey('emby-browse-footer-more'),
            onPressed: onRetry,
            child: const Text('加载更多'),
          )
        : Text(
            '已载入当前可用内容',
            key: const ValueKey('emby-browse-footer-complete'),
            style: TextStyle(color: palette.secondary, fontSize: 12.5),
          );
    return Semantics(
      liveRegion: true,
      child: SizedBox(
        key: const ValueKey('emby-browse-footer'),
        height: 46,
        child: Center(
          child: AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _LibraryLoadingView extends StatelessWidget {
  const _LibraryLoadingView({
    required this.palette,
    required this.icon,
    required this.title,
    this.subtitle = '正在准备当前页面',
    super.key,
  });

  final SourceSheetPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, shimmer, _) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 320),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border, width: .8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 38,
                  child: Icon(icon, size: 27, color: palette.selectedTint),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.secondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < 4; index++) ...[
              _LibrarySkeletonRow(
                palette: palette,
                shimmer: shimmer,
                widthFactor: .58 + index * .06,
              ),
              if (index != 3) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _LibrarySkeletonRow extends StatelessWidget {
  const _LibrarySkeletonRow({
    required this.palette,
    required this.shimmer,
    required this.widthFactor,
  });

  final SourceSheetPalette palette;
  final double shimmer;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border, width: .8),
    ),
    child: Row(
      children: [
        _block(width: 52, height: 52, radius: 8),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: widthFactor.clamp(.4, .84),
                child: _block(height: 10, radius: 4),
              ),
              const SizedBox(height: 7),
              FractionallySizedBox(
                widthFactor: (widthFactor - .18).clamp(.28, .66),
                child: _block(height: 8, radius: 4),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _block({
    double? width,
    required double height,
    required double radius,
  }) {
    final position = -2 + shimmer * 4;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(position - .65, 0),
          end: Alignment(position + .65, 0),
          colors: [
            palette.control,
            Colors.white.withValues(alpha: palette.dark ? .10 : .58),
            palette.control,
          ],
        ),
      ),
    );
  }
}

class _LibraryControlBar extends StatelessWidget {
  const _LibraryControlBar({
    required this.palette,
    required this.watchFilters,
    required this.trailing,
    super.key,
  });

  final SourceSheetPalette palette;
  final List<Widget> watchFilters;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final filterGroup = Container(
      key: const ValueKey('emby-library-watch-filters'),
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: .8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            watchFilters
                .expand((control) => [control, const SizedBox(width: 7)])
                .toList()
              ..removeLast(),
      ),
    );
    final trailingGroup = Wrap(
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: trailing,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: .8),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: palette.dark ? .13 : .035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                filterGroup,
                const SizedBox(width: 18),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailingGroup,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                key: const ValueKey('emby-library-filter-scroll'),
                scrollDirection: Axis.horizontal,
                child: filterGroup,
              ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(height: 9),
                Align(alignment: Alignment.centerRight, child: trailingGroup),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LibraryFilterChip extends StatefulWidget {
  const _LibraryFilterChip({
    required this.title,
    required this.selected,
    required this.onPressed,
    required this.palette,
    super.key,
  });

  final String title;
  final bool selected;
  final VoidCallback onPressed;
  final SourceSheetPalette palette;

  @override
  State<_LibraryFilterChip> createState() => _LibraryFilterChipState();
}

class _LibraryFilterChipState extends State<_LibraryFilterChip> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final animated = !MediaQuery.disableAnimationsOf(context);
    final highlighted = _hovered || _focused || _pressed;
    final background = widget.selected
        ? palette.activePill
        : highlighted
        ? palette.hoverPill
        : Colors.transparent;
    final border = widget.selected
        ? palette.border
        : _focused
        ? palette.selectedTint.withValues(alpha: .68)
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: AnimatedScale(
        scale: _pressed ? .975 : 1,
        duration: animated ? const Duration(milliseconds: 90) : Duration.zero,
        child: AnimatedContainer(
          duration: animated
              ? const Duration(milliseconds: 150)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: .8),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: palette.shadow.withValues(
                        alpha: palette.dark ? .16 : .055,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              borderRadius: BorderRadius.circular(12),
              splashColor: palette.selectedTint.withValues(alpha: .08),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  height: 28,
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: animated
                          ? const Duration(milliseconds: 150)
                          : Duration.zero,
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: widget.selected
                            ? palette.activePillText
                            : palette.idlePillText,
                      ),
                      child: Text(widget.title),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
