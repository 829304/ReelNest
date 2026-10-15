import 'dart:async';

import '../domain/video_frame_preview.dart';

/// One decoder at a time. Interactive requests precede speculative neighbors.
/// Cancellation abandons only that subscriber, not another same-key caller.
class VideoFramePreviewCache {
  VideoFramePreviewCache({
    required this.generate,
    this.maxEntries = 160,
    this.maxBytes = 32 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 9),
    this.prefetchDelay = const Duration(milliseconds: 180),
  }) : assert(maxEntries > 0),
       assert(maxBytes > 0);
  final VideoPreviewGenerator generate;
  final int maxEntries;
  final int maxBytes;
  final Duration requestTimeout;
  final Duration prefetchDelay;
  final _cache = <Duration, VideoPreviewFrame>{};
  final _jobs = <Duration, _PreviewJob>{};
  VideoPreviewResource? _resource;
  _PreviewJob? _active;
  Timer? _prefetch;
  bool _prefetching = false;
  int _bytes = 0;
  bool _disposed = false;
  int get cachedCount => _cache.length;
  int get cachedBytes => _bytes;

  void attach(VideoPreviewResource? resource) {
    _resource = resource;
    _prefetch?.cancel();
    _cache.clear();
    _bytes = 0;
    for (final job in _jobs.values.toList()) {
      job.cancellation.cancel();
      if (!job.result.isCompleted) {
        job.result.complete(null);
      }
    }
    _jobs.clear();
    // An abandoned decoder still owns the gate until its cleanup completes.
  }

  VideoPreviewFrame? cached({
    required Duration time,
    required Duration duration,
    required bool coarse,
  }) {
    if (_disposed || _resource == null || duration <= Duration.zero) {
      return null;
    }
    final key = VideoPreviewBuckets.sample(
      time: time,
      duration: duration,
      coarse: coarse,
    );
    final frame = _cache.remove(key);
    if (frame != null) _cache[key] = frame;
    return frame;
  }

  Future<VideoPreviewFrame?> request({
    required Duration time,
    required Duration duration,
    required bool coarse,
    VideoPreviewCancellation? cancellation,
    bool prefetch = false,
  }) async {
    final resource = _resource;
    if (_disposed ||
        resource == null ||
        duration <= Duration.zero ||
        cancellation?.isCancelled == true) {
      return null;
    }
    final key = VideoPreviewBuckets.sample(
      time: time,
      duration: duration,
      coarse: coarse,
    );
    if (key < resource.offset) return null;
    final hit = cached(time: time, duration: duration, coarse: coarse);
    final frame =
        hit ??
        await _subscribe(resource, key, cancellation, speculative: false);
    if (_resource != resource ||
        cancellation?.isCancelled == true ||
        _disposed) {
      return null;
    }
    if (prefetch && frame != null) {
      _scheduleNeighbors(resource, time, duration, coarse);
    }
    return frame;
  }

  Future<VideoPreviewFrame?> _subscribe(
    VideoPreviewResource resource,
    Duration key,
    VideoPreviewCancellation? cancellation, {
    required bool speculative,
  }) async {
    var job = _jobs[key];
    if (job == null) {
      // A pointer sweep must not build an unbounded backlog. At most two
      // speculative neighbors, or four interactive requests, may wait.
      final pending = _jobs.values.where((j) => j != _active).toList();
      if (pending.length >= 4 || (speculative && pending.length >= 2)) {
        return null;
      }
      job = _PreviewJob(resource, key, speculative);
      _jobs[key] = job;
    }
    if (!speculative) job.speculative = false;
    job.subscribers++;
    _pump();
    final timeout = VideoPreviewCancellation();
    final timer = Timer(requestTimeout, timeout.cancel);
    try {
      return await Future.any<VideoPreviewFrame?>([
        job.result.future,
        timeout.whenCancelled.then((_) => null),
        if (cancellation != null) cancellation.whenCancelled.then((_) => null),
      ]);
    } finally {
      timer.cancel();
      job.subscribers--;
      if (job.subscribers == 0 && !job.result.isCompleted) {
        job.cancellation.cancel();
        job.result.complete(null);
        if (_jobs[key] == job) _jobs.remove(key);
      }
    }
  }

  void _pump() {
    if (_active != null || _disposed) return;
    final waiting =
        _jobs.values.where((j) => !j.cancellation.isCancelled).toList()..sort(
          (a, b) => (a.speculative ? 1 : 0).compareTo(b.speculative ? 1 : 0),
        );
    if (waiting.isEmpty) return;
    final job = _active = waiting.first;
    unawaited(_run(job));
  }

  Future<void> _run(_PreviewJob job) async {
    VideoPreviewFrame? frame;
    try {
      final bytes = await generate(job.resource, job.key, job.cancellation);
      if (!_disposed &&
          _resource == job.resource &&
          !job.cancellation.isCancelled &&
          bytes != null &&
          bytes.isNotEmpty &&
          bytes.length <= 1024 * 1024) {
        frame = VideoPreviewFrame(bytes, job.key);
        if (frame.memoryCost <= maxBytes) {
          final old = _cache.remove(job.key);
          _bytes -= old?.memoryCost ?? 0;
          _cache[job.key] = frame;
          _bytes += frame.memoryCost;
          while (_cache.length > maxEntries || _bytes > maxBytes) {
            _bytes -= _cache.remove(_cache.keys.first)!.memoryCost;
          }
        }
      }
    } catch (_) {
      // Auxiliary preview failures never become session/control errors.
    } finally {
      if (!job.result.isCompleted) job.result.complete(frame);
      if (_jobs[job.key] == job) _jobs.remove(job.key);
      _active = null;
      _pump();
    }
  }

  void _scheduleNeighbors(
    VideoPreviewResource resource,
    Duration time,
    Duration duration,
    bool coarse,
  ) {
    if (_prefetching) return;
    _prefetch?.cancel();
    _prefetch = Timer(prefetchDelay, () async {
      _prefetching = true;
      try {
        final step = Duration(
          microseconds:
              (VideoPreviewBuckets.interval(duration, coarse: coarse) * 1000000)
                  .round(),
        );
        for (final target in [time + step, time - step]) {
          if (_disposed || _resource != resource) return;
          if (target < Duration.zero || target > duration) continue;
          final key = VideoPreviewBuckets.sample(
            time: target,
            duration: duration,
            coarse: coarse,
          );
          if (key < resource.offset || _cache.containsKey(key)) continue;
          await _subscribe(resource, key, null, speculative: true);
        }
      } finally {
        _prefetching = false;
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    attach(null);
  }
}

class _PreviewJob {
  _PreviewJob(this.resource, this.key, this.speculative);
  final VideoPreviewResource resource;
  final Duration key;
  bool speculative;
  int subscribers = 0;
  final cancellation = VideoPreviewCancellation();
  final result = Completer<VideoPreviewFrame?>();
}
