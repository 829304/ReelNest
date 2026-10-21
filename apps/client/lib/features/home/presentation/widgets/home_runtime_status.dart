import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/runtime_observations.dart';
import '../../../../domain/media_source.dart';
import '../../../../ui/theme/source_sheet_palette.dart';
import '../../../sources/application/source_providers.dart';
import '../../application/home_providers.dart';
import '../../application/home_runtime_providers.dart';
import '../../data/home_repository.dart';
import '../../domain/home_runtime.dart';

const _mint = Color(0xFF22D3A8);
const _cyan = Color(0xFF36BFFA);
const _blue = Color(0xFF2E90FA);
const _colors = [
  _mint,
  Color(0xFFFF5C8A),
  _blue,
  Color(0xFFFF9F45),
  _cyan,
  Color(0xFFD946EF),
  Color(0xFF5B6CFF),
  Color(0xFFF97316),
  Color(0xFF14B8A6),
  Color(0xFFA855F7),
];

/// HomeVividDashboard: three 246px cards, 16px gutter, 20px card padding.
/// Task progress rebuilds this subtree rather than the recommendation board.
class HomeRuntimeStatus extends ConsumerWidget {
  const HomeRuntimeStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sidebarSourcesProvider).value ?? [];
    final visible = sources.where(HomeRuntimePolicy.visible).toList();
    final reachability = ref.watch(observedReachabilityProvider);
    final health = ref.watch(homeRuntimeHealthProvider);
    final tasks = ref.watch(homeRuntimeTasksProvider);
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final groups = [
      for (final source in visible)
        (
          source: source,
          online: HomeRuntimePolicy.online(source, reachability),
          count: HomeRepository.accepts(source) ? _count(ref, source.id) : null,
        ),
    ];
    final online = groups.where((g) => g.online == true).length;
    final unknown = groups.where((g) => g.online == null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 20,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_mint, _cyan]),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 9),
            const Text(
              '运行状态',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            _badge('实时', _mint),
            const Spacer(),
            TextButton(
              onPressed: () => context.go('/health'),
              style: TextButton.styleFrom(
                foregroundColor: p.secondary,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Text(
                '进入仪表盘 ›',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final panelWidth = compact
                ? math.min(300.0, constraints.maxWidth)
                : (constraints.maxWidth - 32) / 3;
            final panels = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: panelWidth,
                  child: _Panel(
                    id: 'sources',
                    onTap: () => context.go('/sources'),
                    p: p,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '媒体源',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            Text(
                              '${visible.length} 个',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: groups.isEmpty
                              ? Center(
                                  child: Text(
                                    '还没有媒体源',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p.secondary,
                                    ),
                                  ),
                                )
                              : Row(
                                  children: [
                                    SizedBox(
                                      width: 92,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 76,
                                            height: 76,
                                            child: CustomPaint(
                                              painter: _SourcePie([
                                                for (
                                                  var i = 0;
                                                  i < groups.length;
                                                  i++
                                                )
                                                  (
                                                    weight: math.max(
                                                      groups[i].count ?? 0,
                                                      1,
                                                    ),
                                                    color:
                                                        groups[i].online == true
                                                        ? _colors[i %
                                                              _colors.length]
                                                        : p.border,
                                                  ),
                                              ], p.border),
                                            ),
                                          ),
                                          const SizedBox(height: 7),
                                          Text(
                                            unknown > 0
                                                ? online == 0
                                                      ? '—/${groups.length}'
                                                      : '≥$online/${groups.length}'
                                                : '$online/${groups.length}',
                                            key: const ValueKey(
                                              'home-runtime-online',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          Text(
                                            unknown > 0
                                                ? '$unknown 个待检测'
                                                : '在线',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                              color: p.secondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _SourceList(groups: groups, p: p),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: panelWidth,
                  child: _Panel(
                    id: 'health',
                    onTap: () => context.go('/health'),
                    p: p,
                    child: Tooltip(
                      message: health.totalScore == null
                          ? '复用最近一次检测；请进入仪表盘完成当前视频库检查。来源或索引变化后需重新检测。'
                          : '按原版来源、核心资料、详情资料、失效路径和重复项计算。${health.partialIndex ? '当前仅覆盖已载入的媒体，完整同步后可重新检测。' : '当前为视频范围的最近检测结果。'}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '健康度总评分',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          Center(
                            child: SizedBox(
                              width: 96,
                              height: 96,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _HealthRing(
                                        health.totalScore,
                                        p.border,
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        health.totalScore?.toString() ?? '—',
                                        key: const ValueKey(
                                          'home-runtime-score',
                                        ),
                                        style: const TextStyle(
                                          fontSize: 27,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        health.label,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: p.secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          _metric('媒体源健康度', health.sourcePercent, _mint, p),
                          const SizedBox(height: 5),
                          _metric('元数据健康度', health.metadataPercent, _blue, p),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: panelWidth,
                  child: _Panel(
                    id: 'tasks',
                    onTap: () => context.go('/health/tasks'),
                    p: p,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '任务中心',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (tasks.any((t) => t.active))
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _badge(
                                    '${tasks.where((t) => t.active).length} 进行中',
                                    _mint,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        if (tasks.isEmpty)
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.task_alt,
                                    size: 22,
                                    color: _blue.withValues(alpha: .68),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '无任务',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '扫描和整理任务会显示在这里',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final task in tasks.take(3)) ...[
                            _TaskRow(task: task, p: p),
                            if (task != tasks.take(3).last)
                              const SizedBox(height: 10),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            );
            if (!compact) return panels;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: panels,
            );
          },
        ),
      ],
    );
  }

  int? _count(WidgetRef ref, String id) {
    final stats = ref.watch(homeSourceStatsProvider(id));
    final value = stats.isLoading ? null : stats.value;
    return value == null ? null : value.movies + value.series + value.episodes;
  }
}

typedef _SourceGroup = ({MediaSource source, bool? online, int? count});

class _SourceList extends StatelessWidget {
  const _SourceList({required this.groups, required this.p});
  final List<_SourceGroup> groups;
  final SourceSheetPalette p;
  @override
  Widget build(BuildContext context) {
    Widget row(int i) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _colors[i % _colors.length].withValues(
                alpha: groups[i].online == true ? .15 : .08,
              ),
            ),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: groups[i].online == true
                    ? _colors[i % _colors.length]
                    : p.secondary.withValues(alpha: .68),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message:
                  '${groups[i].source.name} · ${switch (groups[i].online) {
                    true => '在线',
                    false => '离线',
                    null => '待检测',
                  }}',
              child: Text(
                groups[i].source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: p.secondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '当前已载入的公开视频数量',
            child: Text(
              groups[i].count?.toString() ?? '—',
              style: TextStyle(fontSize: 11.5, color: p.secondary),
            ),
          ),
        ],
      ),
    );
    return groups.length > 5
        ? ListView.builder(
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: groups.length,
            itemBuilder: (_, i) => row(i),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (var i = 0; i < groups.length; i++) row(i)],
          );
  }
}

Widget _badge(String text, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .15),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(
    text,
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
  ),
);

Widget _dot(Color color) => Container(
  width: 9,
  height: 9,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(colors: [color, _cyan]),
  ),
);

