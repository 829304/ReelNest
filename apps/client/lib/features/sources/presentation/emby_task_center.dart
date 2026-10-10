import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/emby_providers.dart';
import '../application/source_providers.dart';
import '../data/emby_cache_repository.dart';
import 'emby_cache_actions.dart';

bool cacheTaskActive(VideoCacheTask task) => [
  VideoCacheTaskState.queued,
  VideoCacheTaskState.downloading,
  VideoCacheTaskState.saving,
  VideoCacheTaskState.paused,
].contains(task.state);
String cacheTaskTitle(VideoCacheTask t) => switch (t.state) {
  VideoCacheTaskState.queued => '等待中',
  VideoCacheTaskState.downloading => '运行中',
  VideoCacheTaskState.paused => '已暂停',
  VideoCacheTaskState.saving => '正在保存',
  VideoCacheTaskState.complete => '已完成',
  VideoCacheTaskState.failed => '失败',
  VideoCacheTaskState.cancelled => '已取消',
};

class EmbyTaskCenterPage extends ConsumerStatefulWidget {
  const EmbyTaskCenterPage({super.key});
  @override
  ConsumerState<EmbyTaskCenterPage> createState() => _EmbyTaskCenterPageState();
}

class _EmbyTaskCenterPageState extends ConsumerState<EmbyTaskCenterPage> {
  String? _error;
  Future<void> _run(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is SourceFailure ? error.message : '任务操作失败，请重试。',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(embyCacheProvider);
    final scans = ref.watch(sourceScansProvider);
    final names = {
      for (final s
          in ref.watch(sourcesProvider).asData?.value ?? <MediaSource>[])
        s.id: s.name,
    };
    return ValueListenableBuilder(
      valueListenable: cache.tasks,
      builder: (context, tasks, _) {
        final sorted = tasks.values.toList()
          ..sort((a, b) {
            final priority =
                (cacheTaskActive(b) ? 1 : 0) - (cacheTaskActive(a) ? 1 : 0);
            return priority == 0 ? 0 : priority;
          });
        return PageContent(
          title: '任务中心',
          subtitle: '查看扫描、文件更新和服务同步进度。',
          header: Row(
            children: [
              const Icon(Icons.checklist, size: 42),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '任务中心',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text('查看扫描、文件更新和服务同步进度。', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if (tasks.values.any((t) => !cacheTaskActive(t)) ||
                  scans.values.any((s) => !s.busy))
                SourceSheetButton(
                  label: '清除记录',
                  onPressed: () {
                    cache.clearFinished();
                    ref.read(sourceScansProvider.notifier).clearFinished();
                  },
                ),
            ],
          ),
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (tasks.isEmpty && scans.isEmpty)
              const SizedBox(
                height: 360,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 40),
                      SizedBox(height: 12),
                      Text(
                        '暂无后台任务',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('扫描、同步和缓存任务会在运行时集中展示。'),
                    ],
                  ),
                ),
              )
            else ...[
              Text(
                '任务记录 · ${tasks.length + scans.length} 项',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (final active in [true, false]) ...[
                for (final entry in scans.entries.where(
                  (e) => e.value.busy == active,
                ))
                  _TaskRow(
                    title: names[entry.key] ?? '媒体源',
                    icon: Icons.sync,
                    state: entry.value.queued
                        ? '等待中'
                        : entry.value.running
                        ? '运行中'
                        : entry.value.failed
                        ? '失败'
                        : entry.value.cancelled
                        ? '已取消'
                        : '已完成',
                    detail: entry.value.busy
                        ? '已处理 ${entry.value.progress.processedFiles} / ${entry.value.progress.totalFiles}'
                        : entry.value.message ?? '操作已结束',
                    active: entry.value.busy,
                    progress: entry.value.progress.totalFiles == 0
                        ? null
                        : entry.value.progress.fraction,
                    actions: [
                      if (entry.value.busy)
                        IconButton(
                          tooltip: '取消扫描',
                          onPressed: () => ref
                              .read(sourceScansProvider.notifier)
                              .cancel(entry.key),
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                          ),
                        ),
                      if (entry.value.failed)
                        IconButton(
                          tooltip: '重试任务',
                          onPressed: () => unawaited(
                            _run(
                              () => ref
                                  .read(sourceScansProvider.notifier)
                                  .scan(entry.key),
                            ),
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                    ],
                  ),
                for (final task in sorted.where(
                  (t) => cacheTaskActive(t) == active,
                ))
                  _TaskRow(
                    title: '缓存 · ${task.item.cardTitle}',
                    icon: Icons.download_outlined,
                    state: cacheTaskTitle(task),
                    active:
                        cacheTaskActive(task) &&
                        task.state != VideoCacheTaskState.paused,
                    progress: task.expected == null || task.expected == 0
                        ? null
                        : (task.received / task.expected!).clamp(0, 1),
                    detail:
                        task.error ??
                        '${cacheBytes(task.received)}${task.expected == null ? '' : ' / ${cacheBytes(task.expected!)}'}',
                    actions: [
                      if (task.state == VideoCacheTaskState.queued ||
                          task.state == VideoCacheTaskState.downloading)
                        IconButton(
                          tooltip: '暂停缓存',
                          onPressed: () => cache.pause(task),
                          icon: const Icon(
                            Icons.pause_circle_outline,
                            size: 18,
                          ),
                        ),
                      if (task.state == VideoCacheTaskState.paused)
                        IconButton(
                          tooltip: '继续缓存',
                          onPressed: () =>
                              unawaited(_run(() => cache.resume(task))),
                          icon: const Icon(Icons.play_circle_outline, size: 18),
                        ),
                      if (task.state == VideoCacheTaskState.failed)
                        IconButton(
                          tooltip: '重试任务',
                          onPressed: () => unawaited(
                            _run(() => cache.enqueue(task.item, task.quality)),
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                      if (cacheTaskActive(task))
                        IconButton(
                          tooltip: '取消缓存',
                          onPressed: () =>
                              unawaited(_run(() => cache.cancel(task))),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                        ),
                    ],
                  ),
              ],
            ],
            const SizedBox(height: 22),
            const OfflineSubscriptionsSection(),
          ],
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.title,
    required this.icon,
    required this.state,
    required this.detail,
    required this.active,
    required this.actions,
    this.progress,
  });
  final String title, state, detail;
  final IconData icon;
  final bool active;
  final double? progress;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      state,
                      style: TextStyle(
                        fontSize: 12,
                        color: state == '失败' ? Colors.red : p.accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                if (active) ...[
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 5),
                ],
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.secondary),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class OfflineSubscriptionsSection extends ConsumerWidget {
  const OfflineSubscriptionsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(embyOfflineProvider);
    return ValueListenableBuilder(
      valueListenable: repository.state,
      builder: (context, state, _) {
        Future<void> run(Future<void> Function() work) async {
          try {
            await work();
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    error is SourceFailure ? error.message : '自动缓存设置失败，请重试。',
                  ),
                ),
              );
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.error != null)
              Row(
                children: [
                  Expanded(child: Text(state.error!)),
                  TextButton(
                    onPressed: () => unawaited(run(repository.maintain)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            if (state.rules.isNotEmpty) ...[
              const Text(
                '自动缓存订阅',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              for (final rule in state.rules)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rule.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${rule.compact} · ${rule.network.label}${rule.paused(DateTime.now()) ? ' · 已暂停' : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: rule.paused(DateTime.now())
                            ? '继续自动缓存'
                            : '暂停 7 天',
                        onPressed: () => unawaited(
                          run(
                            () => repository.update(
                              rule.series,
                              pause: !rule.paused(DateTime.now()),
                            ),
                          ),
                        ),
                        icon: Icon(
                          rule.paused(DateTime.now())
                              ? Icons.play_arrow
                              : Icons.pause,
                          size: 18,
                        ),
                      ),
                      IconButton(
                        tooltip: '停止自动缓存',
                        onPressed: () =>
                            unawaited(run(() => repository.stop(rule.series))),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// LibraryHealthCenterView.storageCard. The bar is determinate even for an
/// empty library and never denotes a background scan.
class EmbyCacheDashboard extends ConsumerWidget {
  const EmbyCacheDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(embyCacheStorageProvider);
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.border),
      ),
      child: summary.when(
        loading: () => const Text('正在读取缓存用量…'),
        error: (_, _) => Row(
          children: [
            const Expanded(child: Text('缓存用量读取失败，请检查缓存目录。')),
            TextButton(
              onPressed: () => ref.invalidate(embyCacheStorageProvider),
              child: const Text('重试'),
            ),
          ],
        ),
        data: (s) {
          final limitBytes = s.limit * 1024 * 1024 * 1024;
          final fraction = limitBytes > 0
              ? (s.bytes / limitBytes).clamp(0.0, 1.0)
              : s.bytes > 0
              ? .05
              : 0.0;
          final over = limitBytes > 0 && s.bytes > limitBytes;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '离线缓存用量',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text('${s.count} 个缓存', style: const TextStyle(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${cacheBytes(s.bytes)}${limitBytes > 0 ? ' / ${cacheBytes(limitBytes.round())}' : ' · 未设容量上限'}',
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: p.accent.withValues(alpha: .12)),
                      FractionallySizedBox(
                        key: const ValueKey('cache-storage-fraction'),
                        alignment: Alignment.centerLeft,
                        widthFactor: fraction,
                        child: ColoredBox(
                          color: over ? Colors.orange : p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                over ? '已超出缓存上限，可在设置中清理或调大上限。' : '离线缓存供视频离线播放使用，上限可在设置中调整。',
                style: const TextStyle(fontSize: 12),
              ),
              TextButton(
                onPressed: () => context.go('/health/tasks'),
                child: const Text('任务中心'),
              ),
            ],
          );
        },
      ),
    );
  }
}
