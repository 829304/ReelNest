import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../features/playback/application/playback_providers.dart';
import '../features/playback/application/external_playback_providers.dart';
import '../features/playback/application/external_playback_service.dart';
import '../features/metadata/application/tmdb_providers.dart';
import '../features/metadata/application/tmdb_batch_providers.dart';
import '../features/metadata/application/metadata_supplement_providers.dart';
import '../features/metadata/application/automatic_tmdb_providers.dart';
import '../features/playback/domain/transient_playback_target.dart';
import '../domain/media_source.dart';
import '../features/playback/application/marker_analysis_providers.dart';
import '../features/playback/presentation/player_window_app.dart';
import '../features/sources/application/source_providers.dart';
import '../features/sources/application/emby_library_providers.dart';
import 'reelnest_app.dart';
import '../features/sources/application/automatic_scan_providers.dart';
import '../features/sources/application/emby_providers.dart';
import '../features/home/application/home_providers.dart';
import '../player/playback_diagnostics.dart';
import 'window_close_request.dart';
import '../storage/runtime_storage_paths.dart';
import 'portable_storage_failure_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    runApp(const ProviderScope(child: ReelNestApp()));
    return;
  }
  await windowManager.ensureInitialized();
  try {
    await RuntimeStoragePaths.current.prepare();
  } catch (_) {
    runApp(const PortableStorageFailureApp());
    return;
  }
  final window = await WindowController.fromCurrentEngine();
  final args = window.arguments.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(window.arguments) as Map<String, dynamic>;
  if (args['type'] == 'player') {
    runApp(
      ProviderScope(
        overrides: [
          externalPlaybackServiceProvider.overrideWithValue(
            ExternalWindowPlaybackLauncher(args['mainWindowId'] as String),
          ),
        ],
        child: PlayerWindowApp(window: window, arguments: args),
      ),
    );
    return;
  }
  final container = ProviderContainer();
  // Restore bounded task history asynchronously; never block first paint or
  // automatically re-run interrupted analysis jobs.
  container.read(markerAnalysisProvider);
  await windowManager.setPreventClose(true);
  windowManager.addListener(_MainWindowClose(container));
  await window.setWindowMethodHandler((call) async {
    if (call.method == 'openExternal') {
      try {
        final payload = Map<String, dynamic>.from(call.arguments as Map);
        final launcher = container.read(externalPlaybackServiceProvider);
        if (payload['transient'] is Map) {
          await launcher.openTransient(
            TransientPlaybackTarget.fromJson(
              Map<String, dynamic>.from(payload['transient'] as Map),
            ),
          );
        } else {
          await launcher.openLibrary((
            sourceId: payload['sourceId'] as String,
            localId: payload['localId'] as String,
          ));
        }
        return null;
      } catch (error) {
        throw PlatformException(
          code: 'external_failed',
          message: error is SourceFailure ? error.message : '外部播放器不可用，请检查设置。',
        );
      }
    }
    if (call.method == 'playbackChanged') {
      refreshPlaybackViews(
        container,
        List<String>.from((call.arguments as Map)['sourceIds'] as List),
      );
      return null;
    }
    throw UnsupportedError('Unknown main window method');
  });
  runApp(
    UncontrolledProviderScope(container: container, child: const ReelNestApp()),
  );
}

/// Player windows commit to the shared database through their own engine.
/// Reload the affected source snapshots as well as individual resume records.
void refreshPlaybackViews(
  ProviderContainer container,
  Iterable<String> sourceIds,
) {
  container.invalidate(playbackRecordProvider);
  container.invalidate(markerAnalysisEligibilityProvider);
  container.read(homePlaybackRevisionsProvider.notifier).refresh(sourceIds);
  container.read(embyOfflineProvider).request();
  for (final id in sourceIds.toSet()) {
    container.invalidate(embyVideoContentProvider(id));
  }
}

