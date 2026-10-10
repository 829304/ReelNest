import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../domain/media_source.dart';
import '../../../player/media_kit_video_engine.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/application/emby_providers.dart';
import '../application/playback_providers.dart';
import '../application/playback_session.dart';
import 'video_player_page.dart';

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
  late final PlaybackSession _session;
  late final MediaIdentity _initial;
  bool _destroyed = false;
  MediaIdentity? _notifiedIdentity;
  @override
  void initState() {
    super.initState();
    _initial = _identity(widget.arguments);
    _session = PlaybackSession(
      sources: ref.read(sourceRepositoryProvider),
      records: ref.read(playbackRepositoryProvider),
      createEngine: MediaKitVideoEngine.new,
      emby: ref.read(embyConnectionProvider),
    );
    _session.addListener(_onPlaybackChanged);
    windowManager.addListener(this);
    unawaited(_configure());
  }

  void _onPlaybackChanged() {
    final identity = _session.item?.identity;
    if (!_session.loading &&
        _session.error == null &&
        identity != null &&
        identity != _notifiedIdentity) {
      _notifiedIdentity = identity;
      unawaited(_notifyMain());
    }
  }

  MediaIdentity _identity(Map<String, dynamic> args) => (
    sourceId: args['sourceId'] as String,
    localId: args['localId'] as String,
  );
  Future<void> _configure() async {
    await windowManager.setPreventClose(true);
    await widget.window.setWindowMethodHandler((call) async {
      if (call.method == 'play') {
        // A reused hidden/minimized window must render the surface commit
        // before open() can start playback and return to the caller.
        await widget.window.show();
        await windowManager.focus();
        final id = _identity(Map<String, dynamic>.from(call.arguments as Map));
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
    await windowManager.setMinimumSize(const Size(680, 382));
    await windowManager.setTitle('ReelNest');
    await windowManager.setSize(const Size(960, 540));
    await windowManager.center();
    await widget.window.show();
    await windowManager.focus();
  }

  Future<void> _notifyMain() async {
    try {
      await WindowController.fromWindowId(
        widget.arguments['mainWindowId'] as String,
      ).invokeMethod('playbackChanged').timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Main may already be closing. Progress is on disk. */
    }
  }

  Future<void> _destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    await _session.close();
    await _notifyMain();
    await ref.read(sourceRepositoryProvider).close();
    // window_manager.destroy posts WM_QUIT on Windows, which would exit
    // every engine. Close this native window after committing the checkpoint.
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void onWindowClose() =>
      unawaited(_page.currentState?.requestClose() ?? Future.value());
  @override
  void dispose() {
    windowManager.removeListener(this);
    _session.removeListener(_onPlaybackChanged);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: VideoPlayerPage(
      key: _page,
      identity: _initial,
      session: _session,
      closeWindow: _destroy,
      setFullscreen: windowManager.setFullScreen,
    ),
  );
}
