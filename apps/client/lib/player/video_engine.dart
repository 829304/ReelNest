import 'package:flutter/widgets.dart';

import 'video_tracks.dart';

class VideoClock {
  const VideoClock({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.volume = 80,
    this.rate = 1,
    this.warning,
    this.error,
    this.networkBytesPerSecond,
  });
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;
  final double volume;
  final double rate;
  final String? warning;
  final String? error;

  /// Estimated input bytes/second for an online stream. Null for local files,
  /// offline copies, unsupported backends or a not-yet-available sample.
  final int? networkBytesPerSecond;
}

abstract interface class VideoEngine {
  VideoClock get clock;
  Stream<VideoClock> get changes;
  VideoTrackState get tracks;
  Stream<VideoTrackState> get trackChanges;
  Future<void> refreshTracks();
  Future<void> selectAudio(int? id);
  Future<void> selectSubtitle(int? id);
  Future<void> selectSecondarySubtitle(int? id);
  Future<void> enableAutoSubtitles();
  Future<void> addSubtitle(String path);
  Future<void> setSubtitleDelay(double seconds);
  Future<void> setVolumeBoost(double boost);
  Future<void> setAudioDevice(String name);

  /// Prepare a decoded resource at [start] while paused. The session starts
  /// playback only after committing the surface and applying preferences.
  Future<void> open(String path, Duration start);
  Future<void> pause();
  Future<void> play();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setPitchCorrection(bool enabled);
  Future<void> dispose();
  Widget surface();
}

/// Optional decoded-video geometry exposed by engines that can report it.
abstract interface class VideoAspectEngine {
  double? get videoAspectRatio;
}
