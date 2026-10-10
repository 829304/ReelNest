import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../application/emby_library_providers.dart';
import '../application/source_providers.dart';
import '../application/emby_providers.dart';
import '../domain/emby_library.dart';
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
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final generation = ++_generation;
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
      _debounce?.cancel();
      _search.clear();
      _settings = null;
      _error = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _load();
    }
  }

  @override
  void dispose() {
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
    final data = snapshot.asData?.value;
    final settings = _settings;
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
    final scoped = data?.scope(destination) ?? [];
    final genres =
        scoped
            .expand((e) => e.item.remote?.genres ?? <String>[])
            .where((g) => g.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort(libraryTitleCompare);
    final sorts = VideoLibrarySort.values
        .where(
          (mode) => switch (mode) {
            VideoLibrarySort.runtime => scoped.any(
              (e) => (e.item.remote?.durationMs ?? 0) > 0,
            ),
            VideoLibrarySort.score => scoped.any(
              (e) => e.item.remote?.rating != null,
            ),
            VideoLibrarySort.rating => scoped.any((e) => e.userRating != null),
            _ => true,
          },
        )
        .toList();
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
      child: CustomScrollView(
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
          else if (snapshot.isLoading || settings == null || results == null)
            inset(const Text('正在读取媒体库…'))
          else if (destination.libraryId != null && library == null)
            inset(const Text('此媒体库已移除或未在同步范围内。'))
          else
            ...results.when(
              loading: () => [inset(const Text('正在整理媒体…'))],
              error: (error, _) => [
                inset(
                  TextButton(
                    onPressed: () => ref.invalidate(embyVideoResultsProvider),
                    child: Text('${sourceErrorMessage(error)} 重试'),
                  ),
                ),
              ],
              data: (entries) => [
                inset(
                  Text(
                    '共 ${entries.length} 项',
                    style: TextStyle(color: palette.secondary, fontSize: 12),
                  ),
                  bottom: 8,
                ),
                if (entries.isEmpty)
                  inset(
                    Text(
                      settings.search.isNotEmpty
                          ? '没有匹配的内容'
                          : data!.source.lastScan == null
                          ? '媒体内容尚未同步。请先同步媒体源。'
                          : '暂无${settings.filter == LibraryWatchFilter.all ? title : settings.filter.label}',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 28),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) => SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              ((constraints.crossAxisExtent + 20) / 170)
                                  .floor()
                                  .clamp(1, 100),
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 30,
                          childAspectRatio: 2 / 3,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, index) => LocalMediaCard(
                          key: ValueKey(entries[index].item.identity),
                          source: data!.source,
                          item: entries[index].item,
                          onOpen: () => openIndexedDetail(
                            context,
                            entries[index].item.identity,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
