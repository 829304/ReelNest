import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/player/video_playback_stats.dart';

import 'support/fake_video_engine.dart';

class _StatsEngine extends FakeVideoEngine implements VideoStatsEngine {
  int reads = 0;
  Future<VideoPlaybackStats> Function()? read;

  @override
  Future<VideoPlaybackStats> readPlaybackStats() {
    ++reads;
    return read?.call() ??
        Future.value(const VideoPlaybackStats(estimatedFps: 24));
  }
}

void main() {
  test('native values keep zero, signed sync and actual software decoding', () {
    final stats = VideoPlaybackStats.fromMpv({
      'estimated-vf-fps': 23.976,
      'decoder-frame-drop-count': 0,
      'frame-drop-count': 4,
      'hwdec-current': 'no',
      'demuxer-cache-state/fw-bytes': 0,
      'demuxer-cache-duration': 0.0,
      'avsync': -.012,
      'vo-delayed-frame-count': 600,
      'hwdec': 'auto',
    });
    expect(stats.estimatedFps, 23.976);
    expect(stats.decoderDroppedFrames, 0);
    expect(stats.outputDroppedFrames, 4);
    expect(stats.hardwareDecoder, 'no');
    expect(stats.forwardCacheBytes, 0);
    expect(stats.forwardCacheSeconds, 0);
    expect(stats.avSyncSeconds, -.012);
  });

  test('unavailable, malformed and non-finite properties remain unknown', () {
    final stats = VideoPlaybackStats.fromMpv({
      'estimated-vf-fps': double.nan,
      'decoder-frame-drop-count': -1,
      'frame-drop-count': '0',
      'hwdec-current': 'https://private.example/token',
      'demuxer-cache-state/fw-bytes': 1.5,
      'demuxer-cache-duration': double.infinity,
      'avsync': double.negativeInfinity,
    });
    expect(stats.estimatedFps, isNull);
    expect(stats.decoderDroppedFrames, isNull);
    expect(stats.outputDroppedFrames, isNull);
    expect(stats.hardwareDecoder, isNull);
    expect(stats.forwardCacheBytes, isNull);
    expect(stats.forwardCacheSeconds, isNull);
    expect(stats.avSyncSeconds, isNull);
    expect(stats.renderPasses, isEmpty);
    expect(
      VideoPlaybackStats.fromMpv({'hwdec': 'auto'}).hardwareDecoder,
      isNull,
    );
    expect(VideoPlaybackStats.fromMpv({'avsync': .02}).avSyncSeconds, .02);
  });

  test(
    'variable render passes convert nanoseconds and preserve missing metrics',
    () {
      final stats = VideoPlaybackStats.fromMpv({
        'vo-passes': {
          'fresh': [
            {
              'desc': 'Upload',
              'last': 1250000,
              'avg': 1000000,
              'peak': 3000000,
            },
            {'desc': 'Scale', 'last': 0, 'avg': -1},
            {
              'desc': 'No timing',
              'samples': [5],
            },
            'malformed',
          ],
          'redraw': [
            {'desc': 'Present\nframe', 'avg': 500000},
          ],
        },
      });
      expect(stats.renderPasses, hasLength(3));
      expect(stats.renderPasses.first.name, 'fresh · Upload');
      expect(stats.renderPasses.first.lastMilliseconds, 1.25);
      expect(stats.renderPasses.first.averageMilliseconds, 1);
      expect(stats.renderPasses.first.peakMilliseconds, 3);
      expect(stats.renderPasses[1].lastMilliseconds, 0);
      expect(stats.renderPasses[1].averageMilliseconds, isNull);
      expect(stats.renderPasses.last.name, 'redraw · Present frame');
      expect(stats.renderPasses.last.lastMilliseconds, isNull);
      expect(() => stats.renderPasses.clear(), throwsUnsupportedError);
    },
  );

  testWidgets('binding samples once per second and stops when hidden', (
    tester,
  ) async {
    final engine = _StatsEngine();
    final sampler = VideoStatsSampler();
    sampler.bind(engine, resourceKey: 'a');
    await tester.pump();
    expect(engine.reads, 1);
    expect(sampler.value.estimatedFps, 24);
    // Clock notifications/repeated bindings must not reschedule the sampler.
    sampler.bind(engine, resourceKey: 'a');
    await tester.pump(const Duration(milliseconds: 999));
    expect(engine.reads, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.reads, 2);
    sampler.bind(null);
    expect(sampler.value.estimatedFps, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(engine.reads, 2);
    sampler.dispose();
    await engine.dispose();
  });

  testWidgets('late old-media reads cannot publish or schedule more reads', (
    tester,
  ) async {
    final old = _StatsEngine();
    final current = _StatsEngine();
    final pending = Completer<VideoPlaybackStats>();
    old.read = () => pending.future;
    final sampler = VideoStatsSampler();
    sampler.bind(old, resourceKey: 'old');
    sampler.bind(current, resourceKey: 'new');
    await tester.pump();
    expect(sampler.value.estimatedFps, 24);
    pending.complete(const VideoPlaybackStats(estimatedFps: 999));
    await tester.pump();
    expect(sampler.value.estimatedFps, 24);
    await tester.pump(const Duration(seconds: 1));
    expect(old.reads, 1);
    expect(current.reads, 2);
    sampler.dispose();
    await old.dispose();
    await current.dispose();
  });

  testWidgets('resource change clears counts even on the same engine', (
    tester,
  ) async {
    final engine = _StatsEngine();
    engine.read = () async =>
        const VideoPlaybackStats(decoderDroppedFrames: 30);
    final sampler = VideoStatsSampler();
    sampler.bind(engine, resourceKey: 'a');
    await tester.pump();
    expect(sampler.value.decoderDroppedFrames, 30);
    final next = Completer<VideoPlaybackStats>();
    engine.read = () => next.future;
    sampler.bind(engine, resourceKey: 'b');
    expect(sampler.value.decoderDroppedFrames, isNull);
    await tester.pump(const Duration(seconds: 3));
    expect(engine.reads, 2, reason: 'Do not overlap a slow sample');
    sampler.dispose();
    next.complete(const VideoPlaybackStats(decoderDroppedFrames: 0));
    await tester.pump(const Duration(seconds: 3));
    expect(engine.reads, 2);
    await engine.dispose();
  });

  testWidgets('read failure clears stale values and remains retryable', (
    tester,
  ) async {
    final engine = _StatsEngine();
    final sampler = VideoStatsSampler();
    sampler.bind(engine);
    await tester.pump();
    expect(sampler.value.estimatedFps, 24);
    engine.read = () => throw StateError('Unavailable native property');
    await tester.pump(const Duration(seconds: 1));
    expect(sampler.value.estimatedFps, isNull);
    engine.read = null;
    await tester.pump(const Duration(seconds: 1));
    expect(sampler.value.estimatedFps, 24);
    sampler.dispose();
    await engine.dispose();
  });

  testWidgets(
    'unsupported engine stays idle and pending failures are handled after close',
    (tester) async {
      final plain = FakeVideoEngine();
      final engine = _StatsEngine();
      final pending = Completer<VideoPlaybackStats>();
      engine.read = () => pending.future;
      final sampler = VideoStatsSampler();
      sampler.bind(plain);
      await tester.pump(const Duration(seconds: 5));
      expect(sampler.value.estimatedFps, isNull);
      sampler.bind(engine);
      sampler.dispose();
      pending.completeError(StateError('Engine was released'));
      await tester.pump(const Duration(seconds: 5));
      expect(engine.reads, 1);
      await plain.dispose();
      await engine.dispose();
    },
  );
}
