import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/runtime_observations.dart';
import '../domain/library_health.dart';
import '../domain/media_source.dart';
import '../domain/source_media_type.dart';
import '../features/home/application/home_runtime_providers.dart';
import '../features/home/application/home_actions.dart';
import '../features/home/application/home_providers.dart';
import '../features/home/domain/home_runtime.dart';
import '../features/home/domain/home_snapshot.dart';
import '../features/sources/application/source_providers.dart';
import '../ui/theme/app_palette.dart';
import '../ui/theme/design_tokens.dart';
import '../ui/widgets/source_icons.dart';

/// The persistent status surface at the bottom of the original sidebar.
///
/// It consumes observations already produced by source pages and background
/// work. Merely rendering the sidebar must not probe disks or remote servers.
class SidebarStatusCard extends ConsumerStatefulWidget {
  const SidebarStatusCard({super.key});

  @override
  ConsumerState<SidebarStatusCard> createState() => _SidebarStatusCardState();
}

class _SidebarStatusCardState extends ConsumerState<SidebarStatusCard> {
  static const _rotationInterval = Duration(seconds: 60);
  static const _interruptDuration = Duration(seconds: 6);
  Timer? _rotationTimer;
  Timer? _interruptTimer;
  _SidebarStatus? _interrupt;
  var _rotationTick =
      DateTime.now().millisecondsSinceEpoch ~/ _rotationInterval.inMilliseconds;

