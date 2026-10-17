import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide VideoTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'video_engine.dart';
import 'video_tracks.dart';
import 'video_timeline.dart';
import 'playback_diagnostics.dart';
import 'video_load_monitor.dart';
import 'video_network_speed.dart';
import 'video_subtitle_settings_engine.dart';
import 'video_playback_stats.dart';
import 'mpv_playback_stats_reader.dart';
import 'video_display_settings_engine.dart';
import 'mpv_node_property.dart';
import '../features/playback/domain/video_display_settings.dart';
import '../features/playback/domain/video_subtitle_settings.dart';
import '../platform/playback_sleep_guard.dart';

class MediaKitVideoEngine
    implements
        VideoEngine,
        VideoTimelineEngine,
        VideoAspectEngine,
        VideoSubtitleSettingsEngine,
        VideoStatsEngine,
        VideoDisplayEngine,
        DiagnosableVideoEngine {
  MediaKitVideoEngine({
    Player? player,
    VideoControllerConfiguration videoConfiguration =
        const VideoControllerConfiguration(),
  }) {
    MediaKit.ensureInitialized();
    _player =
        player ??
        Player(
          configuration: const PlayerConfiguration(
            title: 'ReelNest',
            libass: true,
            logLevel: MPVLogLevel.warn,
          ),
        );
    _video = VideoController(_player, configuration: videoConfiguration);
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

    _publish = publish;
    _subscriptions.addAll([
      _player.stream.position.listen(publish),
      _player.stream.duration.listen(publish),
      _player.stream.playing.listen(publish),
      _player.stream.buffering.listen(publish),
      _player.stream.completed.listen(publish),
      _player.stream.volume.listen(publish),
      _player.stream.rate.listen(publish),
      _player.stream.videoParams.listen((_) {
        // media_kit_video 2.0.1 resets its native output to source dimensions
        // on parameter changes. Reassert the viewport after that update.
        _viewportReset = true;
        _scheduleViewport();
        publish(null);
      }),
      _player.stream.tracks.listen((_) => _scheduleRefresh()),
      _player.stream.track.listen((_) => _scheduleRefresh()),
      _player.stream.audioDevices.listen((_) => _scheduleRefresh()),
      _player.stream.audioDevice.listen((_) => _scheduleRefresh()),
      _player.stream.error.listen((error) {
        // libmpv reports a rejected external subtitle through the same log
        // stream as decoder failures. addSubtitle verifies its new track and
        // reports that rejection separately; the playing video stays valid.
        if (error.startsWith('Can not open external file ')) return;
        _backendIssue = PlaybackIssue.prefer(
          _backendIssue,
          PlaybackIssue.backend(error),
        );
        diagnosticTrace?.event(
          'backend_error',
          code: _backendIssue!.code,
          status: _backendIssue!.status,
        );
        if (!_opening) _scheduleFailureCheck(publish);
      }),
      _player.stream.log.listen((entry) {
        if (entry.level != 'error' &&
            entry.level != 'warn' &&
            entry.level != 'fatal') {
          return;
        }
        final issue = PlaybackIssue.backend(entry.text);
        if (!entry.text.startsWith('Can not open external file ') &&
            [
              'http',
              'network',
              'dns',
              'tls',
              'timeout',
              'decoder',
            ].contains(issue.code)) {
          _backendIssue = PlaybackIssue.prefer(_backendIssue, issue);
          if (!_opening) _scheduleFailureCheck(publish);
        }
        // Prefixes and messages can contain paths; keep only classified codes.
        diagnosticTrace?.event(
          'backend_${entry.level == 'warn' ? 'warning' : 'detail'}',
          code: issue.code,
          status: issue.status,
        );
      }),
    ]);
  }
  late final Player _player;
  late final VideoController _video;
  late final PlaybackSleepGuard _sleep;
  late final void Function(dynamic) _publish;
  String? _warning;
  final _changes = StreamController<VideoClock>.broadcast();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  String? _error;
  @override
  PlaybackTrace? diagnosticTrace;
  PlaybackIssue? _backendIssue;
  bool _opening = false;
  VideoLoadMonitor? _loadMonitor;
  Timer? _failureCheck;
  bool _disposed = false;
  int _statsGeneration = 0;
  bool _networkResource = false;
  bool _observingNetworkSpeed = false;
  int? _networkBytesPerSecond;
  Timer? _viewportTimer;
  Future<void> _viewportUpdates = Future.value();
  (int, int)? _viewportTarget, _viewportSubmitted;
  bool _viewportReset = false;

  void _requestViewport(Size logicalSize, double pixelRatio) {
    if (_disposed ||
        !logicalSize.isFinite ||
        logicalSize.isEmpty ||
        !pixelRatio.isFinite ||
        pixelRatio <= 0) {
      return;
    }
    final width = logicalSize.width * pixelRatio;
    final height = logicalSize.height * pixelRatio;
    final scale = math.min(1.0, 8192 / math.max(width, height));
    final target = (
      math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()),
    );
    if (_viewportTarget == target) return;
    _viewportTarget = target;
    _scheduleViewport();
  }

  void _scheduleViewport() {
    if (_disposed || _viewportTarget == null) return;
    _viewportTimer?.cancel();
    // Coalesce drag-resizes instead of reallocating a GPU texture per event.
    _viewportTimer = Timer(const Duration(milliseconds: 80), () {
      _viewportTimer = null;
      _viewportUpdates = _viewportUpdates
          .then((_) async {
            final target = _viewportTarget;
            if (_disposed ||
                target == null ||
                (!_viewportReset && target == _viewportSubmitted)) {
              return;
            }
            final reset = _viewportReset;
            _viewportReset = false;
            if (reset) {
              // Public reset invalidates the plugin's cached requested size after
              // its videoParams listener has independently resized the renderer.
              await _video.setSize();
              if (_disposed) return;
            }
            await _video.setSize(width: target.$1, height: target.$2);
            // The platform queues resize + redraw. This deduplicates submitted
            // requests, not an acknowledgement of a rendered Flutter frame.
            _viewportSubmitted = target;
          })
          .catchError((Object error, StackTrace stack) {
            diagnosticTrace?.failure(
              'video_viewport_resize_failed',
              error,
              stack,
            );
            if (!_disposed) {
              _warning = '画面显示区域更新失败，请调整窗口大小或重新打开视频。';
              _changes.add(clock);
            }
          });
    });
  }

  void _checkAlive() {
    if (_disposed) throw const PlaybackIssue('cancelled');
  }

  void _scheduleFailureCheck(void Function(dynamic) publish) {
    _failureCheck?.cancel();
    _failureCheck = Timer(const Duration(milliseconds: 150), () async {
      try {
        final idle = await _native.getProperty('idle-active');
        if (_disposed || _opening || _player.state.completed || idle != 'yes') {
          return;
        }
        final issue = _backendIssue;
        if (issue == null) return;
        _error = issue.message;
        diagnosticTrace?.event(
          'playback_terminal_error',
          code: issue.code,
          status: issue.status,
        );
        publish(null);
      } catch (error, stack) {
        diagnosticTrace?.failure('failure_probe_failed', error, stack);
      }
    });
  }

  Future<VideoLoadSnapshot> _loadSnapshot() => readVideoLoadSnapshot(
    property: _native.getProperty,
    duration: () => _player.state.duration,
    checkAlive: _checkAlive,
  );

  @override
  double? get videoAspectRatio {
    final params = _player.state.videoParams;
    final aspect = params.aspect;
    if (aspect != null && aspect.isFinite && aspect > 0) {
      return (params.rotate ?? 0) % 180 == 90 ? 1 / aspect : aspect;
    }
    final width = params.dw ?? _player.state.width;
    final height = params.dh ?? _player.state.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (params.rotate ?? 0) % 180 == 90 ? height / width : width / height;
  }

  double _boost = 1;
  double _volume = 80;
  Future<void> _refreshing = Future.value();
  final _trackChanges = StreamController<VideoTrackState>.broadcast();
  VideoTrackState _tracks = const VideoTrackState();
  NativePlayer get _native => _player.platform as NativePlayer;
  late final _subtitleCommands = MpvSubtitleSettingsCommands(
    command: _native.command,
    read: _native.getProperty,
  );
  late final _displayCommands = MpvDisplaySettingsCommands(
    command: _native.command,
    read: (name) async {
      if (name != 'vf') return _native.getProperty(name);
      await _native.waitForPlayerInitialization;
      await _native.waitForVideoControllerInitializationIfAttached;
      final node = readMpvNodeProperty(_native, 'vf');
      if (node is! List) throw StateError('Video filters unavailable');
      return jsonEncode(node);
    },
  );
  @override
  VideoDisplaySettings displaySettings = const VideoDisplaySettings();
  @override
  Future<void> setDisplaySettings(VideoDisplaySettings value) async {
    _checkAlive();
    await _displayCommands.apply(value);
    _checkAlive();
    displaySettings = value;
  }

  @override
  VideoSubtitleStyle subtitleStyle = VideoSubtitleStyle.standard;
  @override
  VideoTimingSettings timing = const VideoTimingSettings();
  late final _timelineCommands = MpvTimelineCommands(
    command: (args) => _native.command(args),
    read: (name) => _native.getProperty(name),
  );
  final _chapterChanges = StreamController<List<VideoChapter>>.broadcast();
  List<VideoChapter> _chapters = const [];
  String? _chapterSnapshot;
  bool _observingChapters = false;
  bool _observingIdle = false;
  @override
  List<VideoChapter> get chapters => _chapters;
  @override
  Stream<List<VideoChapter>> get chapterChanges => _chapterChanges.stream;
  @override
  Future<void> refreshChapters() async {
    if (_disposed) return;
    final raw = await _native.getProperty('chapter-list');
    if (_disposed || raw == _chapterSnapshot) return;
    final chapters = VideoChapter.decode(raw);
    _chapterSnapshot = raw;
    _chapters = chapters;
    _chapterChanges.add(chapters);
  }

  @override
  Future<void> setLoopCurrentItem(bool enabled) =>
      _timelineCommands.setLoopCurrentItem(enabled);
  @override
  Future<void> setABLoop(Duration? start, Duration? end) =>
      _timelineCommands.setABLoop(start, end);
  @override
  Future<void> stepFrame({required bool backward}) async {
    // mpv frame commands pause as well; explicitly use media_kit.pause so its
    // playing stream and the sleep guard also reflect this user action.
    await pause();
    await _timelineCommands.stepFrame(backward: backward);
  }

  @override
  VideoTrackState get tracks => _tracks;
  @override
  Stream<VideoTrackState> get trackChanges => _trackChanges.stream;
  void _scheduleRefresh() {
    if (_disposed) return;
    unawaited(
      refreshTracks().catchError((Object error, StackTrace stack) {
        diagnosticTrace?.failure('track_refresh_failed', error, stack);
      }),
    );
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
    final value = VideoTimingSettings.syncDelay(seconds);
    await _subtitleCommands.apply({'sub-delay': value});
    timing = timing.copyWith(subtitleDelay: value);
    await refreshTracks();
  }

  @override
  Future<void> setSubtitleStyle(VideoSubtitleStyle value) async {
    await _subtitleCommands.applyStyle(value);
    subtitleStyle = value.normalized;
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    final value = VideoTimingSettings.syncDelay(seconds);
    await _subtitleCommands.apply({'audio-delay': value});
    timing = timing.copyWith(audioDelay: value);
  }

  @override
  Future<void> setSubtitleScale(double scale) async {
    final value = VideoTimingSettings.scale(scale);
    await _subtitleCommands.apply({'sub-scale': value});
    timing = timing.copyWith(subtitleScale: value);
  }

  @override
  Future<void> setSubtitlePosition(double position) async {
    final value = VideoTimingSettings.position(position);
    await _subtitleCommands.apply({'sub-pos': value});
    timing = timing.copyWith(subtitlePosition: value);
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
    networkBytesPerSecond: _networkResource ? _networkBytesPerSecond : null,
  );
  @override
  Stream<VideoClock> get changes => _changes.stream;
  @override
  Future<VideoPlaybackStats> readPlaybackStats() async {
    if (_disposed || _opening || _error != null) {
      return const VideoPlaybackStats();
    }
    final generation = _statsGeneration;
    final snapshot = await readMpvPlaybackStats(_native);
    return _disposed || _opening || generation != _statsGeneration
        ? const VideoPlaybackStats()
        : snapshot;
  }

  @override
  Future<void> open(String path, Duration start) async {
    _checkAlive();
    ++_statsGeneration;
    _error = null;
    _networkResource = ['http', 'https'].contains(Uri.tryParse(path)?.scheme);
    _networkBytesPerSecond = null;
    _backendIssue = null;
    _opening = true;
    final monitor = _loadMonitor = VideoLoadMonitor();
    try {
      diagnosticTrace?.stage('engine_configuration');
      if (_networkResource && !_observingNetworkSpeed) {
        try {
          await _native.observeProperty('cache-speed', (raw) async {
            if (_disposed || !_networkResource) return;
            final rate = parseVideoNetworkSpeed(raw);
            if (_networkBytesPerSecond == rate) return;
            _networkBytesPerSecond = rate;
            _changes.add(clock);
          });
          _observingNetworkSpeed = true;
        } catch (error, stack) {
          diagnosticTrace?.failure('network_speed_unavailable', error, stack);
        }
      }
      _checkAlive();
      if (!_observingIdle) {
        await _native.observeProperty('idle-active', (_) async {
          if (!_disposed && !_opening && _backendIssue != null) {
            _scheduleFailureCheck(_publish);
          }
        });
        _observingIdle = true;
      }
      _checkAlive();
      await _set('sub-auto', 'fuzzy');
      _checkAlive();
      await _set('volume-max', '200');
      _checkAlive();
      await setVolume(80);
      _checkAlive();
      diagnosticTrace?.stage('engine_open');
      await _player.open(Media(path, start: start), play: false);
      _checkAlive();
      diagnosticTrace?.stage('engine_ready');
      await monitor.wait(
        read: _loadSnapshot,
        backendIssue: () => _backendIssue,
      );
      _checkAlive();
      // Readiness after decoder fallback makes earlier log errors non-terminal.
      if (_backendIssue != null) {
        diagnosticTrace?.event('backend_recovered', code: _backendIssue!.code);
      }
      _backendIssue = null;
      diagnosticTrace?.stage('engine_tracks');
      await refreshTracks();
      _checkAlive();
      try {
        if (!_observingChapters) {
          await _native.observeProperty('chapter-list', (_) async {
            if (_disposed) return;
            try {
              await refreshChapters();
            } catch (error, stack) {
              diagnosticTrace?.failure('chapter_refresh_failed', error, stack);
              /* Explicit refresh remains retryable. */
            }
          });
          _observingChapters = true;
        }
        await refreshChapters();
      } catch (error, stack) {
        diagnosticTrace?.failure('chapter_initialization_failed', error, stack);
        // An auxiliary chapter read must not block an otherwise valid video.
        // The session performs an explicit retry and exposes a control error.
      }
    } catch (error, stack) {
      diagnosticTrace?.failure('engine_open_failed', error, stack);
      rethrow;
    } finally {
      monitor.cancel();
      if (_loadMonitor == monitor) _loadMonitor = null;
      _opening = false;
      if (!_disposed && _backendIssue != null) {
        _scheduleFailureCheck(_publish);
      }
    }
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
  Widget surface() => LayoutBuilder(
    builder: (context, constraints) {
      _requestViewport(constraints.biggest, View.of(context).devicePixelRatio);
      return Video(
        controller: _video,
        controls: NoVideoControls,
        wakelock: false,
        fit: BoxFit.fill,
      );
    },
  );
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_statsGeneration;
    _loadMonitor?.cancel();
    _failureCheck?.cancel();
    _viewportTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _sleep.dispose();
    await _refreshing;
    await _viewportUpdates;
    await _player.dispose();
    await _changes.close();
    await _trackChanges.close();
    await _chapterChanges.close();
  }
}
