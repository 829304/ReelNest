import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reelnest/player/video_engine.dart';

class FakeVideoEngine implements VideoEngine {
  final events = StreamController<VideoClock>.broadcast(sync: true);
  VideoClock value = const VideoClock();
  Duration? openedAt;
  String? openedPath;
  int disposals = 0;
  bool failOpen = false;
  bool failCommand = false;
  @override
  VideoClock get clock => value;
  @override
  Stream<VideoClock> get changes => events.stream;
  void emit({
    Duration? position,
    bool? playing,
    bool completed = false,
    String? error,
  }) {
    value = VideoClock(
      position: position ?? value.position,
      duration: const Duration(seconds: 100),
      playing: playing ?? value.playing,
      completed: completed,
      volume: value.volume,
      error: error,
    );
    events.add(value);
  }

  @override
  Future<void> open(String path, Duration start) async {
    openedAt = start;
    openedPath = path;
    if (failOpen) throw StateError('decoder failed');
    emit(position: start, playing: true);
  }

  @override
  Future<void> pause() async => emit(playing: false);
  @override
  Future<void> play() async {
    if (failCommand) throw StateError('native command failed');
    emit(playing: true);
  }

  @override
  Future<void> seek(Duration position) async => emit(position: position);
  @override
  Future<void> setVolume(double volume) async {
    value = VideoClock(
      position: value.position,
      duration: value.duration,
      playing: value.playing,
      volume: volume,
    );
    events.add(value);
  }

  @override
  Widget surface() => const ColoredBox(color: Color(0xff101010));
  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
  }
}