  @override
  void initState() {
    super.initState();
    _rotationTimer = Timer.periodic(_rotationInterval, (_) {
      if (mounted) setState(() => _rotationTick++);
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _interruptTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sidebarSourcesProvider).value ?? const [];
    final observations = ref.watch(observedReachabilityProvider);
    final tasks = ref.watch(homeRuntimeTasksProvider);
    final health = ref.watch(homeRuntimeHealthProvider);
    final healthObservation = ref.watch(observedHealthProvider);
    final sourceRevision = ref.watch(sourceChangesProvider).value ?? 0;
    final healthSnapshot = _currentHealthSnapshot(
      healthObservation,
      sourceRevision,
      sources,
    );
    final continueWatching = ref
        .watch(homeCollectionProvider(HomeCollection.continueWatching))
        .items
        .firstOrNull;
    final cache = ref.watch(observedVideoCacheStorageProvider);
    ref.listen<List<RuntimeTask>>(homeRuntimeTasksProvider, _observeTasks);
    final status =
        _interrupt ??
        _statusFor(
          sources,
          observations,
          tasks,
          health,
          healthSnapshot,
          continueWatching,
          cache,
        );
    final palette = context.appPalette;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Semantics(
        button: true,
        label: '${status.title}，${status.subtitle}',
        child: Material(
          key: const ValueKey('sidebar-status-card'),
          color: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: palette.border.withValues(alpha: .82),
              width: .8,
            ),
          ),
          elevation: 0,
          child: InkWell(
            key: const ValueKey('sidebar-status-card-action'),
            onTap: () => _performAction(status),
            borderRadius: BorderRadius.circular(14),
            overlayColor: WidgetStatePropertyAll(
              palette.hoverFill.withValues(alpha: .55),
            ),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: .10),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 58),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : DesignTokens.fastMotion,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOut,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, .12),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _SidebarStatusContent(
                            key: ValueKey(
                              '${status.kind.name}|${status.title}',
                            ),
                            status: status,
                          ),
                        ),
                      ),
                    ),
                    if (status.progress case final progress?)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.bottomLeft,
                            child: Container(
                              key: const ValueKey('sidebar-status-progress'),
                              width: math.max(
                                10,
                                constraints.maxWidth * progress.clamp(0, 1),
                              ),
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    for (final color in status.colors)
                                      color.withValues(alpha: .72),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _SidebarStatus _statusFor(
    List<MediaSource> sources,
    Map<String, ReachabilityObservation> observations,
    List<RuntimeTask> tasks,
    HomeRuntimeHealth health,
    LibraryHealthSnapshot? healthSnapshot,
    HomeVideo? continueWatching,
    VideoCacheStorageObservation? cache,
  ) {
    final activeTask = tasks.where((task) => task.active).firstOrNull;
    if (activeTask != null) {
      final progress = activeTask.progress;
      return _SidebarStatus(
        kind: _SidebarStatusKind.task,
        title: activeTask.title,
        subtitle: progress == null
            ? activeTask.stateTitle
            : '${activeTask.stateTitle} · ${(progress * 100).round()}%',
        colors: const [DesignTokens.blue, Color(0xFF54D1BD)],
        progress: progress,
        route: '/health',
      );
    }

    final attention = <_SidebarStatus>[];
    final offlineCount = sources.where((source) {
      final observation = observations[source.id];
      return observation?.sourceKey == runtimeSourceKey(source) &&
          !observation!.online;
    }).length;
    if (offlineCount > 0) {
      attention.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.issue,
          title: '$offlineCount 个媒体源离线',
          subtitle: '点击查看连接状态',
          colors: const [Color(0xFFFF786B), DesignTokens.orange],
          route: '/sources',
        ),
      );
    }

    final missingCount = healthSnapshot?.missingItems.length ?? 0;
    if (missingCount > 0) {
      attention.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.missingFiles,
          title: '$missingCount 个文件已失效',
          subtitle: '点击查看详情',
          colors: const [Color(0xFFFF7A59), Color(0xFFFFB857)],
          route: '/health',
        ),
      );
    }

    final duplicateCount = healthSnapshot?.duplicates.length ?? 0;
    if (duplicateCount > 0) {
      attention.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.duplicates,
          title: '发现 $duplicateCount 组疑似重复',
          subtitle: '点击查看详情',
          colors: const [Color(0xFFFF7A59), Color(0xFFFFB857)],
          route: '/health',
        ),
      );
    }

    final score = health.totalScore;
    if (score != null && score < 85) {
      attention.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.health,
          title: '媒体健康度 $score',
          subtitle: '点击查看仪表盘',
          colors: const [Color(0xFF40CFAE), DesignTokens.blue],
          progress: score / 100,
          route: '/health',
        ),
      );
    }
    if (attention.isNotEmpty) {
      return attention[_rotationTick.abs() % attention.length];
    }

    final ambient = <_SidebarStatus>[];
    if (score != null && score < 100) {
      ambient.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.health,
          title: '媒体健康度 $score',
          subtitle: '点击查看仪表盘',
          colors: const [Color(0xFF40CFAE), DesignTokens.blue],
          progress: score / 100,
          route: '/health',
        ),
      );
    }
    if (continueWatching != null) {
      ambient.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.continueWatching,
          title: continueWatching.item.title,
          subtitle: '继续播放上次内容',
          colors: const [Color(0xFF5296FF), Color(0xFF7354F2)],
          video: continueWatching,
        ),
      );
    }
    final recentCutoff = DateTime.now().subtract(const Duration(minutes: 30));
    final recentTask = tasks
        .where(
          (task) =>
              !task.active &&
              (task.finishedAt ?? task.startedAt).isAfter(recentCutoff),
        )
        .firstOrNull;
    if (recentTask != null) {
      ambient.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.task,
          title: recentTask.title,
          subtitle: '上次任务 · ${recentTask.stateTitle}',
          colors: const [DesignTokens.blue, Color(0xFF8C8CEB)],
          progress: recentTask.progress,
          route: '/health',
        ),
      );
    }
    if (cache != null && cache.count > 0) {
      ambient.add(
        _SidebarStatus(
          kind: _SidebarStatusKind.cache,
          title: '已缓存 ${cache.count} 项离线内容',
          subtitle: _fileSize(cache.bytes),
          colors: const [DesignTokens.blue, Color(0xFF54D1BD)],
          route: '/settings',
        ),
      );
    }
    ambient.add(
      _SidebarStatus(
        kind: _SidebarStatusKind.sources,
        title: '${sources.length} 个媒体源',
        subtitle: '全部在线 · 刚刚',
        colors: const [DesignTokens.orange, DesignTokens.pink],
        route: '/sources',
      ),
    );
    return ambient[_rotationTick.abs() % ambient.length];
  }

  LibraryHealthSnapshot? _currentHealthSnapshot(
    HealthObservation? observation,
    int revision,
    List<MediaSource> sources,
  ) {
    final snapshot = observation?.revision == revision
        ? observation?.snapshot
        : null;
    if (snapshot == null || !snapshot.evaluationComplete) return null;
    final scope = sources
        .where(
          (source) =>
              HomeRuntimePolicy.visible(source) &&
              source.mediaType != SourceMediaType.music &&
              source.mediaType != SourceMediaType.photo,
        )
        .toList();
    final indexed = {
      for (final source in snapshot.inventory.sources) source.id: source,
    };
    if (scope.isEmpty || indexed.length != scope.length) return null;
    for (final source in scope) {
      final scanned = indexed[source.id];
      if (scanned == null ||
          runtimeSourceKey(scanned) != runtimeSourceKey(source) ||
          scanned.lastScan != source.lastScan) {
        return null;
      }
    }
    return snapshot;
  }

  void _observeTasks(List<RuntimeTask>? previous, List<RuntimeTask> next) {
    if (previous == null || previous.isEmpty) return;
    final active = {
      for (final task in previous.where((task) => task.active)) task.id,
    };
    final completed = next
        .where(
          (task) =>
              active.contains(task.id) &&
              !task.active &&
              task.stateTitle == '已完成',
        )
        .firstOrNull;
    if (completed == null) return;
    _interruptTimer?.cancel();
    setState(() {
      _interrupt = _SidebarStatus(
        kind: _SidebarStatusKind.completedTask,
        title: completed.title,
        subtitle: '刚刚完成',
        colors: const [Color(0xFF40CFAE), DesignTokens.blue],
        route: '/health',
      );
    });
    _interruptTimer = Timer(_interruptDuration, () {
      if (mounted) setState(() => _interrupt = null);
    });
  }

  Future<void> _performAction(_SidebarStatus status) async {
    final video = status.video;
    if (video != null) {
      await homeVideoAction(context, ref, video, 'play');
      return;
    }
    if (status.route case final route?) context.go(route);
  }
}

