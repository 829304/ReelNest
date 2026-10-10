import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'video_engine.dart';
import 'video_tracks.dart';
import '../platform/playback_sleep_guard.dart';

class MediaKitVideoEngine implements VideoEngine {
  MediaKitVideoEngine({Player? player}) {
    MediaKit.ensureInitialized();
    _player =
        player ??
        Player(
          configuration: const PlayerConfiguration(
            title: 'ReelNest',
            libass: true,
          ),
        );
    _video = VideoController(_player);
    _sleep = PlaybackSleepGuard((warning) {
      if (!_disposed) {
        _warning = warning;
        _changes.add(clock);
      }
    });
    void publish(dynamic _) {
      if (!_disposed) {
        _sleep.update(
          _player.state.playing && !_player.state.completed && _error == null,
        );
        _changes.add(clock);
      }
    }

    _subscriptions.addAll([
      _player.stream.position.listen(publish),
      _player.stream.duration.listen(publish),
      _player.stream.playing.listen(publish),
      _player.stream.buffering.listen(publish),
      _player.stream.completed.listen(publish),
      _player.stream.volume.listen(publish),
      _player.stream.rate.listen(publish),
      _player.stream.tracks.listen((_) => _scheduleRefresh()),
      _player.stream.track.listen((_) => _scheduleRefresh()),
      _player.stream.audioDevices.listen((_) => _scheduleRefresh()),
      _player.stream.audioDevice.listen((_) => _scheduleRefresh()),
      _player.stream.error.listen((error) {
        // libmpv reports a rejected external subtitle through the same log
        // stream as decoder failures. addSubtitle verifies its new track and
        // reports that rejection separately; the playing video stays valid.
        if (error.startsWith('Can not open external file ')) return;
        _error = _networkResource ? '远程视频无法解码或连接中断。' : error;
        publish(null);
      }),
    ]);
  }
  late final Player _player;
  late final VideoController _video;
  late final PlaybackSleepGuard _sleep;
  String? _warning;
  final _changes = StreamController<VideoClock>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  String? _error;
  bool _networkResource = false;
  bool _disposed = false;
  double _boost = 1;
  double _volume = 80;
  Future<void> _refreshing = Future.value();
  final _trackChanges = StreamController<VideoTrackState>.broadcast();
  VideoTrackState _tracks = const VideoTrackState();
  NativePlayer get _native => _player.platform as NativePlayer;
  @override
  VideoTrackState get tracks => _tracks;
  @override
  Stream<VideoTrackState> get trackChanges => _trackChanges.stream;
  void _scheduleRefresh() {
    if (_disposed) return;
    unawaited(refreshTracks().catchError((Object _) {}));
  }

  @override
  Future<void> refreshTracks() {
    final next = _refreshing.then((_) async {
      if (_disposed) return;
      final raw = await _native.getProperty('track-list');
      final list = raw.isEmpty ? <dynamic>[] : jsonDecode(raw) as List;
      final available = list
          .whereType<Map>()
          .where((t) => t['type'] == 'audio' || t['type'] == 'sub')
          .map((t) => VideoTrack.fromMpv(Map<String, dynamic>.from(t)))
          .toList();
      final audioId = int.tryParse(await _native.getProperty('aid'));
      final subtitleId = int.tryParse(await _native.getProperty('sid'));
      final secondaryId = int.tryParse(
        await _native.getProperty('secondary-sid'),
      );
      final auto = await _native.getProperty('sub-auto');
      final delay =
          double.tryParse(await _native.getProperty('sub-delay')) ?? 0;
      if (_disposed) return;
      _tracks = VideoTrackState(
        audio: available
            .where((t) => t.type == 'audio')
            .toList(growable: false),
        subtitles: available
            .where((t) => t.type == 'sub')
            .toList(growable: false),
        audioId: audioId,
        subtitleId: subtitleId,
        secondarySubtitleId: secondaryId,
        autoSubtitles: auto != 'no' && auto.isNotEmpty,
        subtitleDelay: delay,
        volumeBoost: _boost,
        devices: _player.state.audioDevices
            .map((d) => VideoAudioDevice(d.name, d.description))
            .toList(growable: false),
        audioDevice: _player.state.audioDevice.name,
      );
      _trackChanges.add(_tracks);
    });
    _refreshing = next.catchError((Object _) {});
    return next;
  }

