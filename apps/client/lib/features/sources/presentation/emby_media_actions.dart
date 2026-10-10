import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../playback/application/playback_providers.dart';
import '../../playback/data/player_preferences_repository.dart';
import '../application/emby_providers.dart';
import '../application/source_providers.dart';

void _notice(BuildContext context, String message) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

Future<void> markEmbyItems(
  BuildContext context,
  WidgetRef ref,
  Iterable<MediaIdentity> ids,
  bool watched,
) async {
  try {
    final failed = await ref
        .read(embyConnectionProvider)
        .markPlayed(ids, watched);
    if (!context.mounted) return;
    _notice(
      context,
      failed == 0
          ? (watched ? '已标记为已观看' : '已标记为未观看')
          : '有 $failed 个条目未能写回远程服务器，本机状态已保存，请检查连接后重新操作。',
    );
  } catch (error) {
    if (context.mounted) _notice(context, sourceErrorMessage(error));
  }
}

class EmbyMediaActions extends ConsumerStatefulWidget {
  const EmbyMediaActions({
    required this.item,
    this.favoriteOnly = false,
    super.key,
  });
  final IndexedMedia item;
  final bool favoriteOnly;
  @override
  ConsumerState<EmbyMediaActions> createState() => _EmbyMediaActionsState();
}

class _EmbyMediaActionsState extends ConsumerState<EmbyMediaActions> {
  bool _busy = false;
  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) _notice(context, sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item =
        ref
            .watch(sourceMediaDetailProvider(widget.item.identity))
            .asData
            ?.value ??
        widget.item;
    final watched =
        ref
            .watch(playbackRecordProvider(item.identity))
            .asData
            ?.value
            .watched ??
        false;
    final favorite = item.remote?.favorite == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.favoriteOnly)
          IconButton(
            tooltip: favorite ? '取消喜欢' : '喜欢',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? Colors.red : null,
              size: 20,
            ),
            onPressed: _busy
                ? null
                : () => _perform(() async {
                    await ref
                        .read(embyConnectionProvider)
                        .setFavorite(item.identity, !favorite);
                  }),
          ),
        if (!widget.favoriteOnly)
          TextButton.icon(
            icon: Icon(
              watched
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 16,
            ),
            label: Text(watched ? '清除已观看' : '标记为已观看'),
            onPressed: _busy
                ? null
                : () => _perform(
                    () =>
                        markEmbyItems(context, ref, [item.identity], !watched),
                  ),
          ),
      ],
    );
  }
}

typedef EmbyBatchKey = ({MediaIdentity series, bool oneSeason, int? season});
final _batchProvider = FutureProvider.autoDispose
    .family<({List<MediaIdentity> ids, int watched}), EmbyBatchKey>((
      ref,
      key,
    ) async {
      ref.watch(sourceChangesProvider);
      final repository = ref.watch(sourceRepositoryProvider);
      final playback = ref.watch(playbackRepositoryProvider);
      final groups = key.oneSeason
          ? [key.season]
          : (await repository.seasons(key.series))
                .map((s) => s.number)
                .toList();
      final ids = <MediaIdentity>[];
      for (final season in groups) {
        for (var offset = 0; ; offset += 200) {
          final page = await repository.episodes(
            key.series,
            seasonNumber: season,
            offset: offset,
            limit: 200,
          );
          ids.addAll(page.items.map((i) => i.identity));
          if (offset + page.items.length >= page.total) break;
          if (page.items.isEmpty) throw const SourceFailure('剧集列表不完整，请重试。');
        }
      }
      final records = await playback.readMany(ids);
      final threshold = await PlayerPreferencesRepository(repository.database)
          .watchedThreshold;
      return (
        ids: ids,
        watched: records.values
            .where(
              (r) =>
                  r.watched ||
                  (r.duration > Duration.zero &&
                      r.position.inMilliseconds / r.duration.inMilliseconds >=
                          threshold),
            )
            .length,
      );
    });

class EmbyBatchWatchedButton extends ConsumerStatefulWidget {
  const EmbyBatchWatchedButton({
    required this.series,
    this.oneSeason = false,
    this.season,
    super.key,
  });
  final MediaIdentity series;
  final bool oneSeason;
  final int? season;
  @override
  ConsumerState<EmbyBatchWatchedButton> createState() =>
      _EmbyBatchWatchedButtonState();
}

class _EmbyBatchWatchedButtonState
    extends ConsumerState<EmbyBatchWatchedButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final batch = ref
        .watch(
          _batchProvider((
            series: widget.series,
            oneSeason: widget.oneSeason,
            season: widget.season,
          )),
        )
        .asData
        ?.value;
    final all =
        batch != null &&
        batch.ids.isNotEmpty &&
        batch.watched == batch.ids.length;
    return TextButton.icon(
      icon: Icon(
        all ? Icons.visibility_off_outlined : Icons.visibility,
        size: 14,
      ),
      label: Text(
        all ? '标记全未看' : '标记全已看',
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: _busy || batch == null || batch.ids.isEmpty
          ? null
          : () async {
              setState(() => _busy = true);
              await markEmbyItems(context, ref, batch.ids, !all);
              if (mounted) setState(() => _busy = false);
            },
    );
  }
}

Future<void> showEmbyEpisodeMenu(
  BuildContext context,
  WidgetRef ref,
  IndexedMedia item,
  Offset position,
) async {
  final watched =
      ref.read(playbackRecordProvider(item.identity)).asData?.value.watched ??
      false;
  final choice = await showMenu<bool>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem(value: !watched, child: Text(watched ? '清除已观看' : '标记为已观看')),
    ],
  );
  if (choice != null && context.mounted) {
    await markEmbyItems(context, ref, [item.identity], choice);
  }
}