Widget _metric(String label, int? value, Color color, SourceSheetPalette p) =>
    Row(
      children: [
        _dot(color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
        Text(
          value == null ? '—' : '$value%',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: p.secondary,
          ),
        ),
      ],
    );

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.p});
  final RuntimeTask task;
  final SourceSheetPalette p;
  @override
  Widget build(BuildContext context) {
    final color = task.isCache
        ? const Color(0xFFFF9F45)
        : task.title.startsWith('Emby')
        ? const Color(0xFFFF5C8A)
        : _blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _dot(color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              task.stateTitle,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: task.active ? _mint : p.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          task.detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: p.secondary),
        ),
        if (task.progress case final progress?) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LayoutBuilder(
              builder: (_, constraints) => Container(
                height: 5,
                color: p.border,
                alignment: Alignment.centerLeft,
                child: Container(
                  width: math.max(
                    4,
                    constraints.maxWidth * progress.clamp(0, 1),
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, _cyan]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Panel extends StatefulWidget {
  const _Panel({
    required this.id,
    required this.onTap,
    required this.p,
    required this.child,
  });
  final String id;
  final VoidCallback onTap;
  final SourceSheetPalette p;
  final Widget child;
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  bool _hover = false, _focused = false;
  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    final highlighted = _hover || _focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: animate ? const Duration(milliseconds: 140) : Duration.zero,
        transform: Matrix4.translationValues(
          0,
          highlighted && animate ? -4 : 0,
          0,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: widget.p.shadow.withValues(
                      alpha: _focused ? .22 : .18,
                    ),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: widget.p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: _focused
                  ? widget.p.accent.withValues(alpha: .78)
                  : widget.p.border,
              width: _focused ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('home-runtime-${widget.id}'),
            onTap: widget.onTap,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
            },
            child: SizedBox(
              height: 246,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourcePie extends CustomPainter {
  _SourcePie(this.groups, this.base);
  final List<({int weight, Color color})> groups;
  final Color base;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(rect, Paint()..color = base);
    final total = groups.fold<int>(0, (sum, group) => sum + group.weight);
    var start = -math.pi / 2;
    for (final group in groups) {
      final sweep = group.weight / math.max(total, 1) * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = group.color);
      canvas.drawArc(
        rect,
        start,
        sweep,
        true,
        Paint()
          ..color = Colors.white.withValues(alpha: .56)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _SourcePie oldDelegate) =>
      base != oldDelegate.base || !listEquals(groups, oldDelegate.groups);
}

class _HealthRing extends CustomPainter {
  _HealthRing(this.score, this.base);
  final int? score;
  final Color base;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(6);
    final paint = Paint()
      ..color = base
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawOval(rect, paint);
    if (score != null) {
      paint
        ..color = Colors.white
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [_cyan, _blue, _mint],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        score!.clamp(0, 100) / 100 * 2 * math.pi,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HealthRing oldDelegate) =>
      score != oldDelegate.score || base != oldDelegate.base;
}
