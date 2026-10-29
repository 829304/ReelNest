import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../domain/media_source.dart';
import '../../../player/media_kit_video_engine.dart';
import '../../../player/playback_diagnostics.dart';
import '../../../player/video_engine.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/application/emby_providers.dart';
import '../application/playback_providers.dart';
import '../application/playback_session.dart';
import '../application/transient_playback_providers.dart';
import '../application/external_playback_providers.dart';
import '../domain/transient_playback_target.dart';
import 'video_player_page.dart';
import 'transient_playback_controls.dart';
import 'player_window_coordinator.dart';

class PlayerWindowApp extends ConsumerStatefulWidget {
  const PlayerWindowApp({
    required this.window,
    required this.arguments,
    super.key,
  });
  final WindowController window;
  final Map<String, dynamic> arguments;
  @override
  ConsumerState<PlayerWindowApp> createState() => _PlayerWindowAppState();
}

class _PlayerWindowAppState extends ConsumerState<PlayerWindowApp>
    with WindowListener {
  final _page = GlobalKey<VideoPlayerPageState>();
  final _diagnostics = PlaybackDiagnostics();
  late final PlaybackSession _session;
  late final PlayerWindowCoordinator _windowCoordinator;
  late final MediaIdentity _initial;
  TransientPlaybackTarget? _initialTransient;
  bool _destroyed = false;
  MediaIdentity? _notifiedIdentity;
  final _playedSourceIds = <String>{};
  Timer? _rememberWindowTimer;
  Future<void> _windowGeometry = Future.value();
  MediaIdentity? _windowGeometryIdentity;
  double? _windowGeometryAspect;
  bool _windowConfigured = false;
  @override
  void initState() {
    super.initState();
    _initial = _identity(widget.arguments);
    if (widget.arguments['transient'] is Map) {
      _initialTransient = TransientPlaybackTarget.fromJson(
        Map<String, dynamic>.from(widget.arguments['transient'] as Map),
      );
    }
    _session = PlaybackSession(
      sources: ref.read(sourceRepositoryProvider),
      records: ref.read(playbackRepositoryProvider),
      createEngine: MediaKitVideoEngine.new,
      emby: ref.read(embyConnectionProvider),
      cache: ref.read(embyCacheProvider),
      diagnostics: _diagnostics,
    );
    _windowCoordinator = PlayerWindowCoordinator(
      const DesktopPlayerWindowGateway(),
    );
    _session.addListener(_onPlaybackChanged);
    _session.timeline.addListener(_onTimelineChanged);
    windowManager.addListener(this);
    unawaited(
      _configure().catchError((Object error, StackTrace stack) {
        _diagnostics.begin().failure(
          'window_configuration_failed',
          error,
          stack,
        );
      }),
    );
  }

  void _onPlaybackChanged() {
    if (_windowCoordinator.preferredAlwaysOnTop !=
        _session.options.alwaysOnTop) {
      unawaited(
        _windowCoordinator
            .setPreferredAlwaysOnTop(_session.options.alwaysOnTop)
            .catchError((_) {}),
      );
    }
    final identity = _session.item?.identity;
    if (identity != null && !isTransientPlayback(identity)) {
      _playedSourceIds.add(identity.sourceId);
    }
    if (!_session.loading &&
        _session.error == null &&
        identity != null &&
        identity != _notifiedIdentity) {
      _notifiedIdentity = identity;
      unawaited(_notifyMain());
    }
    _syncWindowGeometry();
  }

  void _onTimelineChanged() => _syncWindowGeometry();

  double _resolvedVideoAspect() {
    final engine = _session.engine;
    if (engine case final VideoAspectEngine aspectEngine) {
      final decoded = aspectEngine.videoAspectRatio;
      if (decoded != null && decoded.isFinite && decoded > 0) return decoded;
    }
    final resolution = _session.item?.remote?.resolution;
    final match = resolution == null
        ? null
        : RegExp(r'(\d{2,5})\s*[x×*]\s*(\d{2,5})').firstMatch(resolution);
    final width = double.tryParse(match?.group(1) ?? '');
    final height = double.tryParse(match?.group(2) ?? '');
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  void _syncWindowGeometry() {
    if (!_windowConfigured || _destroyed) return;
    final identity = _session.item?.identity;
    if (identity == null) return;
    final aspect = _resolvedVideoAspect();
    final sameItem = identity == _windowGeometryIdentity;
    final sameAspect =
        _windowGeometryAspect != null &&
        (_windowGeometryAspect! - aspect).abs() < (sameItem ? .018 : .001);
    if (sameItem && sameAspect) return;
    _windowGeometryIdentity = identity;
    _windowGeometryAspect = aspect;
    _windowGeometry = _windowGeometry
        .then((_) => _windowCoordinator.applyMediaAspect(aspect))
        .catchError((Object error, StackTrace stack) {
          _diagnostics.begin().failure(
            'window_aspect_update_failed',
            error,
            stack,
          );
        });
  }

  MediaIdentity _identity(Map<String, dynamic> args) => (
    sourceId: args['sourceId'] as String,
    localId: args['localId'] as String,
  );
  Future<void> _configure() async {
    await windowManager.setPreventClose(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS,
    );
    await widget.window.setWindowMethodHandler((call) async {
      if (call.method == 'play') {
        // A reused hidden/minimized window must render the surface commit
        // before open() can start playback and return to the caller.
        await widget.window.show();
        await windowManager.focus();
        final id = _identity(Map<String, dynamic>.from(call.arguments as Map));
        final rawTarget = (call.arguments as Map)['transient'];
        if (rawTarget is Map) {
          await _session.openTransient(
            TransientPlaybackTarget.fromJson(
              Map<String, dynamic>.from(rawTarget),
            ),
          );
          if (!_session.lastOpenSucceeded) {
            throw PlatformException(
              code: 'playback_open_failed',
              message:
                  _session.transitionMessage ?? _session.error ?? '视频未能打开。',
            );
          }
          return null;
        }
        if (_session.item?.identity != id || _session.error != null) {
          await _session.open(id);
          await _notifyMain();
          if (_session.item?.identity != id || _session.error != null) {
            throw PlatformException(
              code: 'playback_open_failed',
              message: _session.saveError ?? _session.error ?? '视频未能打开。',
            );
          }
        }
        return null;
      }
      if (call.method == 'close') {
        await _page.currentState?.requestClose();
        return _destroyed;
      }
      if (call.method == 'playbackMarkersChanged') {
        final ids = List<String>.from(
          (call.arguments as Map)['sourceIds'] as List,
        );
        if (!_destroyed && ids.contains(_session.item?.identity.sourceId)) {
          await _session.refreshTimeline();
        }
        return null;
      }
      if (call.method == 'status') {
        return {
          'loading': _session.loading,
          'error': _session.error,
          'positionMs': _session.clock.position.inMilliseconds,
          'durationMs': _session.clock.duration.inMilliseconds,
          'playing': _session.clock.playing,
        };
      }
      throw MissingPluginException('Unknown player window method');
    });
    await windowManager.setTitle('ReelNest');
    var preferredWidth = PlayerWindowCoordinator.defaultPreferredWidth;
    try {
      preferredWidth = await _session.preferences.number(
        'videoPlayerPreferredWidth',
        PlayerWindowCoordinator.defaultPreferredWidth,
      );
    } catch (_) {
      // Opening playback must not depend on a non-essential preference read.
    }
    await _windowCoordinator.configureNormalWindow(
      aspect: 16 / 9,
      preferredWidth: preferredWidth,
    );
    _windowConfigured = true;
    await widget.window.show();
    await windowManager.focus();
    _syncWindowGeometry();
  }

  @override
  void onWindowResize() {
    _rememberWindowTimer?.cancel();
    _rememberWindowTimer = Timer(
      const Duration(milliseconds: 420),
      () => unawaited(_rememberWindowWidth()),
    );
  }

  Future<void> _rememberWindowWidth() async {
    if (!_windowConfigured ||
        _destroyed ||
        _windowCoordinator.miniMode ||
        _windowCoordinator.busy ||
        _windowCoordinator.applyingNormalBounds ||
        await windowManager.isFullScreen() ||
        await windowManager.isMaximized()) {
      return;
    }
    final width = (await windowManager.getBounds()).width;
    if (!width.isFinite ||
        width < PlayerWindowCoordinator.normalMinimumSize.width) {
      return;
    }
    _windowCoordinator.rememberPreferredWidth(width);
    try {
      await _session.preferences.rememberNumber(
        'videoPlayerPreferredWidth',
        width,
      );
    } catch (_) {
      // The current window remains usable even if preference persistence fails.
    }
  }

  @override
  void onWindowEnterFullScreen() => _page.currentState?.updateFullscreen(true);

  @override
  void onWindowLeaveFullScreen() => _page.currentState?.updateFullscreen(false);

  @override
  void onWindowMaximize() => _page.currentState?.updateMaximized(true);

  @override
  void onWindowUnmaximize() => _page.currentState?.updateMaximized(false);

  Future<void> _notifyMain() async {
    if (_playedSourceIds.isEmpty) return;
    try {
      await WindowController.fromWindowId(
            widget.arguments['mainWindowId'] as String,
          )
          .invokeMethod('playbackChanged', {
            // Include previous sources when reusing the player across libraries.
            'sourceIds': _playedSourceIds.toList(),
          })
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Main may already be closing. Progress is on disk. */
    }
  }

  Future<void> _destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    _rememberWindowTimer?.cancel();
    await _session.close();
    await _notifyMain();
    // Finish this engine's cache work while its database and plugins still live.
    // ProviderScope disposal does not await asynchronous onDispose callbacks.
    await ref.read(embyCacheProvider).dispose();
    ref.read(embyConnectionProvider).dispose();
    await ref.read(sourceRepositoryProvider).close();
    await _diagnostics.close();
    // window_manager.destroy posts WM_QUIT on Windows, which would exit
    // every engine. Close this native window after committing the checkpoint.
    windowManager.removeListener(this);
    _session.removeListener(_onPlaybackChanged);
    _session.timeline.removeListener(_onTimelineChanged);
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    if (!_destroyed) {
      unawaited(_page.currentState?.requestClose() ?? Future.value());
    }
  }

  @override
  void dispose() {
    _rememberWindowTimer?.cancel();
    windowManager.removeListener(this);
    _session.removeListener(_onPlaybackChanged);
    _session.timeline.removeListener(_onTimelineChanged);
    _windowCoordinator.dispose();
    _session.dispose();
    unawaited(_diagnostics.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: TransientMediaDropTarget(
      openFile: ref.read(transientPlaybackLauncherProvider).openFile,
      onError: (error) {
        _session.transitionMessage = error is SourceFailure
            ? error.message
            : '视频未能打开，请检查文件或重试。';
        if (mounted) setState(() {});
      },
      child: VideoPlayerPage(
        key: _page,
        identity: _initial,
        initialTransient: _initialTransient,
        session: _session,
        closeWindow: _destroy,
        setFullscreen: windowManager.setFullScreen,
        windowCoordinator: _windowCoordinator,
        openExternal: () async {
          final launcher = ref.read(externalPlaybackServiceProvider);
          final target = _session.transientTarget;
          if (target != null) {
            await launcher.openTransient(target);
          } else if (_session.item != null) {
            await launcher.openLibrary(_session.item!.identity);
          } else {
            await launcher.openLibrary(_initial);
          }
        },
      ),
    ),
  );
}
