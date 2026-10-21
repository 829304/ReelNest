import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../../ui/widgets/source_sheet_button.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSettingsSubsectionHeader(
          title: '离线缓存',
          icon: Icons.download_outlined,
        ),
        const SizedBox(height: 12),
        ...summary.when(
          loading: () => [const AppSettingsNotice(message: '正在读取缓存设置…')],
          error: (_, _) => [
            AppSettingsNotice(
              message: '缓存设置读取失败。',
              error: true,
              actionLabel: '重试',
              onAction: () => ref.invalidate(videoCacheSummaryProvider),
            ),
          ],
          data: (data) => [
            AppSettingsRow(
              title: '视频缓存位置',
              icon: Icons.folder_outlined,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SourceSheetButton(
                    label: '选择…',
                    outlined: true,
                    height: 34,
                    horizontalPadding: 12,
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
                  ),
                  if (data.custom != null) ...[
                    const SizedBox(width: 8),
                    SourceSheetButton(
                      label: '默认',
                      height: 34,
                      horizontalPadding: 12,
                      onPressed: _busy
                          ? null
                          : () => _run(() => repository.setDirectory(null)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            AppSettingsPathText(text: data.path),
            const SizedBox(height: 10),
            const AppSettingsDescription(
              text: '离线视频会保存在这个位置。删除缓存只清理这些离线副本，不会动你原来的文件。',
            ),
            const AppSettingsDivider(),
            AppSettingsRow(
              title: '视频缓存占用',
              icon: Icons.storage_outlined,
              trailing: Text(
                '${data.count} 个视频 · ${cacheBytes(data.bytes)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const AppSettingsDivider(),
            AppSettingsRow(
              title: '缓存容量上限',
              icon: Icons.data_usage_outlined,
              trailing: PopupMenuButton<double>(
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
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: palette.control,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.limit == 0
                            ? '不限制'
                            : '${data.limit.toStringAsFixed(0)} GB',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.expand_more,
                        size: 15,
                        color: palette.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const AppSettingsDescription(
              text: '设定上限后，会优先清理已经看完的和很久没看的缓存，为新内容腾出空间。',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: SourceSheetButton(
                label: '清理视频缓存',
                outlined: true,
                onPressed: _busy || data.count == 0
                    ? null
                    : () => _run(() async {
                        final clear = await showDialog<bool>(
                          context: context,
                          builder: (context) =>
                              const AppSettingsConfirmationDialog(
                                title: '清理视频缓存？',
                                message: '播放中的离线副本会保留，正在下载的任务会继续。',
                                confirmLabel: '清理',
                                destructive: true,
                              ),
                        );
                        if (clear == true) {
                          await repository.maintenance(clear: true);
                        }
                      }),
              ),
            ),
          ],
        ),
        const AppSettingsDivider(),
        Align(
          alignment: Alignment.centerRight,
          child: SourceSheetButton(
            label: '任务中心',
            outlined: true,
            onPressed: () => context.go('/health/tasks'),
          ),
        ),
        const SizedBox(height: 12),
        const OfflineSubscriptionsSection(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AppSettingsNotice(message: _error!, error: true),
        ],
        const SizedBox(height: 12),
        ValueListenableBuilder(
          valueListenable: repository.tasks,
          builder: (context, tasks, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final task in tasks.values.where(
                (t) => t.state != VideoCacheTaskState.cancelled,
              ))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: palette.cleanPanelFill,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
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
                ),
            ],
          ),
        ),
      ],
    );
  }
}
