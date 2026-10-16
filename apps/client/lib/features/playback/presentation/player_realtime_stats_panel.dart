import 'package:flutter/material.dart';

import '../../../player/video_playback_stats.dart';
import 'player_visuals.dart';

/// Low-frequency, read-only mpv statistics shown inside playback information.
/// The parent owns sampling; this widget only formats the latest snapshot.
class PlayerRealtimeStatsPanel extends StatelessWidget {
  const PlayerRealtimeStatsPanel({
    required this.stats,
    required this.loading,
    required this.buffering,
    required this.playing,
    required this.available,
    required this.palette,
    super.key,
  });

  final VideoPlaybackStats stats;
  final bool loading;
  final bool buffering;
  final bool playing;
  final bool available;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('player-realtime-stats'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 7, bottom: 9),
        child: Divider(height: 1, color: palette.rowStroke),
      ),
      Row(
        children: [
          Icon(
            Icons.monitor_heart_outlined,
            size: 15,
            color: palette.secondary,
          ),
          const SizedBox(width: 7),
          Text(
            '实时统计',
            style: TextStyle(
              color: palette.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '约每秒采样 · 只读',
            style: TextStyle(color: palette.subdued, fontSize: 10),
          ),
          const Spacer(),
          _StateBadge(label: _stateLabel, palette: palette),
        ],
      ),
      const SizedBox(height: 9),
      _row('输出 FPS（估算）', Icons.speed_rounded, _estimatedFps),
      const SizedBox(height: 7),
      _row('解码器丢帧', Icons.memory_rounded, _count(stats.decoderDroppedFrames)),
      const SizedBox(height: 7),
      _row('视频输出丢帧', Icons.tv_outlined, _count(stats.outputDroppedFrames)),
      const SizedBox(height: 7),
      _row('实际解码', Icons.developer_board_outlined, _hardwareDecoder),
      const SizedBox(height: 7),
      if (stats.renderPasses.isEmpty)
        _row('VO 渲染 pass', Icons.auto_graph_rounded, '-- · 当前 VO 未提供统计')
      else ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 2, 3, 7),
          child: Text(
            'VO 渲染 pass · 仅显示已返回项，非整帧或 GPU 总耗时',
            style: TextStyle(color: palette.subdued, fontSize: 9.5),
          ),
        ),
        for (var index = 0; index < stats.renderPasses.length; index++) ...[
          if (index > 0) const SizedBox(height: 7),
          _row(
            _safePassName(stats.renderPasses[index].name),
            Icons.auto_graph_rounded,
            _renderPass(stats.renderPasses[index]),
          ),
        ],
      ],
      const SizedBox(height: 7),
      _row('前向缓存（估算）', Icons.inventory_2_outlined, _forwardCache),
      const SizedBox(height: 7),
      _row('AV 同步偏差', Icons.sync_rounded, _avSync),
    ],
  );

  String get _stateLabel {
    if (loading) return '正在载入';
    if (!available) return '暂不可用';
    if (buffering) return '正在缓冲';
    return playing ? '播放中' : '已暂停';
  }

  String get _estimatedFps {
    final value = stats.estimatedFps;
    if (value == null || !value.isFinite || value < 0) return '--';
    return '${value.toStringAsFixed(2)} FPS（估算）';
  }

  String _count(int? value) => value == null || value < 0 ? '--' : '$value';

  String get _hardwareDecoder {
    final value = stats.hardwareDecoder?.trim();
    if (value == null || value.isEmpty) return '--';
    if (value.toLowerCase() == 'no') return '软件解码';
    if (_looksLikeLocation(value)) return '--';
    return _singleLine(value, maximum: 48);
  }

  String get _forwardCache {
    final bytes = stats.forwardCacheBytes;
    final seconds = stats.forwardCacheSeconds;
    final byteText = bytes == null || bytes < 0 ? '--' : _formatBytes(bytes);
    final durationText = seconds == null || !seconds.isFinite || seconds < 0
        ? '--'
        : '约 ${seconds.toStringAsFixed(1)} s';
    return '字节 $byteText · 时长 $durationText';
  }

  String get _avSync {
    final seconds = stats.avSyncSeconds;
    if (seconds == null || !seconds.isFinite) return '--';
    final milliseconds = seconds * 1000;
    final prefix = milliseconds > 0 ? '+' : '';
    return '$prefix${milliseconds.toStringAsFixed(1)} ms';
  }

  String _renderPass(VideoRenderPass pass) => [
    '最近 ${_milliseconds(pass.lastMilliseconds)}',
    '平均 ${_milliseconds(pass.averageMilliseconds)}',
    '峰值 ${_milliseconds(pass.peakMilliseconds)}',
  ].join(' · ');

  String _milliseconds(double? value) {
    if (value == null || !value.isFinite || value < 0) return '--';
    final digits = value < 10 ? 3 : 2;
    return '${value.toStringAsFixed(digits)} ms';
  }

  String _safePassName(String value) {
    final clean = value.trim();
    if (clean.isEmpty || _looksLikeLocation(clean)) return '未命名 pass';
    return _singleLine(clean, maximum: 40);
  }

  bool _looksLikeLocation(String value) =>
      value.contains('://') || value.contains('/') || value.contains(r'\');

  String _singleLine(String value, {required int maximum}) {
    final clean = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return clean.length <= maximum ? clean : '${clean.substring(0, maximum)}…';
  }

  String _formatBytes(int value) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var number = value.toDouble();
    var unit = 0;
    while (number >= 1024 && unit < units.length - 1) {
      number /= 1024;
      unit++;
    }
    final digits = number >= 100 || unit == 0
        ? 0
        : number >= 10
        ? 1
        : 2;
    return '${number.toStringAsFixed(digits)} ${units[unit]}';
  }

  Widget _row(String title, IconData icon, String value) => Row(
    spacing: 10,
    children: [
      SizedBox(
        width: 112,
        child: Row(
          spacing: 7,
          children: [
            SizedBox(
              width: 20,
              child: Icon(icon, size: 14, color: palette.secondary),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.secondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 29),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: palette.choiceFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.rowStroke, width: .7),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.label, required this.palette});

  final String label;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('player-realtime-stats-state'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: palette.choiceFill,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: palette.rowStroke, width: .7),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: palette.secondary,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
