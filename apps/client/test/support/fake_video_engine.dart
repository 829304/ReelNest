import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reelnest/player/video_engine.dart';
import 'package:reelnest/player/video_tracks.dart';
import 'package:reelnest/player/video_timeline.dart';
import 'package:reelnest/player/video_subtitle_settings_engine.dart';
import 'package:reelnest/features/playback/domain/video_subtitle_settings.dart';

class FakeVideoEngine
    implements VideoEngine, VideoTimelineEngine, VideoSubtitleSettingsEngine {
  @override
  VideoSubtitleStyle subtitleStyle = VideoSubtitleStyle.standard;
  @override
  VideoTimingSettings timing = const VideoTimingSettings();
  @override
  Future<void> setSubtitleStyle(VideoSubtitleStyle style) async {
    _checkControl();
    subtitleStyle = style.normalized;
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    _checkControl();
    timing = timing.copyWith(audioDelay: seconds);
  }

  @override
  Future<void> setSubtitleScale(double scale) async {
    _checkControl();
    timing = timing.copyWith(subtitleScale: scale);
  }

  @override
  Future<void> setSubtitlePosition(double position) async {
    _checkControl();
    timing = timing.copyWith(subtitlePosition: position);
  }

  List<VideoChapter> chapterList = const [];
  final chapterEvents = StreamController<List<VideoChapter>>.broadcast(
    sync: true,
  );
  bool loopCurrentItem = false;
  bool failChapters = false;
  Duration? abStart;
  Duration? abEnd;
  final frameSteps = <bool>[];
  @override
  List<VideoChapter> get chapters => chapterList;
  @override
  Stream<List<VideoChapter>> get chapterChanges => chapterEvents.stream;
  @override
  Future<void> refreshChapters() async {
    if (failChapters) throw StateError('Chapter read failure');
  }

  @override
  Future<void> setLoopCurrentItem(bool enabled) async {
    _checkControl();
    loopCurrentItem = enabled;
  }

  @override
  Future<void> setABLoop(Duration? start, Duration? end) async {
    _checkControl();
    abStart = start;
    abEnd = end;
  }

  @override
  Future<void> stepFrame({required bool backward}) async {
    _checkControl();
    frameSteps.add(backward);
    emit(
      playing: false,
      position: clock.position + Duration(milliseconds: backward ? -40 : 40),
    );
  }

  final events = StreamController<VideoClock>.broadcast(sync: true);
  VideoClock value = const VideoClock();
  Duration? openedAt;
  String? openedPath;
  int disposals = 0;
  bool failOpen = false;
  bool failCommand = false;
  bool failControl = false;
  bool pitchCorrection = true;
  final trackEvents = StreamController<VideoTrackState>.broadcast(sync: true);
  VideoTrackState trackState = const VideoTrackState();
  final addedSubtitles = <String>[];
  @override
  VideoTrackState get tracks => trackState;
  @override
  Stream<VideoTrackState> get trackChanges => trackEvents.stream;
  void emitTracks({
    List<VideoTrack>? audio,
    List<VideoTrack>? subtitles,
    int? audioId,
    int? subtitleId,
    int? secondaryId,
    bool clearAudio = false,
    bool clearSubtitle = false,
    bool clearSecondary = false,
    bool? auto,
    double? delay,
    double? boost,
    String? device,
  }) {
    trackState = VideoTrackState(
      audio: audio ?? tracks.audio,
      subtitles: subtitles ?? tracks.subtitles,
      audioId: clearAudio ? null : audioId ?? tracks.audioId,
      subtitleId: clearSubtitle ? null : subtitleId ?? tracks.subtitleId,
      secondarySubtitleId: clearSecondary
          ? null
          : secondaryId ?? tracks.secondarySubtitleId,
      autoSubtitles: auto ?? tracks.autoSubtitles,
      subtitleDelay: delay ?? tracks.subtitleDelay,
      volumeBoost: boost ?? tracks.volumeBoost,
      devices: tracks.devices,
      audioDevice: device ?? tracks.audioDevice,
    );
    trackEvents.add(trackState);
  }

  void _checkControl() {
    if (failControl) throw StateError('track command failed');
  }

  @override
  Future<void> refreshTracks() async => trackEvents.add(tracks);
  @override
  Future<void> selectAudio(int? id) async {
    _checkControl();
    emitTracks(audioId: id, clearAudio: id == null);
  }

  @override
  Future<void> selectSubtitle(int? id) async {
    _checkControl();
    emitTracks(
      subtitleId: id,
      clearSubtitle: id == null,
      clearSecondary: id != null && id == tracks.secondarySubtitleId,
    );
  }

  @override
  Future<void> selectSecondarySubtitle(int? id) async {
    _checkControl();
    emitTracks(secondaryId: id, clearSecondary: id == null);
  }

  @override
  Future<void> enableAutoSubtitles() async {
    _checkControl();
    emitTracks(auto: true);
  }

  @override
  Future<void> addSubtitle(String path) async {
    _checkControl();
    addedSubtitles.add(path);
  }

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    _checkControl();
    timing = timing.copyWith(subtitleDelay: seconds);
    emitTracks(delay: seconds);
  }

  @override
  Future<void> setVolumeBoost(double boost) async {
    _checkControl();
    emitTracks(boost: boost);
  }

  @override
  Future<void> setAudioDevice(String name) async {
    _checkControl();
    emitTracks(device: name);
  }

  @override
  VideoClock get clock => value;
  @override
  Stream<VideoClock> get changes => events.stream;
  void emit({
    Duration? position,
    bool? playing,
    bool? completed,
    String? error,
    double? rate,
    int? networkBytesPerSecond,
    bool clearNetworkSpeed = false,
  }) {
    value = VideoClock(
      position: position ?? value.position,
      duration: const Duration(seconds: 100),
      playing: playing ?? value.playing,
      completed: completed ?? value.completed,
      volume: value.volume,
      rate: rate ?? value.rate,
      error: error,
      networkBytesPerSecond: clearNetworkSpeed
          ? null
          : networkBytesPerSecond ?? value.networkBytesPerSecond,
    );
    events.add(value);
  }

  @override
  Future<void> open(String path, Duration start) async {
    openedAt = start;
    openedPath = path;
    if (failOpen) throw StateError('decoder failed');
    emit(position: start, playing: false, completed: false);
  }

  @override
  Future<void> pause() async => emit(playing: false);
  @override
  Future<void> play() async {
    if (failCommand) throw StateError('native command failed');
    emit(playing: true);
  }

  @override
  Future<void> seek(Duration position) async =>
      emit(position: position, completed: false);
  @override
  Future<void> setVolume(double volume) async {
    value = VideoClock(
      position: value.position,
      duration: value.duration,
      playing: value.playing,
      completed: value.completed,
      volume: volume,
      rate: value.rate,
      networkBytesPerSecond: value.networkBytesPerSecond,
    );
    events.add(value);
  }

  @override
  Future<void> setRate(double rate) async {
    _checkControl();
    emit(rate: rate);
  }

  @override
  Future<void> setPitchCorrection(bool enabled) async {
    _checkControl();
    pitchCorrection = enabled;
  }

  @override
  Widget surface() => const ColoredBox(color: Color(0xff101010));
  @override
  Future<void> dispose() async {
    disposals++;
    await events.close();
    await trackEvents.close();
    await chapterEvents.close();
  }
}
