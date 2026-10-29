import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../api/emby/emby_playback.dart';
import '../../../api/emby/emby_client.dart' show EmbyFailure;
import '../../../api/emby/emby_subtitle.dart';
import '../../../api/emby/emby_quality.dart';
import '../../sources/data/emby_connection_repository.dart';
import '../../sources/data/emby_cache_repository.dart';
import '../../../player/video_engine.dart';
import '../../../player/video_tracks.dart';
import '../../../player/video_timeline.dart';
import '../../../player/playback_diagnostics.dart';
import '../../../player/video_subtitle_settings_engine.dart';
import '../../../player/video_display_settings_engine.dart';
import '../domain/video_display_settings.dart';
import '../../../player/video_color_adjustments_engine.dart';
import '../domain/video_color_adjustments.dart';
import '../domain/video_sharpen_mode.dart';
import '../domain/video_equalizer_settings.dart';
import '../../../player/video_equalizer_engine.dart';
import '../../../player/video_sharpen_engine.dart';
import '../domain/video_performance_settings.dart';
import '../../../player/video_performance_settings_engine.dart';
import '../domain/video_render_settings.dart';
import '../../../player/video_render_settings_engine.dart';
import '../../../platform/subtitle_font_catalog.dart';
import '../../../storage/runtime_storage_paths.dart';
import '../../../player/mpv_video_frame_preview.dart';
import '../../sources/data/source_repository.dart';
import '../../sources/data/url_video_repository.dart';
import '../data/playback_repository.dart';
import '../data/player_preferences_repository.dart';
import '../data/video_screenshot_store.dart';
import '../domain/video_screenshot.dart';
import '../../../player/video_screenshot_engine.dart';
import '../data/playback_marker_repository.dart';
import '../domain/playback_marker.dart';
import 'playback_timeline_controller.dart';
import '../domain/sidecar_subtitle.dart';
import '../domain/track_language_matcher.dart';
import '../domain/video_queue.dart';
import '../domain/playback_record.dart';
import '../domain/playback_options.dart';
import '../domain/video_frame_preview.dart';
import '../domain/transient_playback_target.dart';
import '../../../platform/transient_file_access.dart';
import 'transient_playback_resolver.dart';
import '../domain/video_subtitle_settings.dart';
import 'video_frame_preview_cache.dart';
import '../domain/online_subtitle.dart';
import '../data/online_subtitle_service.dart';
import '../data/online_subtitle_settings_repository.dart';
import '../data/online_subtitle_store.dart';
import '../domain/video_keyboard_shortcuts.dart';
import '../../../player/video_track_shortcut_engine.dart';

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
    this.diagnostics,
    Future<List<String>> Function()? subtitleFonts,
    VideoPreviewGenerator? previewGenerator,
    VideoScreenshotStore? screenshotStore,
    OnlineSubtitleService? onlineSubtitleService,
    OnlineSubtitleSettingsRepository? onlineSubtitleSettings,
    OnlineSubtitleStore? onlineSubtitleStore,
  }) : preferences =
           preferences ?? PlayerPreferencesRepository(sources.database),
       _providedPreviewGenerator = previewGenerator,
       _subtitleFonts = subtitleFonts ?? SubtitleFontCatalog().families,
       _screenshotStore = screenshotStore ?? VideoScreenshotStore(),
       _onlineService = onlineSubtitleService ?? OnlineSubtitleService(),
       _providedOnlineSettings = onlineSubtitleSettings,
       _onlineStore = onlineSubtitleStore ?? OnlineSubtitleStore();
  final OnlineSubtitleService _onlineService;
  final OnlineSubtitleSettingsRepository? _providedOnlineSettings;
  late final onlineSubtitleSettings =
      _providedOnlineSettings ?? OnlineSubtitleSettingsRepository(preferences);
  final OnlineSubtitleStore _onlineStore;
  VideoKeyboardShortcuts keyboardShortcuts = VideoKeyboardShortcuts();
  Future<void> _shortcutActions = Future.value();
  double? _keyboardHoldRate;
  VideoEngine? _keyboardHoldEngine;

  Future<void> _changeKeyboardShortcuts(
    VideoKeyboardShortcuts Function(VideoKeyboardShortcuts) change,
  ) => _serialize(() async {
    if (_closed || _closing != null || _disposed) return;
    try {
      final next = change(keyboardShortcuts);
      await preferences.rememberKeyboardShortcuts(next);
      keyboardShortcuts = next;
      controlError = null;
    } catch (_) {
      controlError = '快捷键设置保存失败，原有绑定已保留，请重试。';
    }
    if (!_closed && !_disposed) notifyListeners();
  });
  Future<void> setKeyboardShortcuts(
    VideoShortcutAction action,
    List<VideoKeyChord> keys,
  ) => _changeKeyboardShortcuts((current) => current.set(action, keys));
  Future<void> resetKeyboardShortcut(VideoShortcutAction action) =>
      _changeKeyboardShortcuts((current) => current.reset(action));
  Future<void> resetAllKeyboardShortcuts() =>
      _changeKeyboardShortcuts((current) => current.resetAll());

  /// Serialize keyboard deltas before calculating the next value. Network
  /// playback and renderer commands continue through the existing session APIs.
  Future<void> performKeyboardAction(VideoShortcutAction action) {
    final target = engine, identity = item?.identity;
    final operation = _shortcutActions.then((_) async {
      if (_closed ||
          _disposed ||
          _closing != null ||
          loading ||
          target == null ||
          engine != target ||
          item?.identity != identity) {
        return;
      }
      if (action.seekPercent case final double percent) {
        await seek(
          Duration(
            microseconds: (clock.duration.inMicroseconds * percent).round(),
          ),
        );
        return;
      }
      switch (action) {
        case VideoShortcutAction.playPause:
          await toggle();
        case VideoShortcutAction.previousEpisode:
          await adjacent(-1);
        case VideoShortcutAction.nextEpisode:
          await adjacent(1);
        case VideoShortcutAction.restart:
          await seek(Duration.zero);
          if (engine == target && !clock.playing) await toggle();
        case VideoShortcutAction.cycleABLoopPoint:
          await cycleABLoop();
        case VideoShortcutAction.clearABLoop:
          await clearABLoop();
        case VideoShortcutAction.toggleCurrentLoop:
          await setLoopCurrentItem(!precision.value.loop.loopCurrentItem);
        case VideoShortcutAction.seekBackward:
          await skip(-1);
        case VideoShortcutAction.seekForward:
          await skip(1);
        case VideoShortcutAction.seekBackwardSmall:
          await seek(clock.position - const Duration(seconds: 5));
        case VideoShortcutAction.seekForwardSmall:
          await seek(clock.position + const Duration(seconds: 5));
        case VideoShortcutAction.seekBackwardLarge:
          await seek(clock.position - const Duration(seconds: 60));
        case VideoShortcutAction.seekForwardLarge:
          await seek(clock.position + const Duration(seconds: 60));
        case VideoShortcutAction.seekBackwardTen:
          await seek(clock.position - const Duration(seconds: 10));
        case VideoShortcutAction.seekForwardTen:
          await seek(clock.position + const Duration(seconds: 10));
        case VideoShortcutAction.volumeUp:
          await volume(clock.volume + 5.5);
        case VideoShortcutAction.volumeDown:
          await volume(clock.volume - 5.5);
        case VideoShortcutAction.mute:
          await mute();
        case VideoShortcutAction.goToBeginning:
          await seek(Duration.zero);
        case VideoShortcutAction.goToEnd:
          await seek(clock.duration - const Duration(milliseconds: 500));
        case VideoShortcutAction.speedDown:
          await rate(clock.rate - .25);
        case VideoShortcutAction.speedUp:
          await rate(clock.rate + .25);
        case VideoShortcutAction.resetSpeed:
          await rate(1);
        case VideoShortcutAction.frameBackward:
          await stepFrame(backward: true);
        case VideoShortcutAction.frameForward:
          await stepFrame();
        case VideoShortcutAction.audioDelayDown:
          await audioDelay(timing.audioDelay - .1);
        case VideoShortcutAction.audioDelayUp:
          await audioDelay(timing.audioDelay + .1);
        case VideoShortcutAction.subtitleDelayDown:
          await subtitleDelay(timing.subtitleDelay - .1);
        case VideoShortcutAction.subtitleDelayUp:
          await subtitleDelay(timing.subtitleDelay + .1);
        case VideoShortcutAction.subtitleSizeDown:
          await subtitleScale(timing.subtitleScale - .05);
        case VideoShortcutAction.subtitleSizeUp:
          await subtitleScale(timing.subtitleScale + .05);
        case VideoShortcutAction.subtitleMoveUp:
          await subtitlePosition(timing.subtitlePosition - 4);
        case VideoShortcutAction.subtitleMoveDown:
          await subtitlePosition(timing.subtitlePosition + 4);
        case VideoShortcutAction.cycleAspectRatio:
          await updateDisplaySettings(
            (current) => current.copyWith(
              aspectOverride:
                  VideoAspectOverride.values[(current.aspectOverride.index +
                          1) %
                      VideoAspectOverride.values.length],
            ),
          );
        case VideoShortcutAction.cycleCropMode:
          await updateDisplaySettings(
            (current) => current.copyWith(
              cropMode:
                  VideoCropMode.values[(current.cropMode.index + 1) %
                      VideoCropMode.values.length],
            ),
          );
        case VideoShortcutAction.cycleDeinterlaceMode:
          await updateDisplaySettings(
            (current) => current.copyWith(
              deinterlaceMode:
                  VideoDeinterlaceMode.values[(current.deinterlaceMode.index +
                          1) %
                      VideoDeinterlaceMode.values.length],
            ),
          );
        case VideoShortcutAction.rotateVideoLeft:
          await updateDisplaySettings(
            (current) => current.copyWith(
              rotationMode:
                  VideoRotationMode.values[(current.rotationMode.index - 1) %
                      VideoRotationMode.values.length],
            ),
          );
        case VideoShortcutAction.rotateVideoRight:
          await updateDisplaySettings(
            (current) => current.copyWith(
              rotationMode:
                  VideoRotationMode.values[(current.rotationMode.index + 1) %
                      VideoRotationMode.values.length],
            ),
          );
        case VideoShortcutAction.subtitleCycle:
        case VideoShortcutAction.subtitleToggle:
        case VideoShortcutAction.audioCycle:
          await _controls(() async {
            if (target is! VideoTrackShortcutEngine) {
              throw StateError('Track shortcuts unavailable');
            }
            final tracksEngine = target as VideoTrackShortcutEngine;
            if (action == VideoShortcutAction.subtitleCycle) {
              await tracksEngine.cycleSubtitleTrack();
            } else if (action == VideoShortcutAction.subtitleToggle) {
              await tracksEngine.toggleSubtitleVisibility();
            } else {
              await tracksEngine.cycleAudioTrack();
            }
            _didApplyTrackPreference = true;
            tracks.value = target.tracks;
          });
        default:
          break; // Window/surface actions belong to the presentation.
      }
    });
    _shortcutActions = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> setKeyboardSeekForwardHold(bool holding) {
    final requestedEngine = engine;
    return _controls(() async {
      if (holding) {
        if (engine != requestedEngine) return;
        if (_keyboardHoldRate != null) return;
        final current = engine!;
        final before = clock.rate;
        await current.setRate(3);
        _keyboardHoldRate = before;
        _keyboardHoldEngine = current;
        if (!clock.playing) await current.play();
      } else {
        final before = _keyboardHoldRate;
        final expected = _keyboardHoldEngine;
        _keyboardHoldRate = null;
        _keyboardHoldEngine = null;
        if (before != null && expected == engine) await engine!.setRate(before);
      }
    }, failureMessage: '临时倍速操作失败，请重新设置播放速度。');
  }

  ScanCancellation? _onlineSearchToken, _onlineDownloadToken;
  bool searchingOnlineSubtitles = false, hasOpenSubtitlesKey = false;
  String? onlineSubtitleError, downloadingOnlineSubtitleID;
  List<OnlineSubtitleResult> onlineSubtitleResults = const [];
  final downloadedOnlineSubtitlePaths = <String, String>{};
  bool _disposed = false;

  void cancelOnlineSubtitleSearch() {
    _onlineSearchToken?.cancel();
    _onlineSearchToken = null;
    searchingOnlineSubtitles = false;
  }

  void _cancelOnlineSubtitles() {
    cancelOnlineSubtitleSearch();
    _onlineDownloadToken?.cancel();
    _onlineDownloadToken = null;
    downloadingOnlineSubtitleID = null;
  }

  Future<({OnlineSubtitleSettings settings, String? warning})>
  _readOnlineSettings() async {
    try {
      return (settings: await onlineSubtitleSettings.read(), warning: null);
    } catch (_) {
      // An unavailable optional key must not disable the keyless provider.
      return (
        settings: OnlineSubtitleSettings(
          language: await preferences.subtitleLanguage,
        ),
        warning: 'OpenSubtitles 设置读取失败，已尝试使用 Podnapisi。',
      );
    }
  }

  Future<void> searchOnlineSubtitles() async {
    if (_closed ||
        _disposed ||
        _closing != null ||
        loading ||
        item == null ||
        engine == null) {
      return;
    }
    cancelOnlineSubtitleSearch();
    final token = _onlineSearchToken = ScanCancellation();
    final selected = item!, current = engine;
    searchingOnlineSubtitles = true;
    onlineSubtitleError = null;
    onlineSubtitleResults = const [];
    notifyListeners();
    try {
      final configuration = await _readOnlineSettings();
      token.check();
      final settings = configuration.settings;
      onlineSubtitleError = configuration.warning;
      hasOpenSubtitlesKey = settings.apiKey.isNotEmpty;
      var title = selected.title, year = selected.year;
      if (selected.parentId != null) {
        try {
          final parent = await sources.media((
            sourceId: selected.identity.sourceId,
            localId: selected.parentId!,
          ));
          title = parent.title;
          year = parent.year;
        } catch (_) {
          /* Use the selected title when the parent is unavailable. */
        }
      }
      token.check();
      final external = selected.remote?.externalId ?? '';
      final result = await _onlineService.search(
        OnlineSubtitleQuery(
          title: title,
          year: year,
          imdbID: external.startsWith('imdb:') ? external.substring(5) : null,
          season: selected.seasonNumber,
          episode: selected.episodeNumber,
        ),
        settings,
        token,
      );
      token.check();
      if (!identical(engine, current) || item?.identity != selected.identity) {
        return;
      }
      onlineSubtitleResults = result.results;
      final warnings = [?onlineSubtitleError, ...result.warnings];
      onlineSubtitleError = warnings.isNotEmpty
          ? warnings.join(' ')
          : result.results.isEmpty
          ? '未找到字幕，可尝试修改标题后重新搜索。'
          : null;
    } on ScanCancelled {
      /* Stale requests never publish results. */
    } catch (_) {
      if (identical(_onlineSearchToken, token) && !_closed && !_disposed) {
        onlineSubtitleError = '在线字幕搜索失败，请稍后重试。';
      }
    } finally {
      if (identical(_onlineSearchToken, token)) {
        _onlineSearchToken = null;
        searchingOnlineSubtitles = false;
        if (!_closed && !_disposed) notifyListeners();
      }
    }
  }

  Future<void> downloadOnlineSubtitle(OnlineSubtitleResult result) async {
    if (_closed ||
        _disposed ||
        _closing != null ||
        loading ||
        item == null ||
        engine == null ||
        downloadingOnlineSubtitleID != null ||
        !onlineSubtitleResults.any(
          (r) =>
              r.id == result.id &&
              r.fileId == result.fileId &&
              r.provider == result.provider,
        )) {
      return;
    }
    final token = _onlineDownloadToken = ScanCancellation();
    final selected = item!, current = engine!;
    downloadingOnlineSubtitleID = result.id;
    onlineSubtitleError = null;
    notifyListeners();
    try {
      var path = downloadedOnlineSubtitlePaths[result.id];
      final alreadySaved = path != null && await File(path).exists();
      final payload = alreadySaved
          ? null
          : await _onlineService.download(
              result,
              (await _readOnlineSettings()).settings,
              token,
            );
      token.check();
      // Network I/O is outside the playback queue. Commit/load is serialized
      // with engine replacement so a late download cannot attach to a new film.
      await _serialize(() async {
        token.check();
        if (_closed ||
            _closing != null ||
            !identical(engine, current) ||
            item?.identity != selected.identity) {
          return;
        }
        if (payload != null) {
          if (selected.remote == null && filePath != null) {
            path = p.setExtension(filePath!, '.${payload.extension}');
          } else {
            final root = await RuntimeStoragePaths.current.temporary();
            await root.create(recursive: true);
            _subtitleDirectory ??= await root.createTemp('reelnest-subtitles-');
            path = p.join(
              _subtitleDirectory!.path,
              'online-${result.provider.name}-${result.fileId}.${payload.extension}',
            );
          }
          token.check();
          path = await _onlineStore.save(payload, path!, token);
          downloadedOnlineSubtitlePaths.removeWhere(
            (_, old) => p.equals(old, path!),
          );
          downloadedOnlineSubtitlePaths[result.id] = path!;
        }
        token.check();
        final existing = current.tracks.subtitles
            .where(
              (t) =>
                  t.externalFilename != null &&
                  p.equals(t.externalFilename!, path!),
            )
            .firstOrNull;
        if (existing == null || payload != null) {
          await current.addSubtitle(path!);
        } else {
          await current.selectSubtitle(existing.id);
        }
        _didApplyTrackPreference = true;
        tracks.value = current.tracks;
        if (selected.remote == null && filePath != null) {
          sidecarSubtitles = await SidecarSubtitle.find(filePath!);
        }
        try {
          await preferences.rememberSubtitle(selected, result.language);
        } catch (_) {
          onlineSubtitleError = '字幕已加载，但语言偏好保存失败。';
        }
      });
    } on ScanCancelled {
      /* Close/switch owns cancellation and cleanup. */
    } catch (failure) {
      if (identical(_onlineDownloadToken, token) && !_closed && !_disposed) {
        onlineSubtitleError = failure is OnlineSubtitleFailure
            ? failure.message
            : '字幕下载或加载失败，请重试。';
      }
    } finally {
      if (identical(_onlineDownloadToken, token)) {
        _onlineDownloadToken = null;
        downloadingOnlineSubtitleID = null;
        if (!_closed && !_disposed) notifyListeners();
      }
    }
  }

  final VideoScreenshotStore _screenshotStore;
  VideoScreenshotMode screenshotMode = VideoScreenshotMode.subtitles;
  bool capturingFrame = false;
  bool get canCaptureFrame =>
      !_closed &&
      _closing == null &&
      !loading &&
      error == null &&
      item != null &&
      engine is VideoScreenshotEngine;

  Future<void> setScreenshotMode(VideoScreenshotMode value) =>
      _controls(() async {
        await preferences.rememberScreenshotMode(value);
        screenshotMode = value;
      }, failureMessage: '截图内容设置保存失败，请重试。');

  Future<String> captureCurrentFrame() {
    if (!canCaptureFrame || capturingFrame) {
      return Future.error(const VideoScreenshotFailure('当前画面暂不可截图，请稍后重试。'));
    }
    final current = engine! as VideoScreenshotEngine;
    final title = item!.title;
    final identity = item!.identity;
    capturingFrame = true;
    notifyListeners();
    final result = Completer<String>();
    unawaited(
      _serialize(() async {
        try {
          if (!canCaptureFrame ||
              !identical(engine, current) ||
              item?.identity != identity) {
            throw const VideoScreenshotFailure('播放内容已切换，请重新截图。');
          }
          final mode = screenshotMode;
          final png = await current.captureCurrentFrame(mode);
          // Closing/switching waits on this serialized operation, keeping the
          // captured media's identity and native player alive until it settles.
          if (_closed || _closing != null) {
            throw const VideoScreenshotFailure('播放器正在关闭，本次截图未保存。');
          }
          final path = await _screenshotStore.save(title, png);
          _trace?.event('screenshot_saved', code: mode.name);
          result.complete(path);
        } catch (error, stack) {
          _trace?.failure('screenshot_failed', error, stack);
          result.completeError(
            error is VideoScreenshotFailure
                ? error
                : const VideoScreenshotFailure('未能取得当前画面，请稍后重试。'),
          );
        } finally {
          capturingFrame = false;
          if (!_closed) notifyListeners();
        }
      }),
    );
    return result.future;
  }

  final SourceRepository sources;
  final PlaybackDiagnostics? diagnostics;
  PlaybackTrace? _trace;
  final Future<List<String>> Function() _subtitleFonts;
  Future<List<String>>? _fontFamilies;
  Future<List<String>> get subtitleFontFamilies {
    if (_fontFamilies != null) return _fontFamilies!;
    final future = _fontFamilies = Future<List<String>>.sync(_subtitleFonts)
        .catchError((Object error, StackTrace stack) {
          _fontFamilies = null;
          Error.throwWithStackTrace(error, stack);
        });
    // A tab's FutureBuilder attaches on the next frame. Handle early failures
    // immediately while preserving the original failed Future for its error UI.
    unawaited(
      future.then<void>((_) {}, onError: (Object _, StackTrace stack) {}),
    );
    return future;
  }

  VideoSubtitleStyle subtitleStyle = VideoSubtitleStyle.standard;
  VideoTimingSettings timing = const VideoTimingSettings();
  VideoDisplaySettings displaySettings = const VideoDisplaySettings();
  VideoColorAdjustments colorAdjustments = VideoColorAdjustments.neutral;
  VideoSharpenMode sharpenMode = VideoSharpenMode.off;
  VideoEqualizerSettings equalizerSettings = const VideoEqualizerSettings();
  VideoPerformanceSettings performanceSettings =
      const VideoPerformanceSettings();
  VideoRenderSettings renderSettings = const VideoRenderSettings();
  final PlaybackRepository records;
  final VideoPreviewGenerator? _providedPreviewGenerator;
  final _previewIssueCodes = <String>{};
  int _previewTraceAttempts = 0;
  bool _didGeneratePreview = false;
  VideoPreviewResource? _previewResource;
  TransientPlaybackTarget? _transientTarget;
  TransientPlaybackTarget? _failedTransientTarget;
  TransientFileAccess? _fileAccess;
  bool get transient => item != null && isTransientPlayback(item!.identity);
  TransientPlaybackTarget? get transientTarget =>
      _transientTarget ?? (engine == null ? _failedTransientTarget : null);
  bool get httpStream => _previewResource?.remote == true;
  bool lastOpenSucceeded = false;
  late final previewFrames = VideoFramePreviewCache(generate: _generatePreview);

  Future<Uint8List?> _generatePreview(
    VideoPreviewResource resource,
    Duration time,
    VideoPreviewCancellation cancellation,
  ) async {
    String? lease;
    TransientFileAccess? fileAccess;
    final watch = Stopwatch()..start();
    final trace = _trace;
    final traceAttempt = _previewTraceAttempts++ < 8;
    if (traceAttempt) {
      trace?.event(
        'preview_started',
        stage: 'preview',
        remote: resource.remote,
        cached: resource.cached,
      );
    }
    void report(String code) {
      if (cancellation.isCancelled ||
          resource != _previewResource ||
          _previewIssueCodes.length >= 16 ||
          !_previewIssueCodes.add(code)) {
        return;
      }
      _trace?.event(
        'preview_unavailable',
        stage: 'preview',
        code: code,
        durationMs: watch.elapsedMilliseconds,
        remote: resource.remote,
        cached: resource.cached,
      );
    }

    try {
      if (_fileAccess != null && !resource.remote) {
        fileAccess = await TransientFileAccess.acquire(
          resource.location,
          bookmark: _fileAccess!.bookmark,
        );
      }
      if (resource.cached) {
        final retained = await cache?.acquire(resource.identity);
        if (retained == null) {
          report('cache_unavailable');
          return null;
        }
        lease = retained.lease;
        if (!p.equals(retained.path, resource.location)) return null;
      }
      if (cancellation.isCancelled) return null;
      final custom = _providedPreviewGenerator;
      final bytes = custom == null
          ? await generateMpvVideoPreview(
              resource,
              time,
              cancellation,
              onIssue: report,
            )
          : await custom(resource, time, cancellation);
      if (bytes != null &&
          !cancellation.isCancelled &&
          resource == _previewResource &&
          !_didGeneratePreview) {
        _didGeneratePreview = true;
        _trace?.event(
          'preview_generated',
          stage: 'preview',
          durationMs: watch.elapsedMilliseconds,
          remote: resource.remote,
          cached: resource.cached,
        );
      }
      return bytes;
    } catch (_) {
      report('preview_exception');
      return null;
    } finally {
      if (traceAttempt) {
        trace?.event(
          cancellation.isCancelled ? 'preview_cancelled' : 'preview_finished',
          stage: 'preview',
          durationMs: watch.elapsedMilliseconds,
          remote: resource.remote,
          cached: resource.cached,
        );
      }
      await fileAccess?.release();
      if (lease != null) {
        try {
          await cache?.release(lease);
        } catch (_) {
          /* Lease expires. */
        }
      }
    }
  }

  Future<VideoPreviewFrame?> requestPreview({
    required Duration time,
    required Duration duration,
    required bool coarse,
    VideoPreviewCancellation? cancellation,
    bool prefetch = false,
  }) {
    if (_closed ||
        _closing != null ||
        loading ||
        error != null ||
        engine == null) {
      return Future.value();
    }
    return previewFrames.request(
      time: time,
      duration: duration,
      coarse: coarse,
      cancellation: cancellation,
      prefetch: prefetch,
    );
  }

  late final _precision = PlaybackTimelineController(
    PlaybackMarkerRepository(sources.database),
    preferences,
  );

  /// Low-frequency chapter/bookmark/loop state. Observe separately from the
  /// playback clock; send all user commands through this session.
  ValueListenable<PlaybackTimelineState> get precision => _precision;
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
  String _historyEpoch = '';
  bool _reportedStart = false;
  bool _progressPending = false;
  VideoClock? _pendingForcedProgress;
  DateTime? _lastReport;
  String? syncError;
  EmbyVideoQuality quality = EmbyVideoQuality.source;
  Duration _streamOffset = Duration.zero;
  List<EmbyVideoQuality> get qualityOptions =>
      item == null || filePath != null || transient
      ? []
      : EmbyVideoQuality.options(item!);
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
  StreamSubscription<List<VideoChapter>>? _chapterSubscription;
  Timer? _checkpoint;
  Future<void> _operations = Future.value();
  Future<void> _writes = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  bool _hasClock = false;
  bool _completedSaved = false;
  Object? _autoSkippedMarkerKey;
  bool _markerSkipPending = false;

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations.then((_) => operation());
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> open(MediaIdentity identity) => _serialize(
    () => _open(
      identity,
      transientTarget:
          _failedTransientTarget?.identity == identity ||
              (engine == null && error != null && item?.identity == identity)
          ? _failedTransientTarget
          : null,
    ),
  );
  Future<void> openTransient(TransientPlaybackTarget target) =>
      _serialize(() => _open(target.identity, transientTarget: target));

  Future<void> _open(
    MediaIdentity identity, {
    EmbyVideoQuality targetQuality = EmbyVideoQuality.source,
    Duration? at,
    bool force = false,
    bool autoplay = true,
    bool fullTimeline = false,
    TransientPlaybackTarget? transientTarget,
  }) async {
    lastOpenSucceeded = false;
    if (_closed || _closing != null) return;
    if (!force &&
        item?.identity == identity &&
        error == null &&
        engine != null) {
      lastOpenSucceeded = true;
      return;
    }
    _cancelOnlineSubtitles();
    final previous = engine;
    final previousLoop = force && item?.identity == identity
        ? _precision.value.loop
        : const PlaybackLoopState();
    final wasPlaying = clock.playing;
    final trace = diagnostics?.begin();
    final previousTrace = _trace;
    trace?.event('open_begin');
    VideoEngine? candidate;
    String? candidateLease;
    TransientFileAccess? candidateAccess;
    final requestedTarget =
        transientTarget ??
        (item?.identity == identity ? _transientTarget : null);
    _checkpoint?.cancel();
    loading = true;
    previewFrames.attach(null);
    transitionMessage = null;
    notifyListeners();
    try {
      trace?.stage('source_lookup');
      var target = requestedTarget;
      if (target?.local == true) {
        candidateAccess = await TransientFileAccess.acquire(
          target!.location,
          bookmark: target.securityBookmark,
        );
        await target.validate();
        target = target.withBookmark(candidateAccess.bookmark);
        final indexed = await indexedFileIdentity(sources, target.location);
        if (indexed != null) {
          identity = indexed;
          target = null;
        }
      }
      final selected = target?.item ?? await sources.media(identity);
      final source = target != null
          ? null
          : await sources.source(identity.sourceId, includeCounts: false);
      trace?.event('source_selected', code: source?.kind.name ?? 'temporary');
      if (selected.isSeries ||
          selected.type == 'music' ||
          selected.type == 'photo') {
        throw const SourceFailure('请选择一个视频播放。');
      }
      String resource;
      String? localPath;
      String? nextCacheWarning;
      trace?.stage('preferences');
      final nextHistoryEpoch = target != null
          ? ''
          : await records.historyEpoch(identity);
      final record = target != null
          ? PlaybackRecord(identity: identity)
          : await records.read(identity);
      late final PlaybackOptions nextOptions;
      late final VideoSubtitleStyle nextStyle;
      late final VideoTimingSettings nextTiming;
      late final VideoDisplaySettings nextDisplay;
      late final bool loopCurrentItem;
      late final VideoMarkerSkipBehavior markerSkipBehavior;
      late final String? audioPreference, subtitlePreference;
      late final String subtitleLanguage;
      late final VideoEndAction action;
      late final double? rate;
      late final double volume, volumeBoost;
      var nextScreenshotMode = VideoScreenshotMode.subtitles;
      var nextKeyboardShortcuts = VideoKeyboardShortcuts();
      var nextColors = VideoColorAdjustments.neutral;
      String? nextSubtitleWarning;
      String? nextDisplayWarning;
      String? nextColorWarning;
      var nextSharpen = VideoSharpenMode.off;
      String? nextSharpenWarning;
      var nextEqualizer = const VideoEqualizerSettings();
      String? nextEqualizerWarning;
      var nextPerformance = const VideoPerformanceSettings();
      String? nextPerformanceWarning;
      var nextRender = const VideoRenderSettings();
      String? nextRenderWarning;
      await preferences.readPlaybackSnapshot(selected, () async {
        nextOptions = await preferences.options;
        nextStyle = await preferences.subtitleStyle;
        nextTiming = await preferences.timing;
        nextDisplay = await preferences.displaySettings;
        nextKeyboardShortcuts = await preferences.keyboardShortcuts;
        try {
          nextScreenshotMode = await preferences.screenshotMode;
        } catch (error, stack) {
          trace?.failure('screenshot_settings_read_failed', error, stack);
        }
        try {
          nextRender = await preferences.renderSettings;
        } catch (error, stack) {
          trace?.failure('render_settings_read_failed', error, stack);
          nextRenderWarning = '未能读取去色带和 HDR 映射设置，已使用默认值，视频仍可播放。';
        }
        try {
          nextPerformance = await preferences.performanceSettings;
        } catch (error, stack) {
          trace?.failure('performance_settings_read_failed', error, stack);
          nextPerformanceWarning = '未能读取播放性能设置，已使用默认值，视频仍可播放。';
        }
        try {
          nextSharpen = await preferences.sharpenMode;
        } catch (error, stack) {
          trace?.failure('sharpen_settings_read_failed', error, stack);
          nextSharpenWarning = '未能读取锐化设置，已使用默认值，视频仍可播放。';
        }
        try {
          nextEqualizer = await preferences.equalizerSettings;
        } catch (error, stack) {
          trace?.failure('equalizer_settings_read_failed', error, stack);
          nextEqualizerWarning = '未能读取均衡器设置，已使用默认值，视频仍可播放。';
        }
        try {
          nextColors = await preferences.colorAdjustments;
        } catch (error, stack) {
          trace?.failure('color_settings_read_failed', error, stack);
          nextColorWarning = '未能读取画面色彩设置，已使用默认值，视频仍可播放。';
        }
        loopCurrentItem = await preferences.loopCurrentItem;
        markerSkipBehavior = await preferences.markerSkipBehavior;
        audioPreference = await preferences.audio(selected);
        subtitlePreference = await preferences.subtitle(selected);
        subtitleLanguage = await preferences.subtitleLanguage;
        action = await preferences.endAction;
        rate = nextOptions.rememberRate
            ? await preferences.rate(selected)
            : null;
        volume = await preferences.number('videoVolume', 80);
        volumeBoost = await preferences.number('videoVolumeBoost', 1);
      });
      final resume =
          at ??
          record.resume(
            remember: nextOptions.rememberPosition,
            rewindSeconds: nextOptions.rewindSeconds,
          );
      var streamOffset = Duration.zero;
      String? playSessionId;
      if (target != null) {
        trace?.stage(target.local ? 'local_resource' : 'stream_resource');
        resource = target.location;
        localPath = target.local ? target.location : null;
      } else if (source!.kind.isFileSource) {
        trace?.stage('local_resource');
        localPath = p.normalize(
          p.joinAll([source.location, ...p.posix.split(identity.localId)]),
        );
        if (!p.isWithin(source.location, localPath) ||
            !await sources.isReachable(source) ||
            !await File(localPath).exists()) {
          throw const SourceFailure('媒体文件不存在，可能是 NAS 未挂载、移动硬盘断开，或文件已被移动。');
        }
        resource = localPath;
      } else if (source.kind == MediaSourceKind.url) {
        trace?.stage('stream_resource');
        resource = await UrlVideoRepository(sources).location(identity);
      } else if (source.kind.isRemoteVideoSource && emby != null) {
        ({String path, String lease})? cached;
        if (!force) {
          trace?.stage('cache_lookup');
          try {
            cached = await cache?.acquire(identity);
          } catch (error, stack) {
            trace?.failure('cache_fallback', error, stack);
            // A disconnected cache volume must not prevent online playback.
            // Keep its manifest intact so reconnecting the disk restores it.
            nextCacheWarning = '本地缓存读取失败，已尝试在线播放。请检查缓存目录或磁盘连接。';
          }
        }
        if (cached != null) {
          candidateLease = cached.lease;
          resource = localPath = cached.path;
        } else {
          trace?.stage('emby_resource');
          playSessionId = newEmbyIdentity();
          // A suffix generated at the resume point cannot loop the entire
          // film or an A point before that offset. Request a full timeline for
          // native loop controls, while still opening at the user's position.
          final resourceStart =
              !targetQuality.original &&
                  (fullTimeline ||
                      loopCurrentItem ||
                      previousLoop.start != null)
              ? Duration.zero
              : resume;
          resource = (await emby!.preparePlayback(
            selected,
            quality: targetQuality,
            start: resourceStart,
            playSessionId: playSessionId,
          )).uri.toString();
          if (!targetQuality.original && resourceStart.inMilliseconds > 1000) {
            streamOffset = resourceStart;
          }
        }
      } else {
        throw const SourceFailure('此媒体源尚不支持播放。');
      }
      trace?.event(
        'resource_ready',
        remote: localPath == null,
        cached: candidateLease != null,
      );
      trace?.stage('queue_and_preferences');
      final sidecars = localPath == null
          ? <SidecarSubtitle>[]
          : await SidecarSubtitle.find(localPath);
      final nextQueue = await _queueFor(selected);
      if (previous != null) {
        trace?.stage('previous_checkpoint');
        try {
          await previous.pause();
        } catch (_) {
          /* Save last valid clock. */
        }
        await save(completed: clock.completed);
        if (saveError != null) {
          trace?.event('open_aborted', code: 'checkpoint_failed');
          return;
        }
      }
      if (_closed || _closing != null) return;
      final current = candidate = createEngine();
      if (current is DiagnosableVideoEngine) {
        (current as DiagnosableVideoEngine).diagnosticTrace = trace;
      }
      trace?.stage('performance_configuration');
      try {
        if (current is VideoPerformanceEngine) {
          await (current as VideoPerformanceEngine).setPerformanceSettings(
            nextPerformance,
          );
        } else if (nextPerformance != const VideoPerformanceSettings()) {
          nextPerformanceWarning = '此播放后端暂不支持已保存的播放性能设置。';
        }
      } catch (error, stack) {
        trace?.failure(
          'performance_settings_initialization_failed',
          error,
          stack,
        );
        nextPerformanceWarning = '播放性能设置未能应用，视频仍可播放，请重新调整。';
      }
      trace?.stage('decoder_load');
      await current
          .open(resource, streamOffset > Duration.zero ? Duration.zero : resume)
          .timeout(const Duration(seconds: 25));
      if (current.clock.error != null) throw StateError(current.clock.error!);
      trace?.stage('playback_configuration');
      await current.setVolume(
        force
            ? clock.volume
            : nextOptions.useLaunchVolume
            ? nextOptions.launchVolume
            : volume.clamp(0, 100),
      );
      await current.setPitchCorrection(nextOptions.pitchCorrection);
      await current.setRate(
        force ? clock.rate : rate ?? nextOptions.defaultRate,
      );
      await current.setVolumeBoost(volumeBoost.clamp(1, 2));
      try {
        await current.setSubtitleDelay(nextTiming.subtitleDelay);
        if (current is VideoSubtitleSettingsEngine) {
          final settings = current as VideoSubtitleSettingsEngine;
          await settings.setSubtitleStyle(nextStyle);
          await settings.setAudioDelay(nextTiming.audioDelay);
          await settings.setSubtitleScale(nextTiming.subtitleScale);
          await settings.setSubtitlePosition(nextTiming.subtitlePosition);
        } else if (!nextStyle.isStandard ||
            nextTiming.audioDelay != 0 ||
            nextTiming.subtitleScale != 1 ||
            nextTiming.subtitlePosition != 100) {
          nextSubtitleWarning = '此播放后端暂不支持已保存的字幕样式或同步设置。';
        }
      } catch (error, stack) {
        trace?.failure('subtitle_settings_initialization_failed', error, stack);
        nextSubtitleWarning = '部分字幕或音画同步设置未能应用，视频仍可播放，请重新调整。';
      }
      final precisionEngine = current is VideoTimelineEngine
          ? current as VideoTimelineEngine
          : null;
      try {
        if (current is VideoDisplayEngine) {
          await (current as VideoDisplayEngine).setDisplaySettings(nextDisplay);
        } else if (nextDisplay != const VideoDisplaySettings()) {
          nextDisplayWarning = '此播放后端暂不支持已保存的画面显示设置。';
        }
      } catch (error, stack) {
        trace?.failure('display_settings_initialization_failed', error, stack);
        nextDisplayWarning = '部分画面显示设置未能应用，视频仍可播放，请重新调整。';
      }
      try {
        if (current is VideoSharpenEngine) {
          await (current as VideoSharpenEngine).setSharpenMode(nextSharpen);
        } else if (nextSharpen != VideoSharpenMode.off) {
          nextSharpenWarning = '此播放后端暂不支持已保存的锐化设置。';
        }
      } catch (error, stack) {
        trace?.failure('sharpen_settings_initialization_failed', error, stack);
        nextSharpenWarning = '锐化设置未能应用，视频仍可播放，请重新调整。';
      }
      try {
        if (current is VideoEqualizerEngine) {
          await (current as VideoEqualizerEngine).setEqualizerSettings(
            nextEqualizer,
          );
        } else if (nextEqualizer.filterGraph != null) {
          nextEqualizerWarning = '此播放后端暂不支持已保存的均衡器设置。';
        }
      } catch (error, stack) {
        trace?.failure(
          'equalizer_settings_initialization_failed',
          error,
          stack,
        );
        nextEqualizerWarning = '均衡器设置未能应用，视频仍可播放，请重新调整。';
      }
      try {
        if (current is VideoRenderEngine) {
          await (current as VideoRenderEngine).setRenderSettings(nextRender);
        } else if (nextRender != const VideoRenderSettings()) {
          nextRenderWarning = '此播放后端暂不支持已保存的去色带或 HDR 映射设置。';
        }
      } catch (error, stack) {
        if (error is VideoRenderUnavailable) {
          // Inactive defaults need no warning. User actions still fail,
          // including default-valued field edits, so an unsupported renderer
          // cannot overwrite other saved preferences.
          if (nextRender != const VideoRenderSettings()) {
            trace?.event(
              'render_settings_unavailable',
              code: 'software_renderer',
            );
            nextRenderWarning = '当前纯软件渲染不支持已保存的去色带或 HDR 映射；偏好已保留，视频仍可播放。';
          }
        } else {
          trace?.failure('render_settings_initialization_failed', error, stack);
          nextRenderWarning = '去色带或 HDR 映射设置未能应用，视频仍可播放，请重新调整。';
        }
      }
      try {
        if (current is VideoColorEngine) {
          await (current as VideoColorEngine).setColorAdjustments(nextColors);
        } else if (!nextColors.isNeutral) {
          nextColorWarning = '此播放后端暂不支持已保存的画面色彩设置。';
        }
      } catch (error, stack) {
        trace?.failure('color_settings_initialization_failed', error, stack);
        nextColorWarning = '画面色彩设置未能应用，视频仍可播放，请重新调整。';
      }
      if (precisionEngine != null) {
        await precisionEngine.setLoopCurrentItem(loopCurrentItem);
        await precisionEngine.setABLoop(previousLoop.start, previousLoop.end);
      }
      if (_closed || _closing != null) return;
      // Commit only after the target can actually decode. Until this point a
      // rejected target leaves the old session, clocks and controls intact.
      trace?.stage('previous_release');
      await _release(
        save: false,
        preserveTransient:
            isTransientPlayback(selected.identity) &&
            item?.identity == selected.identity,
      );
      engine = current;
      _trace = trace;
      candidate = null;
      item = selected;
      _transientTarget = target;
      _failedTransientTarget = null;
      _fileAccess = candidateAccess;
      candidateAccess = null;
      keyboardShortcuts = nextKeyboardShortcuts;
      onlineSubtitleResults = const [];
      onlineSubtitleError = null;
      _historyEpoch = nextHistoryEpoch;
      filePath = localPath;
      screenshotMode = nextScreenshotMode;
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
      _previewResource = VideoPreviewResource(
        identity: identity,
        location: resource,
        offset: streamOffset,
        cached: _cacheLease != null,
      );
      _previewIssueCodes.clear();
      _previewTraceAttempts = 0;
      _didGeneratePreview = false;
      _playSessionId = playSessionId;
      _reportedStart = false;
      _lastReport = null;
      syncError = null;
      sidecarSubtitles = sidecars;
      serverSubtitles = const [];
      serverSubtitlePaths.clear();
      downloadedOnlineSubtitlePaths.clear();
      subtitleError = null;
      queue = nextQueue;
      endAction = action;
      options = nextOptions;
      error = null;
      saveError = null;
      final settingsWarning = [
        nextSubtitleWarning,
        nextDisplayWarning,
        nextColorWarning,
        nextSharpenWarning,
        nextEqualizerWarning,
        nextPerformanceWarning,
        nextRenderWarning,
      ].whereType<String>().join(' ');
      controlError = settingsWarning.isEmpty ? null : settingsWarning;
      _readDisplaySettings(current);
      _readColorAdjustments(current);
      _readSharpenMode(current);
      _readEqualizerSettings(current);
      _readPerformanceSettings(current);
      _readRenderSettings(current);
      _readSubtitleSettings(current);
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
      if (precisionEngine != null) {
        _chapterSubscription = precisionEngine.chapterChanges.listen((_) {
          if (engine == current && !loading) {
            unawaited(refreshTimeline());
          }
        });
      }
      _subscription = current.changes.listen(
        (value) {
          if (engine == current) _observe(value);
        },
        onError: (Object e) {
          trace?.failure('clock_stream_failed', e, StackTrace.current);
          error = '视频播放失败，请检查文件或重新打开。';
          loading = false;
          notifyListeners();
        },
      );
      notifyListeners();
      tracks.value = current.tracks;
      trace?.stage('timeline');
      try {
        await _precision.attach(
          identity,
          precisionEngine,
          offset: streamOffset,
          duration: streamOffset == Duration.zero
              ? current.clock.duration
              : Duration(milliseconds: selected.remote?.durationMs ?? 0),
          loop: PlaybackLoopState(
            loopCurrentItem: loopCurrentItem,
            start: previousLoop.start,
            end: previousLoop.end,
          ),
          skipBehavior: markerSkipBehavior,
          position: current.clock.position + streamOffset,
        );
      } catch (error, stack) {
        trace?.failure('timeline_initialization_failed', error, stack);
        controlError = '章节或书签读取失败，可以刷新后重试。';
      }
      try {
        trace?.stage('track_preferences');
        await _applyTrackPreferences(current);
      } catch (error, stack) {
        trace?.failure('track_preferences_failed', error, stack);
        controlError = '音轨或字幕偏好未能应用，可以重新选择。';
      }
      // open() leaves the candidate paused, including while the old session
      // flushes its stop report. Wait for the committed surface to be rendered
      // and track preferences to be applied before allowing audio/time to run.
      trace?.stage('surface');
      await waitForSurface?.call().timeout(const Duration(seconds: 10));
      if (_closed || _closing != null) return;
      trace?.stage('play');
      if (autoplay) await current.play();
      lastOpenSucceeded = true;
      loading = false;
      _observe(current.clock);
      trace?.event(
        'open_succeeded',
        durationMs: current.clock.duration.inMilliseconds,
      );
      try {
        trace?.stage('queue_records');
        await _refreshQueueRecords();
      } catch (error, stack) {
        trace?.failure('queue_records_failed', error, stack);
        transitionMessage = '剧集观看状态读取失败，请重试。';
      }
      trace?.stage('playback');
    } catch (e, stack) {
      trace?.failure(
        'open_failed',
        e,
        stack,
        issue: e is EmbyFailure
            ? PlaybackIssue('emby_${e.kind.name}', status: e.status)
            : null,
      );
      final message = e is SourceFailure
          ? e.message
          : PlaybackIssue.from(e).message;
      if (previous != null && engine == previous) {
        _trace = previousTrace;
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
        _failedTransientTarget = requestedTarget;
        try {
          await _release(save: false);
        } catch (error, stack) {
          trace?.failure('failed_engine_release_failed', error, stack);
        }
      }
    } finally {
      // A cleanup error must not hide the original failure or keep loading set.
      try {
        if (candidate != null) await candidate.dispose();
      } catch (error, stack) {
        trace?.failure('candidate_dispose_failed', error, stack);
      }
      try {
        if (candidateLease != null) await cache?.release(candidateLease);
      } catch (error, stack) {
        trace?.failure('cache_release_failed', error, stack);
      }
      trace?.event('open_finished');
      try {
        await candidateAccess?.release();
      } catch (error, stack) {
        trace?.failure('file_access_release_failed', error, stack);
      }
      loading = false;
      previewFrames.attach(_previewResource);
      _updateMarkerSkip();
      if (!_closed && engine != null && _hasClock && error == null) {
        _startCheckpoints();
      }
      if (!_closed) notifyListeners();
    }
  }

  Future<void> _refreshQueueRecords() async {
    if (transient) {
      queueRecords = const {};
      return;
    }
    queueRecords = Map.unmodifiable(
      await records.readMany(queue.items.map((i) => i.identity)),
    );
  }

  Future<VideoQueue> _queueFor(IndexedMedia selected) async {
    if (isTransientPlayback(selected.identity)) {
      return VideoQueue(sequence: [selected], items: [selected]);
    }
    return VideoQueue.forItem(
      selected,
      await sources.playbackQueueCandidates(selected),
    );
  }

  Future<void> refreshQueue() => _serialize(() async {
    if (_closed || loading || item == null) return;
    try {
      queue = await _queueFor(item!);
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
      final fresh = await _queueFor(item!);
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
    if (_precision.value.loop.loopCurrentItem ||
        _precision.value.loop.hasRange) {
      // Native loops normally never emit terminal EOF. Do not advance the
      // episode queue if a backend delivers one at the loop boundary.
      await _seek(
        _precision.value.loop.hasRange
            ? _precision.value.loop.start!
            : Duration.zero,
      );
      await engine?.play();
      return;
    }
    switch (endAction) {
      case VideoEndAction.holdLastFrame:
        break;
      case VideoEndAction.closeWindow:
        closeRequests.value++;
      case VideoEndAction.nextEpisode:
        if (item == null) return;
        final fresh = await _queueFor(item!);
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
        networkBytesPerSecond: value.networkBytesPerSecond,
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
      if (error == null) _trace?.event('playback_failed', code: 'engine_error');
      error = item?.remote == null && !(transient && filePath == null)
          ? '视频播放失败：${value.error}'
          : '远程视频播放失败，请检查连接或重新打开。';
      loading = false;
      notifyListeners();
    }
    if (!loading && value.duration > Duration.zero) _hasClock = true;
    _updateMarkerSkip();
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
    final trace = _trace;
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
    final epoch = _historyEpoch;
    final value = snapshot ?? clock;
    final next = _reports.then((_) async {
      try {
        final cleared = epoch != await records.historyEpoch(selected.identity);
        if (cleared && phase != EmbyPlaybackPhase.stopped) return;
        await emby!.reportPlayback(
          selected,
          playSessionId: sessionId,
          transcoding: !quality.original,
          phase: phase,
          position: cleared
              ? Duration.zero
              : value.completed
              ? value.duration
              : value.position,
          duration: value.duration,
          paused: !value.playing,
        );
        if (item?.identity == selected.identity) syncError = null;
      } catch (error, stack) {
        trace?.failure('remote_report_failed', error, stack);
        if (item?.identity == selected.identity) {
          syncError = '远程媒体库播放状态同步失败，本机播放进度仍会保存。';
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
    final trace = _trace;
    final selected = item;
    final value = clock;
    final policy = options;
    final epoch = _historyEpoch;
    if (!_hasClock ||
        selected == null ||
        isTransientPlayback(selected.identity) ||
        value.duration <= Duration.zero) {
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
          historyEpoch: epoch,
          autoMarkWatched: policy.autoMarkWatched,
          watchedThreshold: await preferences.watchedThreshold,
        );
        saveError = null;
      } catch (error, stack) {
        trace?.failure('checkpoint_failed', error, stack);
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
    } catch (exception, stack) {
      _trace?.failure('command_failed', exception, stack);
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
  Future<void> seek(Duration target) => _command(() => _seek(target));
  Future<void> _seek(Duration target) async {
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
  }

  Future<void> refreshTimeline() => _controls(() async {
    await _precision.refresh();
    _updateMarkerSkip();
  }, failureMessage: '章节或书签读取失败，请重试。');

  Future<int?> analyzeIntroOutroMarkers({
    ScanCancellation? cancellation,
  }) async {
    final identity = item?.identity;
    final expectedEngine = engine;
    int? count;
    await _controls(() async {
      if (identity == null ||
          item?.identity != identity ||
          engine != expectedEngine) {
        return;
      }
      try {
        cancellation?.check();
        count = await _precision.analyzeIntroOutroMarkers(
          duration: clock.duration,
          cancellation: cancellation,
        );
        _updateMarkerSkip();
      } on ScanCancelled {
        // Cancellation is not a player failure and never disposes its decoder.
      }
    }, failureMessage: '片头片尾检测失败，请重试。');
    return count;
  }

  Future<void> reviewAutomaticPlaybackMarker(
    PlaybackMarker marker, {
    required bool accepted,
  }) {
    final expectedEngine = engine;
    return _controls(() async {
      if (item?.identity != marker.identity || engine != expectedEngine) return;
      await _precision.reviewAutomatic(marker, accepted: accepted);
      _updateMarkerSkip();
    }, failureMessage: '更新自动标记失败，请重试。');
  }

  Future<void> addBookmark({Duration? at}) => _controls(
    () => _precision.addManual(PlaybackMarkerKind.bookmark, _markerTime(at)),
    failureMessage: '书签保存失败，请重试。',
  );
  Future<void> addChapter({Duration? at}) => _controls(
    () => _precision.addManual(PlaybackMarkerKind.chapter, _markerTime(at)),
    failureMessage: '章节保存失败，请重试。',
  );
  Future<void> deletePlaybackMarker(String id) => _controls(() async {
    await _precision.deleteManual(id);
    _updateMarkerSkip();
  }, failureMessage: '播放标记删除失败，请重试。');
  Future<void> setMarkerBoundary(
    PlaybackMarkerKind kind, {
    required bool isStart,
    Duration? at,
  }) {
    final identity = item?.identity;
    final time = at ?? clock.position;
    return _controls(() async {
      if (item?.identity != identity) return;
      await _precision.setBoundary(
        kind,
        isStart: isStart,
        at: _markerTime(time),
      );
      _updateMarkerSkip();
    }, failureMessage: '片头或片尾标记保存失败，请重试。');
  }

  Future<void> setMarkerSkipBehavior(VideoMarkerSkipBehavior behavior) =>
      _controls(() async {
        await _precision.setSkipBehavior(behavior);
        _autoSkippedMarkerKey = null;
        _updateMarkerSkip();
      }, failureMessage: '片头片尾跳过设置保存失败，请重试。');

  Future<void> skipPlaybackMarker(String id) {
    final identity = item?.identity;
    return _controls(() async {
      if (item?.identity != identity) return;
      _precision.updatePosition(clock.position);
      final marker = _precision.value.activeSkipMarker;
      if (marker == null || marker.id != id) return;
      await _seek(marker.end!);
    }, failureMessage: '片头或片尾跳过失败，请重试。');
  }

  Object _skipMarkerKey(PlaybackMarker marker) =>
      (marker.identity, marker.id, marker.start, marker.end);

  void _updateMarkerSkip() {
    final enabled =
        !_closed &&
        _closing == null &&
        !loading &&
        engine != null &&
        error == null &&
        !clock.completed &&
        clock.duration > Duration.zero;
    _precision.updatePosition(clock.position, enabled: enabled);
    final marker = _precision.value.activeSkipMarker;
    if (marker == null) {
      _autoSkippedMarkerKey = null;
      return;
    }
    final key = _skipMarkerKey(marker);
    if (!enabled ||
        _precision.value.skipBehavior != VideoMarkerSkipBehavior.automatic ||
        _autoSkippedMarkerKey == key ||
        _markerSkipPending) {
      return;
    }
    // Latch before scheduling, not after seek: several clock events may arrive
    // while another serialized operation (including Emby I/O) is still pending.
    _autoSkippedMarkerKey = key;
    _markerSkipPending = true;
    final expectedEngine = engine;
    final expectedIdentity = item?.identity;
    unawaited(
      _serialize(() async {
        try {
          if (_closed ||
              _closing != null ||
              loading ||
              error != null ||
              engine != expectedEngine ||
              item?.identity != expectedIdentity ||
              _precision.value.skipBehavior !=
                  VideoMarkerSkipBehavior.automatic) {
            return;
          }
          _precision.updatePosition(clock.position);
          final active = _precision.value.activeSkipMarker;
          if (active == null ||
              _skipMarkerKey(active) != key ||
              clock.completed) {
            return;
          }
          await _seek(active.end!);
        } catch (_) {
          // Keep the decoder alive, and do not retry on every clock tick. Leaving
          // the interval rearms the original per-entry automatic-skip policy.
          if (!_closed) {
            controlError = '片头或片尾自动跳过失败，可以手动重试。';
            notifyListeners();
          }
        } finally {
          _markerSkipPending = false;
          if (!_closed) _updateMarkerSkip();
        }
      }),
    );
  }

  Duration _markerTime(Duration? at) => Duration(
    microseconds: (at ?? clock.position).inMicroseconds.clamp(
      0,
      clock.duration.inMicroseconds,
    ),
  );

  Future<void> seekPlaybackMarker(String id) => _controls(() async {
    final marker = _precision.value.markers
        .where((m) => m.id == id && m.isAcceptedForPlayback)
        .firstOrNull;
    if (marker != null) await _seek(marker.start);
  });

  Future<void> _ensureFullLoopTimeline() async {
    if (_streamOffset <= Duration.zero ||
        quality.original ||
        filePath != null) {
      return;
    }
    await _open(
      item!.identity,
      targetQuality: quality,
      at: clock.position,
      force: true,
      autoplay: clock.playing,
      fullTimeline: true,
    );
    if (_streamOffset > Duration.zero || engine == null || error != null) {
      throw StateError('Full loop timeline could not be prepared');
    }
  }

  Future<void> setLoopCurrentItem(bool enabled) => _controls(() async {
    if (enabled) await _ensureFullLoopTimeline();
    await _precision.setLoopCurrentItem(enabled);
  }, failureMessage: '单片循环设置失败，请重试。');
  Future<void> cycleABLoop() => _controls(() async {
    final position = _markerTime(null);
    await _ensureFullLoopTimeline();
    await _precision.cycleABLoop(position);
  }, failureMessage: 'A–B 循环设置失败，请重试。');
  Future<void> clearABLoop() => _controls(
    () => _precision.clearABLoop(),
    failureMessage: 'A–B 循环清除失败，请重试。',
  );
  Future<void> stepFrame({bool backward = false}) => _controls(() async {
    final current = engine;
    if (current is! VideoTimelineEngine) {
      throw StateError('Frame control unavailable');
    }
    await (current as VideoTimelineEngine).stepFrame(backward: backward);
    await save();
    unawaited(_reportRemote(EmbyPlaybackPhase.progress, force: true));
  }, failureMessage: '逐帧操作失败，请重试。');
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
  Future<void> _controls(
    Future<void> Function() action, {
    String failureMessage = '播放器设置操作失败，请检查文件或输出设备后重试。',
  }) => _serialize(() async {
    if (_closed || _closing != null || loading || engine == null) return;
    try {
      await action();
      controlError = null;
    } catch (exception, stack) {
      _trace?.failure('control_failed', exception, stack);
      controlError = exception is SubtitleSettingsRollbackFailure
          ? '设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoDisplayRollbackFailure
          ? '画面设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoColorRollbackFailure
          ? '色彩设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoSharpenRollbackFailure
          ? '锐化设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoEqualizerRollbackFailure
          ? '均衡器设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoPerformanceRollbackFailure
          ? '播放性能设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoRenderRollbackFailure
          ? '去色带或 HDR 映射设置未能完全恢复，视频仍可播放，请重新应用设置。'
          : exception is VideoRenderUnavailable
          ? VideoRenderUnavailable.message
          : failureMessage;
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
    } catch (exception, stack) {
      _trace?.failure('subtitle_inventory_failed', exception, stack);
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
        final temporary = await RuntimeStoragePaths.current.temporary();
        await temporary.create(recursive: true);
        _subtitleDirectory ??= await temporary.createTemp(
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
  void _readSubtitleSettings(VideoEngine current) {
    if (current is VideoSubtitleSettingsEngine) {
      final settings = current as VideoSubtitleSettingsEngine;
      subtitleStyle = settings.subtitleStyle;
      timing = settings.timing;
    } else {
      subtitleStyle = VideoSubtitleStyle.standard;
      timing = VideoTimingSettings(subtitleDelay: current.tracks.subtitleDelay);
    }
    tracks.value = current.tracks;
  }

  Future<void> setSubtitleStyle(VideoSubtitleStyle style) =>
      updateSubtitleStyle((_) => style);

  void _readDisplaySettings(VideoEngine current) {
    displaySettings = current is VideoDisplayEngine
        ? (current as VideoDisplayEngine).displaySettings
        : const VideoDisplaySettings();
  }

  void _readColorAdjustments(VideoEngine current) {
    colorAdjustments = current is VideoColorEngine
        ? (current as VideoColorEngine).colorAdjustments
        : VideoColorAdjustments.neutral;
  }

  void _readSharpenMode(VideoEngine current) {
    sharpenMode = current is VideoSharpenEngine
        ? (current as VideoSharpenEngine).sharpenMode
        : VideoSharpenMode.off;
  }

  void _readPerformanceSettings(VideoEngine current) {
    performanceSettings = current is VideoPerformanceEngine
        ? (current as VideoPerformanceEngine).performanceSettings
        : const VideoPerformanceSettings();
  }

  void _readRenderSettings(VideoEngine current) {
    renderSettings = current is VideoRenderEngine
        ? (current as VideoRenderEngine).renderSettings
        : const VideoRenderSettings();
  }

  /// Share persistence rollback, while each caller retains normalization,
  /// capability checks and the exact point at which engine state is refreshed.
  Future<void> _changeSetting<T>(
    T before,
    T next,
    Future<void> Function(T) apply,
    Future<void> Function(T) remember, {
    required void Function() refresh,
    required String rollbackScope,
    required Object rollbackFailure,
    bool refreshAfterApplyFailure = true,
  }) async {
    // Subtitle/timing setters originally apply before their refresh guard.
    if (!refreshAfterApplyFailure) await apply(next);
    try {
      if (refreshAfterApplyFailure) await apply(next);
      try {
        await remember(next);
      } catch (error, stack) {
        try {
          await apply(before);
        } catch (rollback, rollbackStack) {
          _trace?.failure(
            '${rollbackScope}_settings_rollback_failed',
            rollback,
            rollbackStack,
          );
          throw rollbackFailure;
        }
        Error.throwWithStackTrace(error, stack);
      }
    } finally {
      refresh();
    }
  }

  Future<void> updateRenderSettings({
    VideoDebandMode? debandMode,
    VideoToneMappingMode? toneMappingMode,
  }) => _controls(() async {
    final current = engine!;
    if (current is! VideoRenderEngine) {
      throw UnsupportedError('Render settings unavailable');
    }
    final render = current as VideoRenderEngine;
    final before = render.renderSettings;
    final next = before.copyWith(
      debandMode: debandMode,
      toneMappingMode: toneMappingMode,
    );
    await _changeSetting(
      before,
      next,
      render.setRenderSettings,
      preferences.rememberRenderSettings,
      refresh: () => _readRenderSettings(current),
      rollbackScope: 'render',
      rollbackFailure: const VideoRenderRollbackFailure(),
    );
  }, failureMessage: '去色带或 HDR 映射设置未能应用或保存，视频仍可播放，请重试。');

  Future<void> updatePerformanceSettings({
    VideoHardwareDecodingMode? hardwareDecodingMode,
    bool? memoryBufferingEnabled,
  }) => _controls(() async {
    final current = engine!;
    if (current is! VideoPerformanceEngine) {
      throw UnsupportedError('Playback performance settings are unavailable');
    }
    final performance = current as VideoPerformanceEngine;
    // Merge only when this queued operation runs, after preceding edits/save
    // rollbacks, so a buffer toggle cannot overwrite a just-selected hwdec.
    final before = performance.performanceSettings;
    final next = before.copyWith(
      hardwareDecodingMode: hardwareDecodingMode,
      memoryBufferingEnabled: memoryBufferingEnabled,
    );
    await _changeSetting(
      before,
      next,
      performance.setPerformanceSettings,
      preferences.rememberPerformanceSettings,
      refresh: () => _readPerformanceSettings(current),
      rollbackScope: 'performance',
      rollbackFailure: const VideoPerformanceRollbackFailure(),
    );
  }, failureMessage: '播放性能设置未能应用或保存，视频仍可播放，请重试。');

  void _readEqualizerSettings(VideoEngine current) {
    equalizerSettings = current is VideoEqualizerEngine
        ? (current as VideoEqualizerEngine).equalizerSettings
        : const VideoEqualizerSettings();
  }

  Future<void> updateEqualizerSettings({
    bool? enabled,
    VideoEqualizerPreset? preset,
  }) => _controls(() async {
    final current = engine!;
    if (current is! VideoEqualizerEngine) {
      throw UnsupportedError('Audio equalizer is unavailable');
    }
    final equalizer = current as VideoEqualizerEngine;
    // Merge inside the serial operation, after prior edits or their rollback.
    final before = equalizer.equalizerSettings;
    final next = before.copyWith(enabled: enabled, preset: preset);
    await _changeSetting(
      before,
      next,
      equalizer.setEqualizerSettings,
      preferences.rememberEqualizerSettings,
      refresh: () => _readEqualizerSettings(current),
      rollbackScope: 'equalizer',
      rollbackFailure: const VideoEqualizerRollbackFailure(),
    );
  }, failureMessage: '均衡器设置未能应用或保存，视频仍可播放，请重试。');

  Future<void> setSharpenMode(VideoSharpenMode mode) => _controls(() async {
    final current = engine!;
    if (current is! VideoSharpenEngine) {
      throw UnsupportedError('Sharpen is unavailable');
    }
    final sharpen = current as VideoSharpenEngine;
    final before = sharpen.sharpenMode;
    await _changeSetting(
      before,
      mode,
      sharpen.setSharpenMode,
      preferences.rememberSharpenMode,
      refresh: () => _readSharpenMode(current),
      rollbackScope: 'sharpen',
      rollbackFailure: const VideoSharpenRollbackFailure(),
    );
  }, failureMessage: '锐化设置未能应用或保存，视频仍可播放，请重试。');

  Future<void> updateColorAdjustments(
    VideoColorAdjustments Function(VideoColorAdjustments current) update,
  ) => _controls(() async {
    final current = engine!;
    if (current is! VideoColorEngine) {
      throw UnsupportedError('Video color adjustments are unavailable');
    }
    final colors = current as VideoColorEngine;
    final before = colors.colorAdjustments;
    final next = update(before).normalized;
    await _changeSetting(
      before,
      next,
      colors.setColorAdjustments,
      preferences.rememberColorAdjustments,
      refresh: () => _readColorAdjustments(current),
      rollbackScope: 'color',
      rollbackFailure: const VideoColorRollbackFailure(),
    );
  }, failureMessage: '色彩设置未能应用或保存，视频仍可播放，请重试。');

  Future<void> updateDisplaySettings(
    VideoDisplaySettings Function(VideoDisplaySettings current) update,
  ) => _controls(() async {
    final current = engine!;
    if (current is! VideoDisplayEngine) {
      throw UnsupportedError('Video display settings are unavailable');
    }
    final display = current as VideoDisplayEngine;
    final before = display.displaySettings;
    final next = update(before);
    await _changeSetting(
      before,
      next,
      display.setDisplaySettings,
      preferences.rememberDisplaySettings,
      refresh: () => _readDisplaySettings(current),
      rollbackScope: 'display',
      rollbackFailure: const VideoDisplayRollbackFailure(),
    );
  }, failureMessage: '画面设置未能应用或保存，视频仍可播放，请重试。');

  /// Evaluate a user's field edit only when its serialized operation runs.
  /// Earlier edits may still be applying or rolling back when this is queued.
  Future<void> updateSubtitleStyle(
    VideoSubtitleStyle Function(VideoSubtitleStyle current) update,
  ) => _controls(() async {
    final current = engine!;
    if (current is! VideoSubtitleSettingsEngine) {
      throw UnsupportedError('Subtitle style is unavailable');
    }
    final settings = current as VideoSubtitleSettingsEngine;
    final before = settings.subtitleStyle;
    final next = update(before).normalized;
    await _changeSetting(
      before,
      next,
      settings.setSubtitleStyle,
      preferences.rememberSubtitleStyle,
      refresh: () => _readSubtitleSettings(current),
      rollbackScope: 'subtitle',
      rollbackFailure: const SubtitleSettingsRollbackFailure(),
      refreshAfterApplyFailure: false,
    );
  }, failureMessage: '字幕样式未能应用或保存，视频仍可播放，请重试。');

  Future<void> _timingSetting(
    String key,
    double value,
    double Function(VideoTimingSettings) previous,
    Future<void> Function(VideoEngine, double) apply,
  ) => _controls(() async {
    final current = engine!;
    _readSubtitleSettings(current);
    final before = previous(timing);
    await _changeSetting(
      before,
      value,
      (next) => apply(current, next),
      (next) => preferences.rememberNumber(key, next),
      refresh: () => _readSubtitleSettings(current),
      rollbackScope: 'subtitle',
      rollbackFailure: const SubtitleSettingsRollbackFailure(),
      refreshAfterApplyFailure: false,
    );
  }, failureMessage: '音画同步设置未能应用或保存，视频仍可播放，请重试。');

  VideoSubtitleSettingsEngine _subtitleSettings(VideoEngine current) {
    if (current is VideoSubtitleSettingsEngine) {
      return current as VideoSubtitleSettingsEngine;
    }
    throw UnsupportedError('Subtitle settings are unavailable');
  }

  Future<void> audioDelay(double seconds) => _timingSetting(
    'videoDefaultAudioDelay',
    VideoTimingSettings.syncDelay(seconds),
    (s) => s.audioDelay,
    (e, v) => _subtitleSettings(e).setAudioDelay(v),
  );
  Future<void> subtitleDelay(double seconds) => _timingSetting(
    'videoDefaultSubtitleDelay',
    VideoTimingSettings.syncDelay(seconds),
    (s) => s.subtitleDelay,
    (e, v) => e.setSubtitleDelay(v),
  );
  Future<void> subtitleScale(double scale) => _timingSetting(
    'videoDefaultSubtitleScale',
    VideoTimingSettings.scale(scale),
    (s) => s.subtitleScale,
    (e, v) => _subtitleSettings(e).setSubtitleScale(v),
  );
  Future<void> subtitlePosition(double position) => _timingSetting(
    'videoDefaultSubtitlePosition',
    VideoTimingSettings.position(position),
    (s) => s.subtitlePosition,
    (e, v) => _subtitleSettings(e).setSubtitlePosition(v),
  );
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

  Future<void> _release({
    bool save = true,
    bool preserveTransient = false,
  }) async {
    _previewResource = null;
    previewFrames.attach(null);
    _checkpoint?.cancel();
    _checkpoint = null;
    final current = engine;
    if (current == null) return;
    _keyboardHoldRate = null;
    _keyboardHoldEngine = null;
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
    await _chapterSubscription?.cancel();
    _chapterSubscription = null;
    _precision.detach();
    if (!preserveTransient) {
      _precision.repository.clearTransient();
    }
    _autoSkippedMarkerKey = null;
    if (_playSessionId != null) {
      await _reportRemote(EmbyPlaybackPhase.stopped, force: true);
      await _reports;
      _playSessionId = null;
    }
    try {
      await current.dispose();
    } finally {
      engine = null;
      final access = _fileAccess;
      _fileAccess = null;
      _transientTarget = null;
      try {
        await access?.release();
      } catch (error, stack) {
        _trace?.failure('file_access_release_failed', error, stack);
      }
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
      downloadedOnlineSubtitlePaths.clear();
      if (directory != null &&
          p.isWithin(
            p.normalize(
              (await RuntimeStoragePaths.current.temporary()).absolute.path,
            ),
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
    _cancelOnlineSubtitles();
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
      _failedTransientTarget = null;
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
    _disposed = true;
    _cancelOnlineSubtitles();
    previewFrames.dispose();
    _checkpoint?.cancel();
    _cacheHeartbeat?.cancel();
    timeline.dispose();
    volumeLevel.dispose();
    playbackRate.dispose();
    tracks.dispose();
    _precision.dispose();
    closeRequests.dispose();
    super.dispose();
  }
}
