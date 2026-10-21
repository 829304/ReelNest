import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_scan.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/dashboard_surfaces.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../../playback/application/marker_analysis_providers.dart';
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

Color _taskStateTint(BuildContext context, String state, bool active) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (state.contains('失败') || state.contains('错误')) {
    return Color(dark ? 0xFFFF8E8E : 0xFFD92D20);
  }
  if (state.contains('暂停') || state.contains('取消')) {
    return Color(dark ? 0xFFFFC66D : 0xFFD98A00);
  }
  if (state.contains('完成')) {
    return Color(dark ? 0xFF67E19A : 0xFF1F9D57);
  }
  return active
      ? Color(dark ? 0xFF87D0F4 : 0xFF2E90FA)
      : Theme.of(context).colorScheme.onSurfaceVariant;
}

IconData _taskStateIcon(String state, bool active) {
  if (state.contains('失败') || state.contains('错误')) {
    return Icons.error_outline_rounded;
  }
  if (state.contains('暂停')) return Icons.pause_circle_outline_rounded;
  if (state.contains('取消')) return Icons.cancel_outlined;
  if (state.contains('完成')) return Icons.check_circle_outline_rounded;
  if (state.contains('等待')) return Icons.schedule_rounded;
  return active ? Icons.sync_rounded : Icons.radio_button_unchecked_rounded;
}

String cacheTaskTitle(VideoCacheTask t) => switch (t.state) {
  VideoCacheTaskState.queued => '等待中',
  VideoCacheTaskState.downloading => '运行中',
  VideoCacheTaskState.paused => '已暂停',
  VideoCacheTaskState.saving => '正在保存',
  VideoCacheTaskState.complete => '已完成',
  VideoCacheTaskState.failed => '失败',
  VideoCacheTaskState.cancelled => '已取消',
};

