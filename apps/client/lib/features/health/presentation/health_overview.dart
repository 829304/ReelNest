import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/library_health.dart';
import '../../../domain/runtime_status.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../domain/health_score.dart';

/// LibraryHealthCenterView.overviewGrid / DashboardRingCard: four rings, 12 gap,
/// 14 padding, 48 diameter, 6 stroke and 13 content gap.
class HealthOverview extends StatelessWidget {
  const HealthOverview({
    required this.snapshot,
    required this.tasks,
    super.key,
  });
  final LibraryHealthSnapshot snapshot;
  final List<RuntimeTask> tasks;
  @override
  Widget build(BuildContext context) {
    final health = HealthScore.dashboardHealth(snapshot);
    final metadata = HealthScore.dashboardMetadata(snapshot);
    final sources = snapshot.inventory.sources.length;
    final online = sources - snapshot.offline.length;
    final active = tasks.where((t) => t.active).length;
    final failed = tasks
        .where((t) => {'有错误', '失败', '已失败'}.contains(t.stateTitle))
        .length;
    final issues =
        snapshot.offline.length +
        snapshot.missing.length +
        snapshot.duplicates.length +
        snapshot.metadataGaps.length +
        snapshot.detailGaps.length +
        snapshot.unhealthyURLs.length;
    final gaps = snapshot.metadataGaps.length + snapshot.detailGaps.length;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = SourceSheetPalette(dark);
    final warning = Color(dark ? 0xFFFFB84D : 0xFFD98A00);
    final cyan = dark ? const Color(0xFF87D0F4) : const Color(0xFF36BFFA);
    final good = Color(dark ? 0xFF45D67F : 0xFF1F9D57);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: _Ring(
              title: '健康评分',
              value: '$health%',
              note: issues == 0 ? '未发现待处理项' : '$issues 项需处理',
              icon: Icons.verified_outlined,
              progress: health / 100,
              tint: issues == 0 ? palette.selectedTint : warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Ring(
              title: '来源可用',
              value: '$online/$sources',
              note: snapshot.offline.isEmpty
                  ? '全部在线'
                  : '${snapshot.offline.length} 个离线',
              icon: Icons.storage_outlined,
              progress: sources == 0 ? 1 : online / sources,
              tint: snapshot.offline.isEmpty ? cyan : warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Ring(
              title: '资料完整',
              value: '$metadata%',
              note: gaps == 0 ? '资料完整' : '$gaps 个缺口',
              icon: Icons.sell_outlined,
              progress: metadata / 100,
              tint: gaps == 0 ? good : warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Ring(
              title: '后台任务',
              value: '$active',
              note: failed > 0 ? '$failed 个失败可处理' : '${tasks.length} 条记录',
              icon: Icons.checklist_outlined,
              progress: tasks.isEmpty ? 1 : active / tasks.length,
              tint: failed > 0 ? Colors.red : palette.selectedTint,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
    required this.progress,
    required this.tint,
  });
  final String title, value, note;
  final IconData icon;
  final double progress;
  final Color tint;
  @override
  Widget build(BuildContext context) {
    final p = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Semantics(
      container: true,
      label: '$title $value $note',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.staticSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _ProgressRing(progress, tint, p.dark),
                child: Icon(icon, color: tint, size: 18),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: p.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    key: ValueKey('health-overview-$title'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Tooltip(
                    message: note,
                    child: Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends CustomPainter {
  _ProgressRing(this.progress, this.color, this.dark);
  final double progress;
  final Color color;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: dark ? .16 : .12);
    final rect = (Offset.zero & size).deflate(3);
    canvas.drawOval(rect, paint);
    // The track's translucent alpha must not attenuate the foreground shader.
    paint.color = Colors.white;
    paint.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [color, const Color(0xFF36BFFA).withValues(alpha: .86)],
    ).createShader(rect);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRing old) =>
      progress != old.progress || color != old.color || dark != old.dark;
}
