import 'dart:async';
import 'dart:convert';

import 'playback_diagnostics.dart';

class VideoLoadSnapshot {
  const VideoLoadSnapshot({
    required this.idle,
    this.duration = Duration.zero,
    this.hasVideo = false,
    this.hasAudio = false,
  });
  final bool idle;
  final Duration duration;
  final bool hasVideo, hasAudio;
  bool get ready => !idle && (duration > Duration.zero || hasVideo || hasAudio);
}

/// Uses decoder parameters when total duration is unavailable. Property reads
/// are guarded between awaits so a cancelled engine cannot start more commands.
Future<VideoLoadSnapshot> readVideoLoadSnapshot({
  required Future<String> Function(String) property,
  required Duration Function() duration,
  required void Function() checkAlive,
}) async {
  checkAlive();
  final idle = await property('idle-active');
  checkAlive();
  final length = duration();
  if (idle == 'yes' || length > Duration.zero) {
    return VideoLoadSnapshot(idle: idle == 'yes', duration: length);
  }
  final video = await property('video-params');
  checkAlive();
  final audio = await property('audio-params');
  checkAlive();
  Map? decode(String raw) {
    if (raw.isEmpty) return null;
    final value = jsonDecode(raw);
    return value is Map ? value : null;
  }

  final v = decode(video);
  final a = decode(audio);
  return VideoLoadSnapshot(
    idle: false,
    duration: length,
    hasVideo: v?['w'] is num && v?['h'] is num && v!['w'] > 0 && v['h'] > 0,
    hasAudio: a?['samplerate'] is num && a!['samplerate'] > 0,
  );
}

/// A single opening budget and explicit cancellation, including property reads.
/// Does not assume every valid stream advertises a total duration.
class VideoLoadMonitor {
  VideoLoadMonitor({this.timeout = const Duration(seconds: 20)});
  final Duration timeout;
  final _cancelled = Completer<void>();
  bool get cancelled => _cancelled.isCompleted;
  void cancel() {
    if (!cancelled) _cancelled.complete();
  }

  Future<void> wait({
    required Future<VideoLoadSnapshot> Function() read,
    required PlaybackIssue? Function() backendIssue,
    Duration interval = const Duration(milliseconds: 100),
  }) async {
    final expired = Completer<void>();
    final timer = Timer(timeout, () => expired.complete());
    Future<T> guarded<T>(Future<T> work) async {
      if (cancelled) throw const PlaybackIssue('cancelled');
      final result = await Future.any<T>([
        work,
        _cancelled.future.then<T>(
          (_) => throw const PlaybackIssue('cancelled'),
        ),
        expired.future.then<T>((_) => throw const PlaybackIssue('timeout')),
      ]);
      if (cancelled) throw const PlaybackIssue('cancelled');
      return result;
    }

    try {
      while (true) {
        if (cancelled) throw const PlaybackIssue('cancelled');
        final snapshot = await guarded(read());
        // A decoder can log an error while falling back to another decoder.
        // A valid active stream wins; an error alone is not a terminal event.
        if (snapshot.ready) return;
        final issue = backendIssue();
        if (snapshot.idle && issue != null) throw issue;
        await guarded(Future<void>.delayed(interval));
      }
    } finally {
      timer.cancel();
    }
  }
}
