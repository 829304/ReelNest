import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/library_state_panel.dart';
import '../../../ui/widgets/scroll_hover_scope.dart';
import '../../../ui/widgets/video_library_page_header.dart';
import '../application/source_providers.dart';
import '../domain/emby_library.dart';
import 'emby_video_library_page.dart';
import 'local_media_artwork.dart';
import 'marker_analysis_menu.dart';
import 'url_video_context_menu.dart';

/// Desktop local/URL library translated from MediaLib's `LibraryView` and
/// `PosterGridList` geometry. Remote sources keep their richer server-specific
/// page, while all cards share focus, hover suppression and scroll rhythm.
class SourceLibraryPage extends ConsumerStatefulWidget {
  const SourceLibraryPage({
    required this.sourceId,
    this.libraryId,
    this.section = EmbyVideoSection.videos,
    super.key,
  });

  final String sourceId;
  final String? libraryId;
  final EmbyVideoSection section;

  @override
  ConsumerState<SourceLibraryPage> createState() => _SourceLibraryPageState();
}

class _SourceLibraryPageState extends ConsumerState<SourceLibraryPage> {
  late final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    // Dependency reloads retain the previous value in AsyncLoading. Keep the
    // same library subtree alive while its source configuration is refreshed.
    final source = sources.value
        ?.where((source) => source.id == widget.sourceId)
        .firstOrNull;
    if (source?.kind.isRemoteVideoSource == true) {
      return EmbyVideoLibraryPage(
        destination: (
          sourceId: widget.sourceId,
          section: widget.section,
          libraryId: widget.libraryId,
        ),
      );
    }

    final firstPage = ref.watch(
      sourceMediaProvider((sourceId: widget.sourceId, offset: 0)),
    );
    final firstData = firstPage.value;
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );

    return ColoredBox(
      color: palette.page,
      child: Stack(
        children: [
          FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: ScrollHoverScope(
              child: CustomScrollView(
                key: PageStorageKey<String>(
                  'source-library-${widget.sourceId}',
                ),
                controller: _scroll,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
                    sliver: SliverToBoxAdapter(
                      child: VideoLibraryPageHeader(
                        title: source?.name ?? '媒体库',
                        subtitle: firstData == null
                            ? '浏览、筛选和管理当前内容'
                            : '浏览、筛选和管理当前内容 · ${firstData.total} 项',
                        actions: OutlinedButton.icon(
                          key: const ValueKey('manage-media-sources'),
                          onPressed: () => context.go('/sources'),
                          icon: const Icon(Icons.tune_rounded, size: 17),
                          label: const Text('管理媒体源'),
                        ),
                      ),
                    ),
                  ),
                  if (sources.hasError && source == null)
                    _status(
                      palette,
                      key: const ValueKey('source-library-source-error'),
                      icon: Icons.folder_off_outlined,
                      title: '无法读取媒体源',
                      message: sourceErrorMessage(sources.error!),
                      actionLabel: '重试',
                      onAction: () => ref.invalidate(sourcesProvider),
                    )
                  else if (!sources.isLoading &&
                      sources.hasValue &&
                      source == null)
                    _status(
                      palette,
                      key: const ValueKey('source-library-removed'),
                      icon: Icons.folder_off_outlined,
                      title: '此媒体源已移除。',
                      message: '可以返回媒体源管理，选择其他来源或重新添加。',
                    )
                  else if (source == null)
                    _loading(palette, '正在载入媒体库')
                  else if (firstData == null && firstPage.hasError)
                    _status(
                      palette,
                      key: const ValueKey('source-library-error'),
                      icon: Icons.error_outline_rounded,
                      title: '无法载入${source.name}',
                      message: sourceErrorMessage(firstPage.error!),
                      actionLabel: '重试',
                      onAction: () => ref.invalidate(
                        sourceMediaProvider((sourceId: source.id, offset: 0)),
                      ),
                    )
                  else if (firstData == null)
                    _loading(palette, '正在载入${source.name}')
                  else if (firstData.total == 0)
                    _status(
                      palette,
                      key: const ValueKey('source-library-empty'),
                      icon: Icons.movie_creation_outlined,
                      title: '暂无${source.name}',
                      message: '没有可显示的媒体。请检查来源或重新扫描。',
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(32, 8, 32, 28),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          // PosterGridList: minimum 150, 20/30 column/row gap.
                          final columns =
                              ((constraints.crossAxisExtent + 20) / 170)
                                  .floor()
                                  .clamp(1, 100);
                          return SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 30,
                                  childAspectRatio: 2 / 3,
                                ),
                            itemCount: firstData.total,
                            itemBuilder: (context, index) =>
                                _LibraryItemAtIndex(
                                  source: source,
                                  index: index,
                                ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(right: 22, bottom: 18, child: _scrollToTopButton(palette)),
        ],
      ),
    );
  }

  Widget _loading(SourceSheetPalette palette, String title) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
    sliver: SliverToBoxAdapter(
      child: LibraryLoadingPanel(
        key: const ValueKey('source-library-loading'),
        palette: palette,
        title: title,
      ),
    ),
  );

  Widget _status(
    SourceSheetPalette palette, {
    required Key key,
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
    sliver: SliverToBoxAdapter(
      child: LibraryStatusPanel(
        key: key,
        palette: palette,
        icon: icon,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    ),
  );

  Widget _scrollToTopButton(SourceSheetPalette palette) => Material(
    key: const ValueKey('source-library-scroll-to-top'),
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
}

class _LibraryItemAtIndex extends ConsumerWidget {
  const _LibraryItemAtIndex({required this.source, required this.index});

  final MediaSource source;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (sourceId: source.id, offset: (index ~/ 60) * 60);
    final pageState = ref.watch(sourceMediaProvider(key));
    // Riverpod retains a successful value while a dependency reloads or a
    // refresh fails. Render it first so a transient page error never replaces
    // already visible posters with sixty retry buttons.
    final page = pageState.value;
    if (page != null) {
      final position = index % 60;
      if (position >= page.items.length) return const SizedBox.shrink();
      return _LibraryMediaCard(source: source, item: page.items[position]);
    }

    final position = index % 60;
    return LibraryPosterPlaceholder(
      key: ValueKey(
        pageState.hasError
            ? position == 0
                  ? 'source-page-error-${key.offset}'
                  : 'source-page-error-placeholder-${key.offset}-$position'
            : 'source-page-loading-${key.offset}-$position',
      ),
      retry: pageState.hasError && position == 0
          ? () => ref.invalidate(sourceMediaProvider(key))
          : null,
      loading: !pageState.hasError,
    );
  }
}

class _LibraryMediaCard extends StatelessWidget {
  const _LibraryMediaCard({required this.source, required this.item});

  final MediaSource source;
  final IndexedMedia item;

  @override
  Widget build(BuildContext context) {
    final card = LocalMediaCard(
      key: ValueKey(item.identity),
      source: source,
      item: item,
      onOpen: () => context.pushNamed(
        'local-media-detail',
        pathParameters: {
          'sourceId': source.id,
          // Opaque token keeps slash-containing and Unicode file keys out of
          // URL parsing; source scope is still checked in SQL.
          'mediaKey': base64Url
              .encode(utf8.encode(item.identity.localId))
              .replaceAll('=', ''),
        },
      ),
    );
    return Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: item.type == 'music' ? 1 : 2 / 3,
        child: source.kind == MediaSourceKind.url
            ? UrlVideoContextMenu(item: item, child: card)
            : MarkerAnalysisContextMenu(identity: item.identity, child: card),
      ),
    );
  }
}
