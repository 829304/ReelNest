import 'dart:async';

import 'package:flutter/foundation.dart';

import 'video_engine.dart';

/// A read-only snapshot for the current media. Null means unavailable, not zero.
class VideoPlaybackStats {
  const VideoPlaybackStats({
    this.estimatedFps,
    this.decoderDroppedFrames,
    this.outputDroppedFrames,
    this.hardwareDecoder,
    this.renderPasses = const [],
    this.forwardCacheBytes,
    this.forwardCacheSeconds,
    this.avSyncSeconds,
  });

  final double? estimatedFps;
  final int? decoderDroppedFrames;
  final int? outputDroppedFrames;
  final String? hardwareDecoder;
  final List<VideoRenderPass> renderPasses;
  final int? forwardCacheBytes;
  final double? forwardCacheSeconds;
  final double? avSyncSeconds;

  /// Values here have already been read with MPV_FORMAT_NODE, not OSD strings.
  factory VideoPlaybackStats.fromMpv(Map<String, Object?> properties) {
    double? number(Object? value, {bool signed = false}) {
      if (value is! num) return null;
      final result = value.toDouble();
      return result.isFinite && (signed || result >= 0) ? result : null;
    }

    int? count(Object? value) => value is int && value >= 0 ? value : null;
    final passes = <VideoRenderPass>[];
    final rawPasses = properties['vo-passes'];
    if (rawPasses is Map) {
      for (final type in ['fresh', 'redraw']) {
        final entries = rawPasses[type];
        if (entries is! List) continue;
        for (final (index, entry) in entries.take(128).indexed) {
          if (entry is! Map) continue;
          final last = number(entry['last']);
          final average = number(entry['avg']);
          final peak = number(entry['peak']);
          if (last == null && average == null && peak == null) continue;
          final description = entry['desc'];
          final name = description is String && description.trim().isNotEmpty
              ? description.trim().replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
              : 'Pass ${index + 1}';
          passes.add(
            VideoRenderPass(
              name:
                  '$type · ${name.length > 160 ? name.substring(0, 160) : name}',
              lastMilliseconds: last == null ? null : last / 1000000,
              averageMilliseconds: average == null ? null : average / 1000000,
              peakMilliseconds: peak == null ? null : peak / 1000000,
            ),
          );
        }
      }
    }
    final decoder = properties['hwdec-current'];
    return VideoPlaybackStats(
      estimatedFps: number(properties['estimated-vf-fps']),
      decoderDroppedFrames: count(properties['decoder-frame-drop-count']),
      outputDroppedFrames: count(properties['frame-drop-count']),
      hardwareDecoder:
          decoder is String &&
              RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(decoder)
          ? decoder
          : null,
      renderPasses: List.unmodifiable(passes),
      forwardCacheBytes: count(properties['demuxer-cache-state/fw-bytes']),
      forwardCacheSeconds: number(properties['demuxer-cache-duration']),
      avSyncSeconds: number(properties['avsync'], signed: true),
    );
  }
}

class VideoRenderPass {
  const VideoRenderPass({
    required this.name,
    this.lastMilliseconds,
    this.averageMilliseconds,
    this.peakMilliseconds,
  });
  final String name;
  final double? lastMilliseconds;
  final double? averageMilliseconds;
  final double? peakMilliseconds;
}

/// Optional capability: older/test engines can keep providing basic playback.
abstract interface class VideoStatsEngine {
  Future<VideoPlaybackStats> readPlaybackStats();
}

/// Owned by the information panel, never by the long-lived playback session.
/// One outstanding read at a time per binding; stale completions cannot publish
/// or schedule another timer after a media change, panel close or disposal.
class VideoStatsSampler extends ValueNotifier<VideoPlaybackStats> {
  VideoStatsSampler({this.interval = const Duration(seconds: 1)})
    : super(const VideoPlaybackStats());

  final Duration interval;
  VideoEngine? _engine;
  Object? _resourceKey;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;

  void bind(VideoEngine? engine, {Object? resourceKey}) {
    if (_disposed ||
        (identical(engine, _engine) && resourceKey == _resourceKey)) {
      return;
    }
    _engine = engine;
    _resourceKey = resourceKey;
    final generation = ++_generation;
    _timer?.cancel();
    value = const VideoPlaybackStats();
    if (engine is VideoStatsEngine) {
      unawaited(_sample(engine as VideoStatsEngine, generation));
    }
  }

  Future<void> _sample(VideoStatsEngine engine, int generation) async {
    VideoPlaybackStats snapshot;
    try {
      snapshot = await engine.readPlaybackStats();
    } catch (_) {
      // An optional read cannot fail playback or retain a stale observation.
      snapshot = const VideoPlaybackStats();
    }
    if (_disposed || generation != _generation) return;
    value = snapshot;
    // A listener may have rebound or disposed the sampler during publication.
    if (_disposed || generation != _generation) return;
    _timer = Timer(interval, () => unawaited(_sample(engine, generation)));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _engine = null;
    _resourceKey = null;
    super.dispose();
  }
}
