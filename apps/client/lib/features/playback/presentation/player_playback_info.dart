import 'package:flutter/material.dart';

import '../../../domain/media_source.dart';
import '../../../player/video_tracks.dart';
import '../application/playback_session.dart';
import 'player_visuals.dart';

/// PlayerView's centered playback information sheet. It only renders metadata
/// already available to the shared playback session; unavailable values stay
/// explicit instead of being inferred from a filename or stream URL.
class PlayerPlaybackInfoOverlay extends StatefulWidget {
  const PlayerPlaybackInfoOverlay({
    required this.session,
    required this.palette,
    required this.onDismiss,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;
  final VoidCallback onDismiss;

  @override
  State<PlayerPlaybackInfoOverlay> createState() =>
      _PlayerPlaybackInfoOverlayState();
}

class _PlayerPlaybackInfoOverlayState extends State<PlayerPlaybackInfoOverlay> {
  late Future<MediaSource> _source;

  @override
  void initState() {
    super.initState();
    _source = widget.session.sources.source(
      widget.session.item!.identity.sourceId,
      includeCounts: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 64).clamp(0, 640).toDouble();
    final height = (screen.height - 72).clamp(0, 620).toDouble();
    return Semantics(
      key: const ValueKey('player-playback-info'),
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: '播放信息',
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey('dismiss-player-playback-info'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: ColoredBox(color: Colors.black.withValues(alpha: .24)),
          ),
          Center(
            child: PlayerPanelEntrance(
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: PlayerPanelSurface(
                    palette: widget.palette,
                    radius: 18,
                    shadowRadius: 22,
                    shadowOffset: const Offset(0, 10),
                    child: AnimatedBuilder(
                      animation: Listenable.merge([
                        widget.session,
                        widget.session.timeline,
                        widget.session.tracks,
                        widget.session.precision,
                      ]),
                      builder: (context, _) => _content(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final session = widget.session;
    final item = session.item!;
    final remote = item.remote;
    final tracks = session.tracks.value;
    final loop = session.precision.value.loop;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 14, 13),
          child: Row(
            spacing: 12,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: widget.palette.primary,
                size: 19,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(
                      '播放信息',
                      style: TextStyle(
                        color: widget.palette.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.palette.secondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 30,
                child: PlayerControlSurface(
                  palette: widget.palette,
                  enabled: true,
                  child: IconButton(
                    tooltip: '关闭播放信息',
                    padding: EdgeInsets.zero,
                    onPressed: widget.onDismiss,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: widget.palette.secondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: widget.palette.rowStroke),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              spacing: 9,
              children: [
                _sourceRow(),
                _row('类型', Icons.movie_outlined, _typeName(item.type)),
                _row(
                  '时长',
                  Icons.schedule_rounded,
                  _formatDuration(session.clock.duration),
                ),
                _row(
                  '分辨率',
                  Icons.aspect_ratio_rounded,
                  _clean(remote?.resolution),
                ),
                _row(
                  '视频编码',
                  Icons.videocam_outlined,
                  _clean(remote?.videoCodec),
                ),
                _row(
                  '音频编码',
                  Icons.graphic_eq_rounded,
                  _clean(remote?.audioCodec),
                ),
                _row(
                  '文件大小',
                  Icons.storage_rounded,
                  item.bytes > 0 ? _formatBytes(item.bytes) : '未知',
                ),
                _row(
                  '封装 / 码率',
                  Icons.data_object_rounded,
                  _containerAndBitrate(
                    container: remote?.container,
                    bitrate: remote?.bitrate,
                  ),
                ),
                _row('当前清晰度', Icons.hd_outlined, session.quality.label),
                _row(
                  '当前音轨',
                  Icons.volume_up_outlined,
                  _selectedTrack(tracks.audio, tracks.audioId, '自动'),
                ),
                _row(
                  '当前字幕',
                  Icons.subtitles_outlined,
                  _selectedTrack(tracks.subtitles, tracks.subtitleId, '关闭'),
                ),
                _row(
                  '播放状态',
                  Icons.tune_rounded,
                  '${_formatRate(session.clock.rate)} · 音量 ${session.clock.volume.round()}%',
                ),
                _row(
                  '循环',
                  Icons.repeat_rounded,
                  _loopText(loop.loopCurrentItem, loop.start, loop.end),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sourceRow() => FutureBuilder<MediaSource>(
    future: _source,
    builder: (context, snapshot) {
      final source = snapshot.data;
      final value = snapshot.hasError
          ? '未知来源'
          : source == null
          ? '正在读取…'
          : '${source.name} · ${source.kind.label}';
      return _row('来源', Icons.source_outlined, value);
    },
  );

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
              child: Icon(icon, size: 14, color: widget.palette.secondary),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.palette.secondary,
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
            color: widget.palette.choiceFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.palette.rowStroke, width: .7),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: widget.palette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  );

  String _selectedTrack(List<VideoTrack> tracks, int? id, String fallback) {
    for (final track in tracks) {
      if (track.id == id || track.selected) return track.displayName;
    }
    return fallback;
  }

  String _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? '未知' : text;
  }

  String _typeName(String type) => switch (type) {
    'movie' => '电影',
    'episode' => '剧集',
    'video' => '视频',
    _ => type.isEmpty ? '视频' : type,
  };

  String _formatRate(double value) {
    if ((value - value.round()).abs() < .001) {
      return '${value.round()}x';
    }
    return '${value.toStringAsFixed(2)}x';
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

  String _containerAndBitrate({String? container, int? bitrate}) {
    final values = <String>[];
    final cleanContainer = container?.trim();
    if (cleanContainer?.isNotEmpty == true) {
      values.add(cleanContainer!.toUpperCase());
    }
    if (bitrate != null && bitrate > 0) {
      values.add('${(bitrate / 1000000).toStringAsFixed(1)} Mbps');
    }
    return values.isEmpty ? '未知' : values.join(' · ');
  }

  String _loopText(bool current, Duration? start, Duration? end) {
    final values = <String>[];
    if (current) values.add('单片循环');
    if (start != null) {
      values.add(
        end == null
            ? 'A 点 ${_formatDuration(start)}'
            : 'A-B ${_formatDuration(start)} - ${_formatDuration(end)}',
      );
    }
    return values.isEmpty ? '关闭' : values.join(' · ');
  }

  String _formatDuration(Duration value) {
    if (value < Duration.zero) return '--:--';
    final total = value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
