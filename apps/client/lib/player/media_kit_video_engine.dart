import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_engine.dart';

class MediaKitVideoEngine implements VideoEngine {
  MediaKitVideoEngine() {
    MediaKit.ensureInitialized();
    _player = Player(
      configuration: const PlayerConfiguration(title: 'ReelNest'),
    );
    _video = VideoController(_player);
    void publish(dynamic _) {
      if (!_disposed) _changes.add(clock);
    }

    _subscriptions.addAll([
      _player.stream.position.listen(publish),
      _player.stream.duration.listen(publish),
      _player.stream.playing.listen(publish),
      _player.stream.buffering.listen(publish),
      _player.stream.completed.listen(publish),
      _player.stream.volume.listen(publish),
      _player.stream.error.listen((error) {
        _error = error;
        publish(null);
      }),
    ]);
  }
  late final Player _player;
  late final VideoController _video;
  final _changes = StreamController<VideoClock>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  String? _error;
  bool _disposed = false;
  @override
  VideoClock get clock => VideoClock(
    position: _player.state.position,
    duration: _player.state.duration,
    playing: _player.state.playing,
    buffering: _player.state.buffering,
    completed: _player.state.completed,
    volume: _player.state.volume,
    error: _error,
  );
  @override
  Stream<VideoClock> get changes => _changes.stream;
  @override
  Future<void> open(String path, Duration start) async {
    _error = null;
    await _player.setVolume(80);
    await _player.open(Media(path, start: start), play: false);
    if (_player.state.duration <= Duration.zero) {
      await _player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 20));
    }
    if (_error != null) throw StateError(_error!);
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 100));
  @override
  Widget surface() =>
      Video(controller: _video, controls: NoVideoControls, wakelock: false);
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _changes.close();
  }
}