class _SidebarStatusContent extends StatelessWidget {
  const _SidebarStatusContent({required this.status, super.key});

  final _SidebarStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        DecoratedBox(
          key: const ValueKey('sidebar-status-leading'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: status.colors),
            boxShadow: [
              BoxShadow(
                color: status.colors.first.withValues(alpha: .22),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: SizedBox.square(
            dimension: 32,
            child: Center(
              child: SourceLineIcon(
                switch (status.kind) {
                  _SidebarStatusKind.sources => SourceGlyph.server,
                  _SidebarStatusKind.issue => SourceGlyph.warning,
                  _SidebarStatusKind.missingFiles => SourceGlyph.missingFolder,
                  _SidebarStatusKind.duplicates => SourceGlyph.duplicates,
                  _SidebarStatusKind.task => SourceGlyph.refresh,
                  _SidebarStatusKind.health => SourceGlyph.dashboard,
                  _SidebarStatusKind.continueWatching =>
                    SourceGlyph.playRectangle,
                  _SidebarStatusKind.cache => SourceGlyph.downloadCircle,
                  _SidebarStatusKind.completedTask => SourceGlyph.checkCircle,
                },
                size: 14,
                lineWidth: 2.2,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status.title,
                key: const ValueKey('sidebar-status-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.body,
                  fontSize: 12.5,
                  height: 1.15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                status.subtitle,
                key: const ValueKey('sidebar-status-subtitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.subtle,
                  fontSize: 10.5,
                  height: 1.15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          key: const ValueKey('sidebar-status-trailing'),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.hoverFill.withValues(alpha: .82),
          ),
          child: SizedBox.square(
            dimension: 25,
            child: SourceLineIcon(
              SourceGlyph.chevronRight,
              size: 12,
              lineWidth: 2.2,
              color: palette.secondary.withValues(alpha: .76),
            ),
          ),
        ),
      ],
    );
  }
}

enum _SidebarStatusKind {
  sources,
  issue,
  missingFiles,
  duplicates,
  task,
  health,
  continueWatching,
  cache,
  completedTask,
}

class _SidebarStatus {
  const _SidebarStatus({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.colors,
    this.route,
    this.progress,
    this.video,
  });

  final _SidebarStatusKind kind;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final String? route;
  final double? progress;
  final HomeVideo? video;
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final digits = value >= 100
      ? 0
      : value >= 10
      ? 1
      : 2;
  return '${value.toStringAsFixed(digits)} ${units[index]}';
}
