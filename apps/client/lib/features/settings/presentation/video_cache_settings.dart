import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../domain/media_source.dart';
import '../../sources/application/emby_providers.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/presentation/emby_cache_actions.dart';
import '../../sources/data/emby_cache_repository.dart';
import '../../sources/presentation/emby_task_center.dart';

final videoCacheSummaryProvider = FutureProvider((ref) {
  ref.watch(sourceChangesProvider);
  return ref.watch(embyCacheProvider).summary();
});

class VideoCacheSettings extends ConsumerStatefulWidget {
  const VideoCacheSettings({super.key});
  @override
  ConsumerState<VideoCacheSettings> createState() => _VideoCacheSettingsState();
}

class _VideoCacheSettingsState extends ConsumerState<VideoCacheSettings> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) ref.invalidate(videoCacheSummaryProvider);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SourceFailure
              ? error.message
              : '缓存设置操作失败，请检查目录权限后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(videoCacheSummaryProvider);
    final repository = ref.watch(embyCacheProvider);
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return AppSheetSection(
      title: '离线缓存',
      icon: const Icon(Icons.download_outlined, size: 17),
      colors: palette.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          ...summary.when(
            loading: () => [const Text('正在读取缓存设置…')],
            error: (_, _) => [
              TextButton(
                onPressed: () => ref.invalidate(videoCacheSummaryProvider),
                child: const Text('缓存设置读取失败，重试'),
              ),
            ],
            data: (data) => [
              Row(
                children: [
                  const Text('视频缓存位置'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      data.path,
                      style: TextStyle(fontSize: 12, color: palette.secondary),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final path = await getDirectoryPath(
                              confirmButtonText: '选择缓存位置',
                            );
                            if (path != null) {
                              await repository.setDirectory(path);
                            }
                          }),
                    child: const Text('选择…'),
                  ),
                  if (data.custom != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => repository.setDirectory(null)),
                      child: const Text('默认'),
                    ),
                ],
              ),
              const Text(
                '离线视频会保存在这个位置。删除缓存只清理这些离线副本，不会动你原来的文件。',
                style: TextStyle(fontSize: 12),
              ),
              Row(
                children: [
                  const Expanded(child: Text('视频缓存占用')),
                  Text('${data.count} 个视频 · ${cacheBytes(data.bytes)}'),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('缓存容量上限')),
                  PopupMenuButton<double>(
                    enabled: !_busy,
                    initialValue: data.limit,
                    onSelected: (v) => _run(() => repository.setLimit(v)),
                    itemBuilder: (_) => [
                      for (final value in ({
                        0.0,
                        20.0,
                        50.0,
                        100.0,
                        200.0,
                        500.0,
                        data.limit,
                      }.toList()..sort()))
                        PopupMenuItem(
                          value: value,
                          child: Text(
                            value == 0
                                ? '不限制'
                                : '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} GB',
                          ),
                        ),
                    ],
                    child: Text(
                      data.limit == 0
                          ? '不限制 ▾'
                          : '${data.limit.toStringAsFixed(0)} GB ▾',
                    ),
                  ),
                ],
              ),
              const Text(
                '设定上限后，会优先清理已经看完的和很久没看的缓存，为新内容腾出空间。',
                style: TextStyle(fontSize: 12),
              ),
              TextButton(
                onPressed: _busy || data.count == 0
                    ? null
                    : () => _run(() async {
                        final clear = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('清理视频缓存？'),
                            content: const Text('播放中的离线副本会保留，正在下载的任务会继续。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('清理'),
                              ),
                            ],
                          ),
                        );
                        if (clear == true) {
                          await repository.maintenance(clear: true);
                        }
                      }),
                child: const Text('清理视频缓存'),
              ),
            ],
          ),
          TextButton(
            onPressed: () => context.go('/health/tasks'),
            child: const Text('任务中心'),
          ),
          const OfflineSubscriptionsSection(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ValueListenableBuilder(
            valueListenable: repository.tasks,
            builder: (context, tasks, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final task in tasks.values.where(
                  (t) => t.state != VideoCacheTaskState.cancelled,
                ))
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${task.item.cardTitle} · ${switch (task.state) {
                            VideoCacheTaskState.queued => '等待缓存',
                            VideoCacheTaskState.downloading => '${cacheBytes(task.received)}${task.expected == null ? '' : ' / ${cacheBytes(task.expected!)}'}',
                            VideoCacheTaskState.paused => '已暂停',
                            VideoCacheTaskState.saving => '正在保存字幕',
                            VideoCacheTaskState.complete => task.error ?? '已缓存',
                            VideoCacheTaskState.failed => task.error ?? '缓存失败',
                            VideoCacheTaskState.cancelled => '已取消',
                          }}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if ([
                        VideoCacheTaskState.queued,
                        VideoCacheTaskState.downloading,
                      ].contains(task.state))
                        IconButton(
                          tooltip: '暂停缓存',
                          onPressed: () => repository.pause(task),
                          icon: const Icon(Icons.pause, size: 16),
                        ),
                      if (task.state == VideoCacheTaskState.paused)
                        IconButton(
                          tooltip: '继续缓存',
                          onPressed: () => _run(() => repository.resume(task)),
                          icon: const Icon(Icons.play_arrow, size: 16),
                        ),
                      if (task.state == VideoCacheTaskState.failed)
                        TextButton(
                          onPressed: () => _run(
                            () => repository.enqueue(task.item, task.quality),
                          ),
                          child: const Text('重试'),
                        ),
                      if ([
                        VideoCacheTaskState.queued,
                        VideoCacheTaskState.downloading,
                        VideoCacheTaskState.paused,
                        VideoCacheTaskState.saving,
                      ].contains(task.state))
                        IconButton(
                          tooltip: '取消缓存',
                          onPressed: () => _run(() => repository.cancel(task)),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
