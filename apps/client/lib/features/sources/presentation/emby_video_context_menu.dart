import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/data/player_preferences_repository.dart';
import '../application/emby_library_providers.dart';
import '../application/emby_providers.dart';
import '../application/source_providers.dart';

import 'emby_cache_actions.dart';
import 'external_playback_actions.dart';
import 'marker_analysis_menu.dart';

/// VideoItemContextMenuItems; server titles never expose local reclassification.
class EmbyVideoContextMenu extends ConsumerStatefulWidget {
  const EmbyVideoContextMenu({
    required this.item,
    required this.child,
    super.key,
  });
  final IndexedMedia item;
  final Widget child;
  @override
  ConsumerState<EmbyVideoContextMenu> createState() =>
      _EmbyVideoContextMenuState();
}

class _EmbyVideoContextMenuState extends ConsumerState<EmbyVideoContextMenu> {
  final _controller = MenuController();
  bool _busy = false;

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (error) {
      if (mounted) {
        showAppToast(
          context,
          sourceErrorMessage(error),
          kind: AppFeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.item.identity;
    final library = ref.watch(embyLibraryRepositoryProvider);
    final connections = ref.watch(embyConnectionProvider);
    final launcher = ref.watch(playbackLauncherProvider);
    final snapshot = ref
        .watch(embyVideoSnapshotProvider(id.sourceId))
        .asData
        ?.value;
    final entry = snapshot?.entryFor(id);
    final item = entry?.item ?? widget.item;
    final children = snapshot?.childrenOf(id) ?? [];
    final threshold = ref.watch(_thresholdProvider).asData?.value ?? .9;
    final anyWatched =
        entry?.watched(threshold) == true ||
        children.any((e) => e.watched(threshold));
    final parent = item.parentId == null
        ? null
        : snapshot?.entryFor((sourceId: id.sourceId, localId: item.parentId!));
    final seriesTrace = entry?.hasTrace != true && parent?.hasTrace == true;
    final hasTrace =
        entry?.hasTrace == true ||
        children.any((e) => e.hasTrace) ||
        seriesTrace;
    Widget action(
      String title,
      Future<void> Function() work, {
      bool selected = false,
      IconData? icon,
      bool requiresEntry = true,
    }) => MenuItemButton(
      onPressed: _busy || (requiresEntry && entry == null)
          ? null
          : () => unawaited(_run(work)),
      leadingIcon: selected
          ? const Icon(Icons.check, size: 16)
          : icon == null
          ? null
          : Icon(icon, size: 16),
      child: Text(title),
    );
    Future<void> watched(bool value, {bool clear = false}) async {
      final target = clear && seriesTrace ? parent!.item.identity : id;
      await prepareEmbySeries(ref, [target]);
      final targets = await library.targets([target], descendants: true);
      final failed = await connections.markPlayed(
        targets.map((i) => i.identity),
        value,
        clearHistory: clear,
      );
      if (context.mounted && failed > 0) {
        showAppToast(
          context,
          '本机状态已保存，$failed 个条目未能写回服务器，请检查连接后重试。',
          kind: AppFeedbackKind.warning,
        );
      }
    }

    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        if (item.parentId == null)
          action('播放', () async {
            var target = id;
            if (item.isSeries) {
              await prepareEmbySeries(ref, [id]);
              final sources = library.sources;
              final seasons = await sources.seasons(id);
              if (seasons.isEmpty) throw const SourceFailure('此媒体没有可播放文件。');
              final episodes = await sources.episodes(
                id,
                seasonNumber: seasons.first.number,
                limit: 1,
              );
              if (episodes.items.isEmpty) {
                throw const SourceFailure('此媒体没有可播放文件。');
              }
              target = episodes.items.first.identity;
            }
            await launcher.open(target);
          }),
        action(
          '外部打开',
          () => openLibraryExternally(ref, item),
          icon: Icons.open_in_new_rounded,
          requiresEntry: false,
        ),
        EmbyCacheActions(item: item, menuOnly: true),
        MarkerAnalysisMenuItem(identity: item.identity),
        const Divider(),
        if (hasTrace)
          action(
            seriesTrace ? '删除本系列播放记录' : '删除播放记录',
            () => watched(false, clear: true),
          ),
        if (children.isNotEmpty) ...[
          action('标记整个系列为已观看', () => watched(true)),
          if (anyWatched) action('清除已观看', () => watched(false)),
        ] else
          action(anyWatched ? '清除已观看' : '标记为已观看', () => watched(!anyWatched)),
        action(
          entry?.watchlist == true ? '移出想看' : '加入想看',
          () => library.setWatchlist(id, entry?.watchlist != true),
        ),
        action(
          item.remote?.favorite == true ? '取消喜欢' : '喜欢',
          () => connections.setFavorite(id, item.remote?.favorite != true),
        ),
        SubmenuButton(
          menuChildren: [
            action(
              '清除评级',
              () => library.setRating([id], null),
              selected: entry?.userRating == null,
            ),
            const Divider(),
            for (var stars = 1; stars <= 5; stars++)
              action(
                '★' * stars,
                () => library.setRating([id], stars.toDouble()),
                selected: entry?.userRating == stars,
              ),
          ],
          child: const Text('评级'),
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (event) =>
            controller.open(position: event.localPosition),
        child: widget.child,
      ),
    );
  }
}

final _thresholdProvider = FutureProvider<double>(
  (ref) =>
      PlayerPreferencesRepository(ref.watch(sourceRepositoryProvider).database)
          .watchedThreshold,
);