class _MainWindowClose with WindowListener {
  _MainWindowClose(this.container);
  final ProviderContainer container;
  bool closing = false;
  final diagnostics = PlaybackDiagnostics();
  @override
  void onWindowClose() => unawaited(_close());
  Future<void> _close() async {
    if (closing) return;
    closing = true;
    final trace = diagnostics.begin();
    trace.stage('main_window_close');
    try {
      for (final window in await WindowController.getAll()) {
        if (window.arguments.isEmpty) continue;
        final args = jsonDecode(window.arguments) as Map<String, dynamic>;
        if (args['type'] != 'player') continue;
        final closed = await requestChildWindowClose(
          request: () => window.invokeMethod<Object?>('close'),
          exists: () async => (await WindowController.getAll()).any(
            (w) => w.windowId == window.windowId,
          ),
          onError: (error, stack) =>
              trace.failure('child_close_reply_failed', error, stack),
        );
        if (!closed) {
          trace.event('main_close_deferred');
          return; // User kept the player open after a checkpoint failure.
        }
      }
      // Stop automatic matching before draining metadata jobs/database writes.
      if (container.exists(automaticTmdbMatcherProvider)) {
        await _step(
          trace,
          'close_automatic_tmdb',
          () => container.read(automaticTmdbMatcherProvider).dispose(),
        );
      }
      // Stop file-event producers before database shutdown; dispose does not
      // wait for slow filesystem discovery and late watcher starts self-cancel.
      if (container.exists(automaticSourceScannerProvider)) {
        await _step(
          trace,
          'close_file_monitors',
          () => container.read(automaticSourceScannerProvider).dispose(),
        );
      }
      // Cancel every active producer before waiting for any one to drain. Do
      // not construct unused services just because the application is exiting.
      await _step(trace, 'close_external_playback', () async {
        if (container.exists(externalPlaybackServiceProvider)) {
          final service = container.read(externalPlaybackServiceProvider);
          if (service is ExternalPlaybackService) await service.dispose();
        }
      });
      await _step(
        trace,
        'close_background_tasks',
        () => Future.wait<void>([
          if (container.exists(metadataSupplementServiceProvider))
            _closeTask(
              trace,
              'metadata_supplement',
              () => container.read(metadataSupplementServiceProvider).dispose(),
            ),
          if (container.exists(tmdbBatchServiceProvider))
            _closeTask(
              trace,
              'tmdb_batch',
              () => container.read(tmdbBatchServiceProvider).dispose(),
            ),
          if (container.exists(tmdbMovieServiceProvider))
            _closeTask(
              trace,
              'metadata',
              () => container.read(tmdbMovieServiceProvider).dispose(),
            ),
          if (container.exists(tmdbSeriesServiceProvider))
            _closeTask(
              trace,
              'series_metadata',
              () => container.read(tmdbSeriesServiceProvider).dispose(),
            ),
          if (container.exists(markerAnalysisProvider))
            _closeTask(
              trace,
              'marker_analysis',
              () => container.read(markerAnalysisProvider).dispose(),
            ),
          if (container.exists(embyOfflineProvider))
            _closeTask(
              trace,
              'offline',
              () => container.read(embyOfflineProvider).dispose(),
            ),
          if (container.exists(embyCacheProvider))
            _closeTask(
              trace,
              'cache',
              () => container
                  .read(embyCacheProvider)
                  .dispose(
                    onProgress: (phase, milliseconds) => trace.event(
                      'close_cache_$phase',
                      durationMs: milliseconds,
                    ),
                  ),
            ),
        ]),
      );
      await _step(trace, 'close_database', () async {
        if (container.exists(sourceRepositoryProvider)) {
          await container.read(sourceRepositoryProvider).close();
        }
      });
      await _step(trace, 'close_providers', () async => container.dispose());
      // Request a native close after the channel reply has returned. Posting
      // WM_QUIT via destroy skips the normal HWND shutdown sequence on Windows.
      await windowManager.setPreventClose(false);
      windowManager.removeListener(this);
      trace.event('native_main_close_requested');
      await diagnostics.flush().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      await windowManager.close();
    } catch (error, stack) {
      trace.failure('main_window_close_failed', error, stack);
    } finally {
      closing = false;
    }
  }

  Future<void> _step(
    PlaybackTrace trace,
    String stage,
    Future<void> Function() work,
  ) async {
    trace.stage(stage);
    try {
      await work();
    } catch (error, stack) {
      // Drain the remaining owners even if one cleanup fails; a failed cache
      // cleanup must not leave the native close interception permanently on.
      trace.failure('${stage}_failed', error, stack);
    }
  }

  Future<void> _closeTask(
    PlaybackTrace trace,
    String name,
    Future<void> Function() close,
  ) async {
    trace.event('close_${name}_begin');
    try {
      await close();
      trace.event('close_${name}_completed');
    } catch (error, stack) {
      trace.failure('close_${name}_failed', error, stack);
      rethrow;
    }
  }
}