class _TaskCenterIcon extends StatelessWidget {
  const _TaskCenterIcon();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF245E85), Color(0xFF227B6B)]
              : const [Color(0xFF2E90FA), Color(0xFF34C759)],
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E90FA).withValues(alpha: dark ? .22 : .18),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(Icons.checklist_rounded, color: Colors.white, size: 28),
    );
  }
}

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
    final markerAnalysis = ref.watch(markerAnalysisProvider);
    final scans = ref.watch(sourceScansProvider);
    final names = {
      for (final s
          in ref.watch(sourcesProvider).asData?.value ?? <MediaSource>[])
        s.id: s.name,
    };
    return ValueListenableBuilder<List<MarkerAnalysisTask>>(
      valueListenable: markerAnalysis.tasks,
      builder: (context, markerTasks, _) {
        final sortedMarkers = [...markerTasks]
          ..sort((a, b) {
            final active = (b.active ? 1 : 0) - (a.active ? 1 : 0);
            return active != 0 ? active : b.startedAt.compareTo(a.startedAt);
          });
        return ValueListenableBuilder(
          valueListenable: cache.tasks,
          builder: (context, tasks, _) {
            final sorted = tasks.values.toList()
              ..sort((a, b) {
                final priority =
                    (cacheTaskActive(b) ? 1 : 0) - (cacheTaskActive(a) ? 1 : 0);
                return priority == 0 ? 0 : priority;
              });
            final total = tasks.length + scans.length + markerTasks.length;
            final activeCount =
                tasks.values.where(cacheTaskActive).length +
                scans.values.where((scan) => scan.busy).length +
                markerTasks.where((task) => task.active).length;
            return PageContent(
              title: '任务中心',
              subtitle: '查看扫描、文件更新和服务同步进度。',
              header: DashboardPageHeader(
                title: '任务中心',
                subtitle: '查看扫描、文件更新和服务同步进度。',
                icon: const _TaskCenterIcon(),
                actions: [
                  if (tasks.values.any((t) => !cacheTaskActive(t)) ||
                      scans.values.any((s) => !s.busy) ||
                      markerTasks.any((task) => !task.active))
                    SourceSheetButton(
                      label: '清除记录',
                      outlined: true,
                      onPressed: () => unawaited(
                        _run(() async {
                          cache.clearFinished();
                          ref
                              .read(sourceScansProvider.notifier)
                              .clearFinished();
                          await markerAnalysis.clearFinished();
                        }),
                      ),
                    ),
                ],
              ),
              children: [
                if (_error != null || markerAnalysis.historyError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: AppInlineNotice(
                      message: _error ?? markerAnalysis.historyError!,
                      kind: AppFeedbackKind.error,
                    ),
                  ),
                if (tasks.isEmpty && scans.isEmpty && markerTasks.isEmpty)
                  const DashboardEmptyState(
                    title: '暂无后台任务',
                    message: '扫描、同步和缓存任务会在运行时集中展示。',
                    icon: Icons.task_alt_rounded,
                  )
                else ...[
                  DashboardSectionHeading(
                    title: '任务记录',
                    subtitle: '任务记录 · $total 项',
                    icon: Icons.history_rounded,
                    badge: activeCount == 0 ? '当前空闲' : '$activeCount 项活动任务',
                  ),
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
                            ? entry.value.progress.phase ==
                                      SourceScanPhase.persisting
                                  ? '正在入库 ${entry.value.progress.processedFiles} / ${entry.value.progress.totalFiles}'
                                  : entry.value.progress.totalFiles > 0
                                  ? '已处理 ${entry.value.progress.processedFiles} / ${entry.value.progress.totalFiles}'
                                  : '已读取 ${entry.value.progress.processedFiles} 个媒体条目'
                            : entry.value.message ?? '操作已结束',
                        active: entry.value.busy,
                        progress: entry.value.progress.totalFiles == 0
                            ? null
                            : entry.value.progress.fraction,
                        actions: [
                          if (entry.value.busy)
                            DashboardIconAction(
                              tooltip: '取消扫描',
                              onPressed: () => ref
                                  .read(sourceScansProvider.notifier)
                                  .cancel(entry.key),
                              icon: Icons.stop_circle_outlined,
                              danger: true,
                            ),
                          if (entry.value.failed)
                            DashboardIconAction(
                              tooltip: '重试任务',
                              onPressed: () => unawaited(
                                _run(
                                  () => ref
                                      .read(sourceScansProvider.notifier)
                                      .scan(entry.key),
                                ),
                              ),
                              icon: Icons.refresh_rounded,
                            ),
                        ],
                      ),
                    for (final task in sortedMarkers.where(
                      (task) => task.active == active,
                    ))
                      _TaskRow(
                        title: task.title,
                        icon: Icons.auto_awesome_outlined,
                        state: task.stateTitle,
                        detail: task.detail,
                        active: task.active,
                        progress: task.progress,
                        actions: [
                          _MarkerAnalysisTaskActions(
                            task: task,
                            controller: markerAnalysis,
                            run: _run,
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
                            DashboardIconAction(
                              tooltip: '暂停缓存',
                              onPressed: () => cache.pause(task),
                              icon: Icons.pause_circle_outline,
                            ),
                          if (task.state == VideoCacheTaskState.paused)
                            DashboardIconAction(
                              tooltip: '继续缓存',
                              onPressed: () =>
                                  unawaited(_run(() => cache.resume(task))),
                              icon: Icons.play_circle_outline,
                            ),
                          if (task.state == VideoCacheTaskState.failed)
                            DashboardIconAction(
                              tooltip: '重试任务',
                              onPressed: () => unawaited(
                                _run(
                                  () => cache.enqueue(task.item, task.quality),
                                ),
                              ),
                              icon: Icons.refresh_rounded,
                            ),
                          if (cacheTaskActive(task))
                            DashboardIconAction(
                              tooltip: '取消缓存',
                              onPressed: () =>
                                  unawaited(_run(() => cache.cancel(task))),
                              icon: Icons.cancel_outlined,
                              danger: true,
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
      },
    );
  }
}

class _MarkerAnalysisTaskActions extends ConsumerWidget {
  const _MarkerAnalysisTaskActions({
    required this.task,
    required this.controller,
    required this.run,
  });

  final MarkerAnalysisTask task;
  final PlaybackMarkerAnalysisController controller;
  final Future<void> Function(Future<void> Function() work) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retryable =
        task.state == MarkerAnalysisState.failed && controller.canRetry(task);
    final eligible = retryable
        ? ref
                  .watch(markerAnalysisEligibilityProvider(task.root))
                  .asData
                  ?.value ==
              true
        : false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (retryable && eligible)
          DashboardIconAction(
            tooltip: '重试任务',
            onPressed: () => unawaited(
              run(() async {
                await controller.retry(task.id);
              }),
            ),
            icon: Icons.refresh_rounded,
          ),
        if (task.isCancellable)
          DashboardIconAction(
            tooltip: '取消检测',
            onPressed: () => controller.cancel(task.id),
            icon: Icons.cancel_outlined,
            danger: true,
          ),
      ],
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
    final tint = _taskStateTint(context, state, active);
    return DashboardPanel(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      radius: 15,
      accent: active ? tint : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: p.dark ? .16 : .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DashboardStatusBadge(
                      label: state,
                      tint: tint,
                      icon: _taskStateIcon(state, active),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                if (active) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: tint,
                      backgroundColor: tint.withValues(alpha: .13),
                    ),
                  ),
                  const SizedBox(height: 7),
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
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 10),
            Wrap(spacing: 6, children: actions),
          ],
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
              showAppToast(
                context,
                error is SourceFailure ? error.message : '自动缓存设置失败，请重试。',
                kind: AppFeedbackKind.error,
              );
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.error != null)
              AppInlineNotice(
                message: state.error!,
                kind: AppFeedbackKind.error,
                actionLabel: '重试',
                onAction: () => unawaited(run(repository.maintain)),
              ),
            if (state.rules.isNotEmpty) ...[
              DashboardSectionHeading(
                title: '自动缓存订阅',
                subtitle: '为已订阅系列自动维护离线内容。',
                icon: Icons.offline_pin_outlined,
                badge: '${state.rules.length} 项',
              ),
              for (final rule in state.rules)
                DashboardPanel(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  radius: 15,
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.cloud_download_outlined,
                          size: 19,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 11),
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
                              '${rule.compact} · ${rule.network.label}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (rule.paused(DateTime.now())) ...[
                        const DashboardStatusBadge(
                          label: '已暂停',
                          tint: Color(0xFFD98A00),
                          icon: Icons.pause_circle_outline,
                        ),
                        const SizedBox(width: 8),
                      ],
                      DashboardIconAction(
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
                        icon: rule.paused(DateTime.now())
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      const SizedBox(width: 6),
                      DashboardIconAction(
                        tooltip: '停止自动缓存',
                        onPressed: () =>
                            unawaited(run(() => repository.stop(rule.series))),
                        icon: Icons.close_rounded,
                        danger: true,
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
    return DashboardPanel(
      margin: const EdgeInsets.only(bottom: 22),
      child: summary.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('正在读取缓存用量…'),
          ],
        ),
        error: (_, _) => AppInlineNotice(
          message: '缓存用量读取失败，请检查缓存目录。',
          kind: AppFeedbackKind.error,
          actionLabel: '重试',
          onAction: () => ref.invalidate(embyCacheStorageProvider),
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
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: p.dark ? .16 : .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.offline_pin_outlined,
                      size: 20,
                      color: p.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '离线缓存用量',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text('供视频离线播放使用', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  DashboardStatusBadge(
                    label: '${s.count} 个缓存',
                    tint: over ? const Color(0xFFD98A00) : p.accent,
                  ),
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
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: SourceSheetButton(
                  label: '打开任务中心',
                  height: 32,
                  horizontalPadding: 12,
                  onPressed: () => context.go('/health/tasks'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
