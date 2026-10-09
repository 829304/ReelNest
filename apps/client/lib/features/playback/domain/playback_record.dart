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
  Duration get resumePosition => position > const Duration(seconds: 10)
      ? position - const Duration(seconds: 5)
      : position;
}
