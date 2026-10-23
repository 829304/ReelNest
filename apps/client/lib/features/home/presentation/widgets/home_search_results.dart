import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/media.dart';
import '../../../../ui/theme/source_sheet_palette.dart';
import '../../../sources/application/source_providers.dart';
import '../../../sources/presentation/local_media_artwork.dart';
import '../../application/home_actions.dart';
import '../../application/home_search_providers.dart';
import '../../domain/home_search.dart';
import '../../domain/home_snapshot.dart';
import '../../data/home_repository.dart';

/// GlobalSearchView embeds in the homepage scroll view. Each result is a lazy
/// 40x60 poster row, not another independently scrolling list/grid.
class HomeSearchResults extends ConsumerWidget {
  const HomeSearchResults({required this.query, super.key});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final sources = ref.watch(sidebarSourcesProvider).value ?? [];
    final key = (
      query: query,
      scope: sources
          .where(HomeRepository.accepts)
          .map(homeSearchScope)
          .join('\n'),
    );
    final result = ref.watch(homeSearchProvider(key));
    final state = result.value ?? HomeSearchState(loading: result.isLoading);
    final loading = result.isLoading || state.loading;
    final failed = state.errors.isNotEmpty || result.hasError;
    final title = loading
        ? '正在搜索“$query”'
        : state.count == 0
        ? failed
              ? '搜索未完成“$query”'
              : '未找到“$query”'
        : '搜索“$query”';
    Widget panel(String title, String subtitle, {double radius = 16}) =>
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.staticSurface.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: p.iconChip,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.search, color: p.accent, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: panel(
          title,
          '${state.count == 0 ? '可尝试标题、演员、角色、题材、简介、制作方、年份或剧集名称。' : '已穿透匹配作品资料、演职人员和子集标题，并按媒体类型分组。'}${!loading && state.count > 0 ? ' ${state.count} 个结果' : ''}',
        ),
      ),
      if (state.partial)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _SearchNotice(
              icon: Icons.info_outline_rounded,
              message: 'Emby 显示已载入范围内的搜索结果；完整同步后将补齐。',
            ),
          ),
        ),
      if (state.errors.isNotEmpty || result.hasError)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _SearchNotice(
              icon: Icons.error_outline_rounded,
              message: [
                ...state.errors.values,
                if (result.hasError) '搜索暂时失败，请重试。',
              ].join('\n'),
              actionLabel: '重试',
              onAction: () {
                ref.invalidate(homeSearchSourceProvider);
                ref.invalidate(homeSearchProvider(key));
              },
            ),
          ),
        ),
      if (state.count == 0)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: panel(
              loading
                  ? '正在匹配媒体资料'
                  : failed
                  ? '暂时无法完成搜索'
                  : '无匹配结果',
              loading
                  ? '按电影、剧集等分类匹配，命中后会立即显示。'
                  : failed
                  ? '部分来源搜索失败，重试后再确认结果。'
                  : '支持标题与拼音、演员和角色、题材、简介、电视网、制作公司、年份及具体剧集名称。',
              radius: 22,
            ),
          ),
        ),
    ];
    for (final group in state.groups.entries) {
      slivers.addAll([
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 12),
            child: Row(
              children: [
                Icon(
                  switch (group.key) {
                    HomeSearchGroup.movie => Icons.movie_outlined,
                    HomeSearchGroup.tvShow => Icons.tv,
                    HomeSearchGroup.anime => Icons.auto_awesome,
                    HomeSearchGroup.documentary => Icons.menu_book,
                    HomeSearchGroup.variety => Icons.mic_none,
                    HomeSearchGroup.other => Icons.inbox_outlined,
                  },
                  size: 20,
                  color: p.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.key.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '点击条目查看详情',
                        style: TextStyle(fontSize: 12, color: p.secondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${group.value.length} 项',
                  style: TextStyle(color: p.secondary),
                ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: group.value.length,
          itemBuilder: (_, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SearchRow(
              key: ValueKey(group.value[index].item.identity),
              video: group.value[index],
            ),
          ),
        ),
      ]);
    }
    if (loading && state.count > 0) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: panel('继续穿透其他分类', '已显示先命中的结果，其余来源仍在匹配。'),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(36, 22, 36, 28),
      sliver: SliverMainAxisGroup(slivers: slivers),
    );
  }
}

class _SearchNotice extends StatelessWidget {
  const _SearchNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 9, 10),
      decoration: BoxDecoration(
        color: palette.cleanPanelFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: palette.secondary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchRow extends ConsumerStatefulWidget {
  const _SearchRow({required this.video, super.key});
  final HomeVideo video;
  @override
  ConsumerState<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends ConsumerState<_SearchRow> {
  bool _hover = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final video = widget.video, item = video.item;
    final subtitle = [
      mediaTypes[item.displayType] ?? '其他',
      if (item.year != null) '${item.year}',
      if (item.remote?.genres.isNotEmpty == true)
        item.remote!.genres.join(', '),
      if ((item.remote?.rating ?? 0) > 0)
        '★ ${item.remote!.rating!.toStringAsFixed(1)}',
    ].join(' · ');
    final active =
        (_hover || _focused) &&
        !Scrollable.recommendDeferredLoadingForContext(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          if (_focused != focused) setState(() => _focused = focused);
        },
        child: Semantics(
          label: '${item.title}，$subtitle',
          hint: '打开媒体详情',
          button: true,
          child: AnimatedContainer(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? p.accent.withValues(alpha: .7) : p.border,
              ),
            ),
            child: Material(
              color: active
                  ? p.hoverPill
                  : p.staticSurface.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(11),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('home-search-open-${item.identity}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  // Do not restore the search field's focus on pop: TextField's
                  // ensureVisible would scroll the retained results back to top.
                  FocusManager.instance.primaryFocus?.unfocus();
                  await context.push(homeDetailLocation(video));
                  // Dependency refresh retains prior rows while cached detail
                  // terms reload. invalidate() would collapse the list on pop.
                  if (mounted) {
                    ref
                        .read(sourceRepositoryProvider)
                        .traceChanged(sourceIds: [item.identity.sourceId]);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: SizedBox(
                          width: 40,
                          height: 60,
                          child: LocalMediaArtwork(
                            source: video.source,
                            item: item,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: active ? p.selectedTint : p.secondary,
                      ),
                    ],
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
