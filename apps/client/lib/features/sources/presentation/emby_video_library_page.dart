import 'dart:async';

import 'package:flutter/material.dart';
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
    setState(() => _settings = value);
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
    final hasCached =
        ref
            .watch(embyCachedVideosProvider)
            .asData
            ?.value
            .any((e) => e.identity.sourceId == destination.sourceId) ??
        false;
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
          CustomScrollView(
            controller: _scroll,
            key: PageStorageKey(destination),
            slivers: [
              inset(
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _search,
                        enabled: settings != null,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '搜索$title',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 17),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  icon: const Icon(Icons.close, size: 15),
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
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: palette.border),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 180),
                            _commitSearch,
                          );
                        },
                        onSubmitted: (_) => _commitSearch(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              await ref
                                  .read(sourceScansProvider.notifier)
                                  .scan(destination.sourceId);
                            },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('扫描'),
                    ),
                    TextButton.icon(
                      onPressed: _batchBusy
                          ? null
                          : () => setState(() {
                              _selectionMode = !_selectionMode;
                              if (!_selectionMode) _selected.clear();
                            }),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(_selectionMode ? '完成' : '选择'),
                    ),
                    IconButton(
                      tooltip: '管理媒体源',
                      onPressed: () => context.go('/sources'),
                      icon: const Icon(Icons.settings_outlined, size: 18),
                    ),
                  ],
                ),
              ),
              if (data != null && settings != null)
                inset(
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 3,
                        runSpacing: 4,
                        children: [
                          for (final filter in LibraryWatchFilter.values)
                            _capsule(
                              filter.label,
                              settings.filter == filter,
                              () => _change(settings.copyWith(filter: filter)),
                              palette,
                            ),
                        ],
                      ),
                      if (hasCached || settings.cachedOnly)
                        _capsule(
                          '已缓存',
                          settings.cachedOnly,
                          () => _change(
                            settings.copyWith(cachedOnly: !settings.cachedOnly),
                            persist: false,
                          ),
                          palette,
                        ),
                      if (genres.isNotEmpty)
                        _menu(
                          settings.genre.isEmpty ? '全部类型' : settings.genre,
                          <String>['', ...genres],
                          (value) => value.isEmpty ? '全部类型' : value,
                          (value) => _change(settings.copyWith(genre: value)),
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
                inset(TextButton(onPressed: _load, child: Text('$_error 重试')))
              else if (snapshot.hasError)
                inset(
                  TextButton(
                    onPressed: () => ref.invalidate(
                      embyVideoSnapshotProvider(destination.sourceId),
                    ),
                    child: Text('${sourceErrorMessage(snapshot.error!)} 重试'),
                  ),
                )
              else if ((snapshot.isLoading && data == null) ||
                  settings == null ||
                  results == null)
                inset(const Text('正在读取媒体库…'))
              else if (destination.libraryId != null && library == null)
                inset(const Text('此媒体库已移除或未在同步范围内。'))
              else
                ...results.when(
                  skipLoadingOnReload: true,
                  loading: () => [inset(const Text('正在整理媒体…'))],
                  error: (error, _) => [
                    inset(
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(embyVideoResultsProvider),
                        child: Text('${sourceErrorMessage(error)} 重试'),
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
                        Text(
                          settings.search.isNotEmpty
                              ? '没有匹配的内容'
                              : data.source.lastScan == null
                              ? _browseLoading
                                    ? '正在读取服务端视频…'
                                    : '暂无已载入的视频'
                              : '暂无${settings.filter == LibraryWatchFilter.all ? title : settings.filter.label}',
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
                                  key: ValueKey(entries[index].item.identity),
                                  item: entries[index].item,
                                  child: LocalMediaCard(
                                    source: data.source,
                                    item: entries[index].item,
                                    selectionMode: _selectionMode,
                                    selected: _selected.contains(
                                      entries[index].item.identity,
                                    ),
                                    onOpen: () {
                                      final id = entries[index].item.identity;
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
}
