import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media.dart';
import '../../../ui/widgets/status_notice.dart';
import '../application/library_providers.dart';
import 'media_card.dart';

class BrowsePage extends ConsumerStatefulWidget {
  const BrowsePage({required this.type, super.key});
  final String type;

  @override
  ConsumerState<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends ConsumerState<BrowsePage> {
  MediaSort _sort = MediaSort.recentlyUpdated;
  bool _list = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(MediaItem item) => context.pushNamed(
    'media-detail',
    pathParameters: {'type': widget.type, 'id': item.id},
    queryParameters: {if (item.isSeries) 'series': '1'},
  );

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(libraryScopeProvider);
    if (scope == null) return const LibraryLoginPrompt();
    if (!mediaTypes.containsKey(widget.type)) {
      return const Center(child: Text('暂不支持此分类。'));
    }
    final key = (
      scope: scope,
      type: widget.type,
      sort: _sort,
      seriesId: null as String?,
      season: null as String?,
    );
    final state = ref.watch(browseProvider(key));
    final controller = ref.read(browseProvider(key).notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 500 ? 20.0 : 32.0;
        final width = constraints.maxWidth - padding * 2;
        // Original PosterGridList: min width 150, horizontal gap 20, row gap 30.
        final minWidth = MediaQuery.textScalerOf(context).scale(150);
        final columns = ((width + 20) / (minWidth + 20))
            .floor()
            .clamp(1, 12)
            .toInt();
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            controller: _scroll,
            key: PageStorageKey('browse:$scope:${widget.type}:${_sort.name}'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 28, padding, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mediaTypes[widget.type]!,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('已加载 ${state.items.length} / ${state.total} 项'),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => context.go('/servers/library'),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('媒体库'),
                          ),
                          DropdownButton<MediaSort>(
                            value: _sort,
                            items: MediaSort.values
                                .map(
                                  (sort) => DropdownMenuItem(
                                    value: sort,
                                    child: Text(sort.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (sort) {
                              if (sort == null || sort == _sort) return;
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                              setState(() => _sort = sort);
                            },
                          ),
                          IconButton(
                            onPressed: () => setState(() => _list = !_list),
                            tooltip: _list ? '海报视图' : '列表视图',
                            icon: Icon(
                              _list ? Icons.grid_view : Icons.view_list,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: state.loading
                                ? null
                                : controller.refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('刷新'),
                          ),
                        ],
                      ),
                      if (state.loading) ...[
                        const SizedBox(height: 16),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('正在读取媒体…'),
                      ],
                      if (state.failure case final failure?) ...[
                        const SizedBox(height: 16),
                        StatusNotice(
                          message: failure.message,
                          onRetry: state.appendFailure
                              ? controller.loadMore
                              : controller.refresh,
                        ),
                      ],
                      if (state.items.isNotEmpty &&
                          (state.loading || state.failure != null)) ...[
                        const SizedBox(height: 8),
                        const Text('保留上次成功读取的条目。'),
                      ],
                      if (!state.loading &&
                          state.failure == null &&
                          state.items.isEmpty) ...[
                        const SizedBox(height: 24),
                        const Text('这个分类还没有媒体。'),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                sliver: _list
                    ? SliverList.builder(
                        itemCount: state.items.length,
                        itemBuilder: (context, index) {
                          final item = state.items[index];
                          return Card(
                            child: ListTile(
                              title: Text(item.title),
                              subtitle: Text(
                                [
                                  if (item.year != null) '${item.year}',
                                  if (item.artist != null) item.artist!,
                                  mediaTypes[item.type] ?? item.type,
                                ].join(' · '),
                              ),
                              leading: Icon(
                                item.isSeries
                                    ? Icons.tv
                                    : Icons.perm_media_outlined,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _open(item),
                            ),
                          );
                        },
                      )
                    : SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 30,
                          childAspectRatio: widget.type == 'music' ? 1 : 2 / 3,
                        ),
                        itemCount: state.items.length,
                        itemBuilder: (context, index) => MediaCard(
                          key: ValueKey(state.items[index].id),
                          item: state.items[index],
                          scope: scope,
                          onOpen: () => _open(state.items[index]),
                        ),
                      ),
              ),
              SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: state.hasMore
                        ? OutlinedButton.icon(
                            onPressed: state.loading || state.loadingMore
                                ? null
                                : controller.loadMore,
                            icon: const Icon(Icons.expand_more),
                            label: Text(state.loadingMore ? '正在加载…' : '加载更多'),
                          )
                        : Text(
                            state.limitReached
                                ? '已达到服务器分页上限。'
                                : state.items.isEmpty
                                ? ''
                                : '已加载全部条目',
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class LibraryLoginPrompt extends StatelessWidget {
  const LibraryLoginPrompt({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('请先连接服务器；若会话已过期，请重新登录。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go('/servers'),
            child: const Text('管理服务器'),
          ),
        ],
      ),
    ),
  );
}
