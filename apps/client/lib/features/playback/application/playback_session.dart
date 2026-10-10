import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../api/emby/emby_playback.dart';
import '../../../api/emby/emby_subtitle.dart';
import '../../../api/emby/emby_quality.dart';
import '../../sources/data/emby_connection_repository.dart';
import '../../sources/data/emby_cache_repository.dart';
import '../../../player/video_engine.dart';
import '../../../player/video_tracks.dart';
import '../../sources/data/source_repository.dart';
import '../data/playback_repository.dart';
import '../data/player_preferences_repository.dart';
import '../domain/sidecar_subtitle.dart';
import '../domain/track_language_matcher.dart';
import '../domain/video_queue.dart';
import '../domain/playback_record.dart';
import '../domain/playback_options.dart';

/// Owns a single engine; transitions and checkpoints are serialized. No widget
/// sends native commands or writes SQLite directly.
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required this.sources,
    required this.records,
    required this.createEngine,
    this.checkpointInterval = const Duration(seconds: 5),
    PlayerPreferencesRepository? preferences,
    this.emby,
    this.cache,
    this.remoteReportInterval = const Duration(seconds: 15),
    this.waitForSurface,
  }) : preferences =
           preferences ?? PlayerPreferencesRepository(sources.database);
  final SourceRepository sources;
  final PlaybackRepository records;
  final VideoEngine Function() createEngine;
  final Duration checkpointInterval;
  final PlayerPreferencesRepository preferences;
  final EmbyConnectionRepository? emby;
  final EmbyCacheRepository? cache;
  String? cacheWarning;
  String? _cacheLease;
  Timer? _cacheHeartbeat;
  final Duration remoteReportInterval;

  /// Installed by the player page; headless sessions need no rendering barrier.
  Future<void> Function()? waitForSurface;
  Future<void> _reports = Future.value();
  String? _playSessionId;
  bool _reportedStart = false;
  bool _progressPending = false;
  VideoClock? _pendingForcedProgress;
  DateTime? _lastReport;
  String? syncError;
  EmbyVideoQuality quality = EmbyVideoQuality.source;
  Duration _streamOffset = Duration.zero;
  List<EmbyVideoQuality> get qualityOptions =>
      item == null || filePath != null ? [] : EmbyVideoQuality.options(item!);
  Future<void> selectQuality(EmbyVideoQuality value) => _serialize(() async {
    if (_closed || loading || item == null || value.id == quality.id) return;
    final selected = qualityOptions.where((q) => q.id == value.id).firstOrNull;
    if (selected == null) return;
    await _open(
      item!.identity,
      targetQuality: selected,
      at: clock.position,
      force: true,
      autoplay: clock.playing,
    );
  });
  VideoEngine? engine;
  IndexedMedia? item;
  VideoClock clock = const VideoClock();
  final timeline = ValueNotifier<VideoClock>(const VideoClock());
  final volumeLevel = ValueNotifier<double>(80);
  final playbackRate = ValueNotifier<double>(1);
  String? _powerWarning;
  final tracks = ValueNotifier<VideoTrackState>(const VideoTrackState());
  List<SidecarSubtitle> sidecarSubtitles = const [];
  List<EmbySubtitle> serverSubtitles = const [];
  final serverSubtitlePaths = <String, String>{};
  String? subtitleError;
  Directory? _subtitleDirectory;
  ScanCancellation? _subtitleCancellation;
  String? filePath;
  String? controlError;
  bool _didApplyTrackPreference = false;
  String? _audioPreference;
  String? _subtitlePreference;
  String _subtitleLanguage = 'zh-CN';
  double _volumeBeforeMute = 80;
  bool loading = false;
  String? error;
  String? saveError;
  String? transitionMessage;
  VideoQueue queue = const VideoQueue();
  Map<MediaIdentity, PlaybackRecord> queueRecords = const {};
  VideoEndAction endAction = VideoEndAction.nextEpisode;
  PlaybackOptions options = const PlaybackOptions();
  final closeRequests = ValueNotifier<int>(0);
  StreamSubscription<VideoClock>? _subscription;
  StreamSubscription<VideoTrackState>? _trackSubscription;
  Timer? _checkpoint;
  Future<void> _operations = Future.value();
  Future<void> _writes = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  bool _hasClock = false;
  bool _completedSaved = false;

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> open(MediaIdentity identity) =>
      _serialize(() => _open(identity));

  Future<void> _open(
    MediaIdentity identity, {
    EmbyVideoQuality targetQuality = EmbyVideoQuality.source,
    Duration? at,
    bool force = false,
    bool autoplay = true,
  }) async {
    if (_closed || _closing != null) return;
    if (!force &&
        item?.identity == identity &&
        error == null &&
        engine != null) {
      return;
    }
    final previous = engine;
    final wasPlaying = clock.playing;
    VideoEngine? candidate;
    String? candidateLease;
    _checkpoint?.cancel();
    loading = true;
    transitionMessage = null;
    notifyListeners();
    try {
      final selected = await sources.media(identity);
      final source = await sources.source(identity.sourceId);
      if (selected.isSeries ||
          selected.type == 'music' ||
          selected.type == 'photo') {
        throw const SourceFailure('请选择一个视频播放。');
      }
      String resource;
      String? localPath;
      String? nextCacheWarning;
      final record = await records.read(identity);
      final nextOptions = await preferences.options;
      final resume =
          at ??
          record.resume(
            remember: nextOptions.rememberPosition,
            rewindSeconds: nextOptions.rewindSeconds,
          );
      var streamOffset = Duration.zero;
      String? playSessionId;
      if (source.kind.isFileSource) {
        localPath = p.normalize(
          p.joinAll([source.location, ...p.posix.split(identity.localId)]),
        );
        if (!p.isWithin(source.location, localPath) ||
            !await sources.isReachable(source) ||
            !await File(localPath).exists()) {
          throw const SourceFailure('媒体文件不存在，可能是 NAS 未挂载、移动硬盘断开，或文件已被移动。');
        }
        resource = localPath;
      } else if (source.kind == MediaSourceKind.emby && emby != null) {
        ({String path, String lease})? cached;
        if (!force) {
          try {
            cached = await cache?.acquire(identity);
          } catch (_) {
            // A disconnected cache volume must not prevent online playback.
            // Keep its manifest intact so reconnecting the disk restores it.
            nextCacheWarning = '本地缓存读取失败，已尝试在线播放。请检查缓存目录或磁盘连接。';
          }
        }
        if (cached != null) {
          candidateLease = cached.lease;
          resource = localPath = cached.path;
        } else {
          playSessionId = newEmbyIdentity();
          resource = (await emby!.preparePlayback(
            selected,
            quality: targetQuality,
            start: resume,
            playSessionId: playSessionId,
          )).uri.toString();
          if (!targetQuality.original && resume.inMilliseconds > 1000) {
            streamOffset = resume;
          }
        }
      } else {
        throw const SourceFailure('此媒体源尚不支持播放。');
      }
      final sidecars = localPath == null
          ? <SidecarSubtitle>[]
          : await SidecarSubtitle.find(localPath);
      final audioPreference = await preferences.audio(selected);
      final subtitlePreference = await preferences.subtitle(selected);
      final subtitleLanguage = await preferences.subtitleLanguage;
      final action = await preferences.endAction;
      final rate = nextOptions.rememberRate
          ? await preferences.rate(selected)
          : null;
      final inventory = await sources.inventory();
      final nextQueue = VideoQueue.forItem(selected, inventory.items);
      if (previous != null) {
        try {
          await previous.pause();
        } catch (_) {
          /* Save last valid clock. */
        }
        await save(completed: clock.completed);
        if (saveError != null) return;
      }
      if (_closed || _closing != null) return;
      final current = candidate = createEngine();
      await current
          .open(resource, streamOffset > Duration.zero ? Duration.zero : resume)
          .timeout(const Duration(seconds: 25));
      if (current.clock.error != null) throw StateError(current.clock.error!);
      await current.setVolume(
        force
            ? clock.volume
            : nextOptions.useLaunchVolume
            ? nextOptions.launchVolume
            : (await preferences.number('videoVolume', 80)).clamp(0, 100),
      );
      await current.setPitchCorrection(nextOptions.pitchCorrection);
      await current.setRate(
        force ? clock.rate : rate ?? nextOptions.defaultRate,
      );
      await current.setVolumeBoost(
        (await preferences.number('videoVolumeBoost', 1)).clamp(1, 2),
      );
      await current.setSubtitleDelay(
        (await preferences.number('videoDefaultSubtitleDelay', 0)).clamp(-3, 3),
      );
      if (_closed || _closing != null) return;
      // Commit only after the target can actually decode. Until this point a
      // rejected target leaves the old session, clocks and controls intact.
      await _release(save: false);
      engine = current;
      candidate = null;
      item = selected;
      filePath = localPath;
      cacheWarning = nextCacheWarning;
      _cacheLease = candidateLease;
      candidateLease = null;
      if (_cacheLease != null) {
        final lease = _cacheLease!;
        _cacheHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
          unawaited(cache!.renew(lease).catchError((Object _) {}));
        });
      }
      quality = targetQuality;
      _streamOffset = streamOffset;
      _playSessionId = playSessionId;
      _reportedStart = false;
      _lastReport = null;
      syncError = null;
      sidecarSubtitles = sidecars;
      serverSubtitles = const [];
      serverSubtitlePaths.clear();
      subtitleError = null;
      queue = nextQueue;
      endAction = action;
      options = nextOptions;
      error = null;
      saveError = null;
      controlError = null;
      _hasClock = false;
      _completedSaved = false;
      _didApplyTrackPreference = false;
      _audioPreference = audioPreference;
      _subtitlePreference = subtitlePreference;
      _subtitleLanguage = subtitleLanguage;
      _trackSubscription = current.trackChanges.listen((value) {
        if (_closed || engine != current) return;
        tracks.value = value;
        if (!loading && !_didApplyTrackPreference) {
          unawaited(_controls(() => _applyTrackPreferences(current)));
        }
      });
      _subscription = current.changes.listen(
        (value) {
          if (engine == current) _observe(value);
        },
        onError: (Object e) {
          error = '视频播放失败，请检查文件或重新打开。';
          loading = false;
          notifyListeners();
        },
      );
      notifyListeners();
      tracks.value = current.tracks;
      try {
        await _applyTrackPreferences(current);
      } catch (_) {
        controlError = '音轨或字幕偏好未能应用，可以重新选择。';
      }
      // open() leaves the candidate paused, including while the old session
      // flushes its stop report. Wait for the committed surface to be rendered
      // and track preferences to be applied before allowing audio/time to run.
      await waitForSurface?.call();
      if (_closed || _closing != null) return;
      if (autoplay) await current.play();
      loading = false;
      _observe(current.clock);
      try {
        await _refreshQueueRecords();
      } catch (_) {
        transitionMessage = '剧集观看状态读取失败，请重试。';
      }
    } catch (e) {
      final message = e is SourceFailure ? e.message : '视频无法打开或加载超时，请检查文件后重试。';
      if (previous != null && engine == previous) {
        transitionMessage = message;
        if (wasPlaying && !clock.completed) {
          try {
            await previous.play();
          } catch (_) {
            /* Keep retryable decoder. */
          }
        }
      } else {
        error = message;
        await _release(save: false);
      }
    } finally {
      if (candidate != null) await candidate.dispose();
      if (candidateLease != null) await cache?.release(candidateLease);
      loading = false;
      if (!_closed && engine != null && _hasClock && error == null) {
        _startCheckpoints();
      }
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _refreshQueueRecords() async {
    queueRecords = Map.unmodifiable(
      await records.readMany(queue.items.map((i) => i.identity)),
    );
  }

  Future<void> refreshQueue() => _serialize(() async {
    if (_closed || loading || item == null) return;
    try {
      queue = VideoQueue.forItem(item!, (await sources.inventory()).items);
      await _refreshQueueRecords();
      transitionMessage = null;
    } catch (_) {
      transitionMessage = '剧集列表读取失败，请重试。';
    }
    if (!_closed) notifyListeners();
  });

  Future<void> adjacent(int direction) => _serialize(() async {
    if (_closed || _closing != null || loading || item == null) return;
    try {
      final fresh = VideoQueue.forItem(
        item!,
        (await sources.inventory()).items,
      );
      final target = fresh.adjacent(item!.identity, direction);
      if (target == null) {
        transitionMessage = direction < 0 ? '已经是第一集' : '已经是最后一集';
        notifyListeners();
        return;
      }
      await _open(target.identity);
    } catch (_) {
      transitionMessage = '播放列表读取失败，请重试。';
      notifyListeners();
    }
  });

  Future<void> setEndAction(VideoEndAction action) => _serialize(() async {
    if (_closed || _closing != null) return;
    try {
      await preferences.rememberEndAction(action);
      endAction = action;
      controlError = null;
    } catch (_) {
      controlError = '播放结束设置保存失败，请重试。';
    }
    if (!_closed) notifyListeners();
  });

  Future<void> _handleEnd(VideoEngine? finished) => _serialize(() async {
    if (_closed || _closing != null || engine != finished || !clock.completed) {
      return;
    }
    await save(completed: true);
    if (saveError != null || engine != finished) return;
    switch (endAction) {
      case VideoEndAction.holdLastFrame:
        break;
      case VideoEndAction.closeWindow:
        closeRequests.value++;
      case VideoEndAction.nextEpisode:
        if (item == null) return;
        final fresh = VideoQueue.forItem(
          item!,
          (await sources.inventory()).items,
        );
        if (fresh.items.length > 1) await _open(fresh.items[1].identity);
    }
  });

  void _startCheckpoints() {
    _checkpoint?.cancel();
    _checkpoint = Timer.periodic(checkpointInterval, (_) => unawaited(save()));
  }

  void _observe(VideoClock value) {
    if (_closed) return;
    if (!quality.original && filePath == null) {
      value = VideoClock(
        position: value.position + _streamOffset,
        duration: Duration(
          milliseconds: (item?.remote?.durationMs ?? 0) > 0
              ? item!.remote!.durationMs!
              : (value.duration + _streamOffset).inMilliseconds,
        ),
        playing: value.playing,
        buffering: value.buffering,
        completed: value.completed,
        volume: value.volume,
        rate: value.rate,
        warning: value.warning,
        error: value.error,
      );
    }
    clock = value;
    timeline.value = value;
    if (volumeLevel.value != value.volume) volumeLevel.value = value.volume;
    if (playbackRate.value != value.rate) playbackRate.value = value.rate;
    if (_powerWarning != value.warning) {
      if (controlError == _powerWarning) controlError = value.warning;
      _powerWarning = value.warning;
      if (value.warning != null) controlError = value.warning;
      notifyListeners();
    }
    if (value.error != null) {
      error = item?.remote == null
          ? '视频播放失败：${value.error}'
          : '远程视频播放失败，请检查连接或重新打开。';
      loading = false;
      notifyListeners();
    }
    if (!loading && value.duration > Duration.zero) _hasClock = true;
    if (_hasClock && !loading && error == null) {
      unawaited(
        _reportRemote(
          _reportedStart
              ? EmbyPlaybackPhase.progress
              : EmbyPlaybackPhase.started,
        ),
      );
    }
    if (!value.completed) _completedSaved = false;
    if (value.completed && !_completedSaved && !loading) {
      _completedSaved = true;
      _hasClock = true;
      unawaited(
        _handleEnd(engine).catchError((Object _) {
          if (!_closed) {
            transitionMessage = '播放结束处理失败，请重试。';
            notifyListeners();
          }
        }),
      );
    }
  }

  Future<void> _reportRemote(
    EmbyPlaybackPhase phase, {
    bool force = false,
    VideoClock? snapshot,
  }) {
    final selected = item;
    final sessionId = _playSessionId;
    if (selected == null ||
        selected.remote == null ||
        sessionId == null ||
        emby == null) {
      return Future.value();
    }
    if (phase != EmbyPlaybackPhase.started && !_reportedStart) {
      return Future.value();
    }
    if (phase == EmbyPlaybackPhase.started) {
      if (_reportedStart) return Future.value();
      _reportedStart = true;
    }
    final now = DateTime.now();
    if (phase == EmbyPlaybackPhase.progress) {
      if (_progressPending) {
        // Keep the latest user pause/seek while an upload is in flight; ordinary
        // clock ticks remain throttled and never create an unbounded backlog.
        if (force) _pendingForcedProgress = snapshot ?? clock;
        return Future.value();
      }
      if (!force &&
          _lastReport != null &&
          now.difference(_lastReport!) < remoteReportInterval) {
        return Future.value();
      }
      _progressPending = true;
    }
    _lastReport = now;
    if (phase == EmbyPlaybackPhase.stopped) {
      _reportedStart = false;
      _pendingForcedProgress = null;
    }
    final value = snapshot ?? clock;
    final next = _reports.then((_) async {
      try {
        await emby!.reportPlayback(
          selected,
          playSessionId: sessionId,
          transcoding: !quality.original,
          phase: phase,
          position: value.completed ? value.duration : value.position,
          duration: value.duration,
          paused: !value.playing,
        );
        if (item?.identity == selected.identity) syncError = null;
      } catch (_) {
        if (item?.identity == selected.identity) {
          syncError = 'Emby 播放状态同步失败，本机播放进度仍会保存。';
        }
      } finally {
        if (phase == EmbyPlaybackPhase.progress) {
          _progressPending = false;
          final pending = _pendingForcedProgress;
          _pendingForcedProgress = null;
          if (pending != null &&
              _reportedStart &&
              _playSessionId == sessionId) {
            unawaited(
              _reportRemote(
                EmbyPlaybackPhase.progress,
                force: true,
                snapshot: pending,
              ),
            );
          }
        }
        if (!_closed) notifyListeners();
      }
    });
    _reports = next;
    return next;
  }

  Future<void> save({bool completed = false}) {
    final selected = item;
    final value = clock;
    final policy = options;
    if (!_hasClock || selected == null || value.duration <= Duration.zero) {
      return Future.value();
    }
    final next = _writes.then((_) async {
      try {
        await records.save(
          selected.identity,
          position: completed || value.completed
              ? value.duration
              : value.position,
          duration: value.duration,
          autoMarkWatched: policy.autoMarkWatched,
          watchedThreshold: await preferences.watchedThreshold,
        );
        saveError = null;
      } catch (_) {
        saveError = '播放进度保存失败，请检查本地索引。';
        if (!_closed) notifyListeners();
      }
    });
    _writes = next;
    return next;
  }

  Future<void> _command(Future<void> Function() action) => _serialize(() async {
    if (_closed || _closing != null) return;
    try {
      await action();
    } catch (_) {
      error = '播放器操作失败，请重新打开视频。';
      loading = false;
      notifyListeners();
    }
  });

  Future<void> toggle() => _command(() async {
    if (_closed || loading || error != null || engine == null) return;
    if (clock.playing) {
      await engine!.pause();
      await save();
    } else {
      await engine!.play();
    }
    unawaited(_reportRemote(EmbyPlaybackPhase.progress, force: true));
  });
  Future<void> seek(Duration target) => _command(() async {
    if (_closed ||
        loading ||
        error != null ||
        engine == null ||
        clock.duration <= Duration.zero) {
      return;
    }
    final clamped = target.inMilliseconds.clamp(
      0,
      clock.duration.inMilliseconds,
    );
    if (!quality.original &&
        item != null &&
        filePath == null &&
        _streamOffset > Duration.zero &&
        clamped < _streamOffset.inMilliseconds - 500) {
      await _open(
        item!.identity,
        targetQuality: quality,
        at: Duration(milliseconds: clamped),
        force: true,
        autoplay: clock.playing,
      );
      return;
    }
    await engine!.seek(
      Duration(
        milliseconds: (clamped - _streamOffset.inMilliseconds).clamp(
          0,
          clamped,
        ),
      ),
    );
    unawaited(_reportRemote(EmbyPlaybackPhase.progress, force: true));
  });
  Future<void> volume(double value, {bool remember = true}) => _controls(
    () async {
      if (!_closed && !loading && engine != null) {
        await engine!.setVolume(value.clamp(0, 100));
        if (remember) {
          await preferences.rememberNumber('videoVolume', value.clamp(0, 100));
        }
      }
    },
  );
  Future<void> skip(int direction) => seek(
    clock.position +
        Duration(
          milliseconds:
              (options.skipSeconds * 1000).round() * (direction < 0 ? -1 : 1),
        ),
  );

  Future<void> rate(double value, {bool remember = true}) =>
      _controls(() async {
        final speed = value.isFinite ? value.clamp(.5, 3.0) : 1.0;
        await engine!.setRate(speed);
        if (remember && options.rememberRate && item != null) {
          await preferences.rememberRate(item!, speed);
        }
      });

  Future<void> changeOptions(
    PlaybackOptions Function(PlaybackOptions) change,
  ) => _serialize(() async {
    if (_closed || _closing != null) return;
    final next = PlaybackOptions.fromJson(change(options).toJson())
        .copyWith(watchedThreshold: options.watchedThreshold);
    final previous = options;
    try {
      if (engine != null && next.pitchCorrection != previous.pitchCorrection) {
        await engine!.setPitchCorrection(next.pitchCorrection);
      }
      try {
        await preferences.rememberOptions(next);
      } catch (_) {
        if (engine != null &&
            next.pitchCorrection != previous.pitchCorrection) {
          await engine!.setPitchCorrection(previous.pitchCorrection);
        }
        rethrow;
      }
      options = next;
      controlError = null;
    } catch (_) {
      controlError = '播放设置保存或应用失败，请重试。';
    }
    if (!_closed) notifyListeners();
  });
  Future<void> mute() => _controls(() async {
    final current = clock.volume;
    if (current > 0) _volumeBeforeMute = current;
    final next = current > 0 ? 0.0 : _volumeBeforeMute.clamp(40.0, 100.0);
    await engine!.setVolume(next);
    await preferences.rememberNumber('videoVolume', next);
  });

  Future<void> _applyTrackPreferences(VideoEngine current) async {
    if (_didApplyTrackPreference ||
        engine != current ||
        (current.tracks.audio.isEmpty && current.tracks.subtitles.isEmpty)) {
      return;
    }
    _didApplyTrackPreference = true;
    final audio = _audioPreference == null
        ? null
        : TrackLanguageMatcher.best(current.tracks.audio, _audioPreference!);
    if (audio != null && audio.id != current.tracks.audioId) {
      await current.selectAudio(audio.id);
    }
    if (_subtitlePreference == PlayerPreferencesRepository.subtitleOff) {
      await current.selectSubtitle(null);
    } else {
      final sub = TrackLanguageMatcher.best(
        current.tracks.subtitles,
        _subtitlePreference ?? _subtitleLanguage,
      );
      if (sub != null && sub.id != current.tracks.subtitleId) {
        await current.selectSubtitle(sub.id);
      }
    }
    tracks.value = current.tracks;
  }

  /// Track/device failures do not tear down an otherwise playable decoder.
  Future<void> _controls(Future<void> Function() action) =>
      _serialize(() async {
        if (_closed || _closing != null || loading || engine == null) return;
        try {
          await action();
          controlError = null;
        } catch (_) {
          controlError = '播放器设置操作失败，请检查文件或输出设备后重试。';
        }
        if (!_closed) notifyListeners();
      });
  Future<void> refreshTracks() => _controls(() async {
    await engine!.refreshTracks();
    tracks.value = engine!.tracks;
    if (filePath != null) {
      sidecarSubtitles = await SidecarSubtitle.find(filePath!);
    }
    await _readServerSubtitles();
  });

  Future<T> _subtitleWork<T>(Future<T> Function(ScanCancellation) work) async {
    final token = _subtitleCancellation = ScanCancellation();
    final cancelled = Completer<T>();
    final unlisten = token.listen(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(const ScanCancelled());
      }
    });
    try {
      return await Future.any([work(token), cancelled.future]).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          token.cancel();
          throw const SourceFailure('服务器字幕读取超时，请重试。');
        },
      );
    } finally {
      unlisten();
      if (identical(_subtitleCancellation, token)) _subtitleCancellation = null;
    }
  }

  Future<void> _readServerSubtitles() async {
    if (item?.remote == null || emby == null || _cacheLease != null) return;
    try {
      serverSubtitles = await _subtitleWork(
        (token) => emby!.subtitles(item!, cancellation: token),
      );
      subtitleError = null;
    } catch (_) {
      subtitleError = '服务器字幕读取失败，请重试。';
    }
  }

  Future<void> refreshServerSubtitles() => _controls(_readServerSubtitles);

  Future<void> selectServerSubtitle(String key) => _controls(() async {
    final stream = serverSubtitles.where((s) => s.key == key).firstOrNull;
    if (stream == null || item == null || emby == null) return;
    try {
      var path = serverSubtitlePaths[key];
      if (path == null || !await File(path).exists()) {
        final bytes = await _subtitleWork(
          (token) => emby!.subtitle(item!, stream, cancellation: token),
        );
        _subtitleDirectory ??= await Directory.systemTemp.createTemp(
          'reelnest-subtitles-',
        );
        final language = (stream.language ?? 'und').replaceAll(
          RegExp(r'[^a-zA-Z0-9-]'),
          '_',
        );
        path = p.join(
          _subtitleDirectory!.path,
          '${stream.index}.$language.${stream.extension}',
        );
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (_closing != null || _closed) return;
      final loaded = engine!.tracks.subtitles
          .where(
            (t) =>
                t.externalFilename != null &&
                p.equals(t.externalFilename!, path!),
          )
          .firstOrNull;
      if (loaded == null) {
        await engine!.addSubtitle(path);
      } else {
        await engine!.selectSubtitle(loaded.id);
      }
      serverSubtitlePaths[key] = path;
      _didApplyTrackPreference = true;
      tracks.value = engine!.tracks;
      await preferences.rememberSubtitle(item!, stream.language);
      subtitleError = null;
    } catch (_) {
      subtitleError = '服务器字幕加载失败，请重新选择。';
    }
  });
  Future<void> selectAudio(int? id) => _controls(() async {
    final track = id == null
        ? null
        : tracks.value.audio.where((t) => t.id == id).firstOrNull;
    if (id != null && track == null) throw StateError('Unknown audio track');
    if (id != null) _didApplyTrackPreference = true;
    await engine!.selectAudio(id);
    if (id != null && track?.language != null) {
      await preferences.rememberAudio(item!, track!.language);
    }
  });
  Future<void> selectSubtitle(int? id) => _controls(() async {
    final track = id == null
        ? null
        : tracks.value.subtitles.where((t) => t.id == id).firstOrNull;
    if (id != null && track == null) throw StateError('Unknown subtitle track');
    _didApplyTrackPreference = true;
    await engine!.selectSubtitle(id);
    if (id == null || track?.language != null) {
      await preferences.rememberSubtitle(
        item!,
        id == null ? PlayerPreferencesRepository.subtitleOff : track!.language,
      );
    }
  });
  Future<void> selectSecondarySubtitle(int? id) => _controls(() async {
    if (id != null &&
        (id == tracks.value.subtitleId ||
            !tracks.value.subtitles.any((t) => t.id == id))) {
      throw StateError('Invalid secondary subtitle');
    }
    await engine!.selectSecondarySubtitle(id);
  });
  Future<void> enableAutoSubtitles() => _controls(() async {
    await engine!.enableAutoSubtitles();
    if (filePath != null) {
      sidecarSubtitles = await SidecarSubtitle.find(filePath!);
    }
  });
  Future<void> addSubtitle(String path) => _controls(() async {
    final existing = tracks.value.subtitles
        .where(
          (t) =>
              t.external &&
              t.externalFilename != null &&
              p.equals(t.externalFilename!, path),
        )
        .firstOrNull;
    if (existing != null) {
      _didApplyTrackPreference = true;
      await engine!.selectSubtitle(existing.id);
      if (existing.language != null) {
        await preferences.rememberSubtitle(item!, existing.language);
      }
    } else {
      await engine!.addSubtitle(path);
    }
  });
  Future<void> subtitleDelay(double seconds) => _controls(() async {
    final clamped = seconds.isFinite ? (seconds * 10).round() / 10 : 0.0;
    final value = clamped.clamp(-3.0, 3.0);
    await engine!.setSubtitleDelay(value);
    await preferences.rememberNumber('videoDefaultSubtitleDelay', value);
  });
  Future<void> volumeBoost(double value) => _controls(() async {
    final boost = value.isFinite ? value.clamp(1.0, 2.0) : 1.0;
    await engine!.setVolumeBoost(boost);
    await preferences.rememberNumber('videoVolumeBoost', boost);
  });
  Future<void> audioDevice(String name) => _controls(() async {
    if (name != 'auto' && !tracks.value.devices.any((d) => d.name == name)) {
      throw StateError('Unknown audio device');
    }
    await engine!.setAudioDevice(name);
  });

  Future<void> _release({bool save = true}) async {
    _checkpoint?.cancel();
    _checkpoint = null;
    final current = engine;
    if (current == null) return;
    try {
      await current.pause();
    } catch (_) {
      /* Still release a failed decoder. */
    }
    if (save) await this.save(completed: clock.completed);
    await _subscription?.cancel();
    _subscription = null;
    await _trackSubscription?.cancel();
    _trackSubscription = null;
    if (_playSessionId != null) {
      await _reportRemote(EmbyPlaybackPhase.stopped, force: true);
      await _reports;
      _playSessionId = null;
    }
    try {
      await current.dispose();
    } finally {
      engine = null;
      _cacheHeartbeat?.cancel();
      _cacheHeartbeat = null;
      final lease = _cacheLease;
      _cacheLease = null;
      if (lease != null) {
        try {
          await cache?.release(lease);
        } catch (_) {
          /* Lease expires if storage is unavailable. */
        }
      }
      final directory = _subtitleDirectory;
      _subtitleDirectory = null;
      serverSubtitlePaths.clear();
      if (directory != null &&
          p.isWithin(
            p.normalize(Directory.systemTemp.absolute.path),
            p.normalize(directory.absolute.path),
          ) &&
          p.basename(directory.path).startsWith('reelnest-subtitles-')) {
        try {
          await directory.delete(recursive: true);
        } on FileSystemException {
          // An OS-held temporary file must not prevent closing the decoder.
        }
      }
    }
  }

  /// Pause and commit first. A failed checkpoint leaves the decoder and
  /// command queue available; only an explicit discard may bypass persistence.
  Future<void> close({bool discardProgress = false}) {
    if (_closed) return _closing ?? Future.value();
    if (_closing != null) return _closing!;
    _subtitleCancellation?.cancel();
    final closing = _serialize(() async {
      _checkpoint?.cancel();
      _checkpoint = null;
      if (engine != null) {
        try {
          await engine!.pause();
        } catch (_) {
          // A failed decoder must not prevent persisting its last valid clock.
        }
      }
      if (!discardProgress) await save(completed: clock.completed);
      await _writes;
      if (!discardProgress && saveError != null) return;
      await _release(save: false);
      _closed = true;
    });
    _closing = closing;
    return closing.whenComplete(() {
      if (!_closed) {
        _closing = null;
        if (engine != null && _hasClock && !loading && error == null) {
          _startCheckpoints();
        }
      }
    });
  }

  @override
  void dispose() {
    _checkpoint?.cancel();
    _cacheHeartbeat?.cancel();
    timeline.dispose();
    volumeLevel.dispose();
    playbackRate.dispose();
    tracks.dispose();
    closeRequests.dispose();
    super.dispose();
  }
}
