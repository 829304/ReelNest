import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:reelnest/player/video_engine.dart';
import 'package:reelnest/player/video_tracks.dart';

class FakeVideoEngine implements VideoEngine {
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
  }) {
    value = VideoClock(
      position: position ?? value.position,
      duration: const Duration(seconds: 100),
      playing: playing ?? value.playing,
      completed: completed ?? value.completed,
      volume: value.volume,
      rate: rate ?? value.rate,
      error: error,
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
  }
}
