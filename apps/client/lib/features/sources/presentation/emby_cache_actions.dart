import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/emby/emby_quality.dart';
import '../../../domain/media_source.dart';
import '../application/emby_providers.dart';
import '../application/source_providers.dart';
import '../data/emby_cache_repository.dart';
import 'emby_offline_menu.dart';

/// VideoCacheMenuItems' manual download/quality/remove operations. Series
/// selections expand into their indexed episodes, retaining source identities.
class EmbyCacheActions extends ConsumerWidget {
  const EmbyCacheActions({required this.item, this.compact = false, super.key});
  final IndexedMedia item;
  final bool compact;
  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is SourceFailure ? error.message : '缓存操作失败，请重试。',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(embyCacheProvider);
    final cached = ref.watch(embyCachedVideosProvider).asData?.value ?? [];
    final candidates = item.isSeries
        ? ref.watch(embyCacheCandidatesProvider(item.identity)).asData?.value ??
              <IndexedMedia>[]
        : [item];
    final ids = candidates.map((c) => c.identity).toSet();
    final entries = cached.where((c) => ids.contains(c.identity)).toList();
    final options = EmbyVideoQuality.options(candidates.firstOrNull ?? item);
    return ValueListenableBuilder(
      valueListenable: repository.tasks,
      builder: (context, tasks, _) {
        final task = tasks[item.identity];
        final active =
            task != null &&
            [
              VideoCacheTaskState.queued,
              VideoCacheTaskState.downloading,
              VideoCacheTaskState.paused,
              VideoCacheTaskState.saving,
            ].contains(task.state);
        final title = item.isSeries && entries.isNotEmpty
            ? '${entries.length == candidates.length ? '已缓存' : '部分缓存'} ${entries.length}/${candidates.length} 集'
            : active
            ? switch (task.state) {
                VideoCacheTaskState.queued => '等待缓存…',
                VideoCacheTaskState.paused => '缓存已暂停',
                VideoCacheTaskState.saving => '正在保存字幕…',
                _ =>
                  task.expected == null
                      ? '已下载 ${cacheBytes(task.received)}'
                      : '正在缓存 ${(task.received / task.expected! * 100).clamp(0, 100).round()}%',
              }
            : entries.isEmpty
            ? '缓存到本地'
            : '已缓存 · ${entries.first.qualityLabel}';
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<String>(
              enabled: !active && candidates.isNotEmpty,
              tooltip: title,
              onSelected: (value) => unawaited(
                _run(context, () async {
                  if (value == 'delete') {
                    if (item.isSeries) {
                      final children = await ref
                          .read(sourceRepositoryProvider)
                          .indexedSource(item.identity.sourceId);
                      for (final child in children.where(
                        (c) => c.parentId == item.identity.localId,
                      )) {
                        await repository.maintenance(remove: child.identity);
                      }
                    } else {
                      await repository.maintenance(remove: item.identity);
                    }
                  } else {
                    final quality =
                        options.where((q) => q.id == value).firstOrNull ??
                        EmbyVideoQuality.source;
                    await repository.enqueue(item, quality);
                  }
                }),
              ),
              itemBuilder: (_) => [
                if (!active) ...[
                  for (final option
                      in options.isEmpty ? [EmbyVideoQuality.source] : options)
                    PopupMenuItem(
                      value: option.id,
                      child: Text(
                        '${entries.isEmpty ? '缓存到本地' : '重新缓存到本地'}${options.isEmpty ? '' : ' · ${option.label}'}',
                      ),
                    ),
                ],
                if (entries.isNotEmpty)
                  const PopupMenuItem(value: 'delete', child: Text('删除缓存文件')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      entries.isEmpty
                          ? Icons.download_outlined
                          : Icons.offline_pin_outlined,
                      size: 16,
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(title, style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            EmbyOfflineMenu(item: item, compact: compact),
            if (active) ...[
              if (task.state != VideoCacheTaskState.saving)
                IconButton(
                  tooltip: task.state == VideoCacheTaskState.paused
                      ? '继续缓存'
                      : '暂停缓存',
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => task.state == VideoCacheTaskState.paused
                      ? unawaited(_run(context, () => repository.resume(task)))
                      : repository.pause(task),
                  icon: Icon(
                    task.state == VideoCacheTaskState.paused
                        ? Icons.play_arrow
                        : Icons.pause,
                  ),
                ),
              IconButton(
                tooltip: '取消缓存',
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    unawaited(_run(context, () => repository.cancel(task))),
                icon: const Icon(Icons.close),
              ),
            ],
            if (!compact && task?.error != null)
              Text(
                task!.error!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        );
      },
    );
  }
}

String cacheBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}
