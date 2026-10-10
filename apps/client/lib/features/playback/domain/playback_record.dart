import '../../../domain/media_source.dart';

class PlaybackRecord {
  const PlaybackRecord({
    required this.identity,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.watched = false,
    this.lastPlayedAt,
  });
  final MediaIdentity identity;
  final Duration position;
  final Duration duration;
  final bool watched;
  final DateTime? lastPlayedAt;

  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1)
      : 0;

  // MpvPlayerController.load: default rememberPlaybackPosition=true,
  // videoResumeRewindSeconds=5; only rewind positions strictly above 10s.
  Duration get resumePosition => resume();
  Duration resume({bool remember = true, double rewindSeconds = 5}) {
    if (!remember) return Duration.zero;
    final rewind = rewindSeconds.isFinite
        ? (rewindSeconds / 5).round().clamp(0, 6) * 5000
        : 0;
    final value = position.inMilliseconds > 10000
        ? position.inMilliseconds - rewind
        : position.inMilliseconds;
    return Duration(milliseconds: value.clamp(0, 1 << 53));
  }
}