  Future<void> _set(String property, String value) =>
      _native.command(['set', property, value]);
  Future<void> _select(String property, int? id, String fallback) async {
    await _set(property, id?.toString() ?? fallback);
    if (id != null && int.tryParse(await _native.getProperty(property)) != id) {
      throw StateError('Track selection rejected');
    }
  }

  @override
  Future<void> selectAudio(int? id) async {
    await _select('aid', id, 'auto');
    await refreshTracks();
  }

  @override
  Future<void> selectSubtitle(int? id) async {
    if (id != null && id == tracks.secondarySubtitleId) {
      await _set('secondary-sid', 'no');
    }
    await _select('sid', id, 'no');
    await _set('sub-visibility', id == null ? 'no' : 'yes');
    await refreshTracks();
  }

  @override
  Future<void> selectSecondarySubtitle(int? id) async {
    await _select('secondary-sid', id, 'no');
    if (id != null) await _set('secondary-sub-visibility', 'yes');
    await refreshTracks();
  }

  @override
  Future<void> enableAutoSubtitles() async {
    await _set('sub-auto', 'fuzzy');
    await _native.command(['rescan-external-files']);
    await _set('sub-visibility', 'yes');
    await refreshTracks();
  }

  @override
  Future<void> addSubtitle(String path) async {
    if (!await File(path).exists()) {
      throw StateError('Subtitle file unavailable');
    }
    await _native.command(['sub-add', path, 'select']);
    await _set('sub-visibility', 'yes');
    await refreshTracks();
    if (!tracks.subtitles.any(
      (t) =>
          t.external &&
          t.id == tracks.subtitleId &&
          t.externalFilename != null &&
          p.equals(t.externalFilename!, path),
    )) {
      throw StateError('Subtitle load rejected');
    }
  }

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    await _set('sub-delay', seconds.toString());
    await refreshTracks();
  }

  @override
  Future<void> setVolumeBoost(double boost) async {
    final volume = clock.volume;
    _boost = boost.clamp(1, 2);
    await setVolume(volume);
    await refreshTracks();
  }

  @override
  Future<void> setAudioDevice(String name) async {
    await _set('audio-device', name);
    if (await _native.getProperty('audio-device') != name) {
      throw StateError('Audio device selection rejected');
    }
    await refreshTracks();
  }

  @override
  VideoClock get clock => VideoClock(
    position: _player.state.position,
    duration: _player.state.duration,
    playing: _player.state.playing,
    buffering: _player.state.buffering,
    completed: _player.state.completed,
    volume: _volume,
    rate: _player.state.rate,
    error: _error,
    warning: _warning,
  );
  @override
  Stream<VideoClock> get changes => _changes.stream;
  @override
  Future<void> open(String path, Duration start) async {
    _error = null;
    _networkResource = ['http', 'https'].contains(Uri.tryParse(path)?.scheme);
    await _set('sub-auto', 'fuzzy');
    await _set('volume-max', '200');
    await setVolume(80);
    await _player.open(Media(path, start: start), play: false);
    if (_player.state.duration <= Duration.zero) {
      await _player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 20));
    }
    if (_error != null) throw StateError(_error!);
    await refreshTracks();
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate.clamp(.5, 3));
  @override
  Future<void> setPitchCorrection(bool enabled) =>
      _set('audio-pitch-correction', enabled ? 'yes' : 'no');
  @override
  Future<void> setVolume(double volume) async {
    final level = volume.clamp(0.0, 100.0);
    await _player.setVolume(level * _boost);
    // mpv's volume observation is asynchronous. Preserve the logical level
    // before the next boost command instead of reading the previous event.
    _volume = level;
    if (!_disposed) _changes.add(clock);
  }

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
    await _sleep.dispose();
    await _refreshing;
    await _player.dispose();
    await _changes.close();
    await _trackChanges.close();
  }
}
