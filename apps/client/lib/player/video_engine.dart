import 'package:flutter/widgets.dart';

class VideoClock {
  const VideoClock({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.volume = 80,
    this.error,
  });
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;
  final double volume;
  final String? error;
}

abstract interface class VideoEngine {
  VideoClock get clock;
  Stream<VideoClock> get changes;
  Future<void> open(String path, Duration start);
  Future<void> pause();
  Future<void> play();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
  Widget surface();
}
