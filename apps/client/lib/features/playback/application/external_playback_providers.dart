import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../platform/external_player_gateway.dart';
import '../../../platform/transient_file_access.dart';
import '../../../player/playback_diagnostics.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/application/emby_providers.dart';
import '../../sources/data/emby_cache_repository.dart';
import '../data/external_player_settings_repository.dart';
import '../domain/external_player_settings.dart';
import '../domain/transient_playback_target.dart';
import 'external_playback_service.dart';

final externalPlayerGatewayProvider = Provider<ExternalPlayerGateway>(
  (_) => DesktopExternalPlayerGateway(),
);
final externalPlayerSettingsRepositoryProvider =
    Provider<ExternalPlayerSettingsRepository>(
      (ref) => ExternalPlayerSettingsRepository(
        ref.watch(sourceRepositoryProvider).database,
      ),
    );
final externalPlayerSettingsProvider =
    AsyncNotifierProvider<
      ExternalPlayerSettingsController,
      ExternalPlayerSettings
    >(
      ExternalPlayerSettingsController.new,
      // Local malformed settings cannot recover through automatic retries.
      retry: (_, _) => null,
    );

class ExternalPlayerSettingsController
    extends AsyncNotifier<ExternalPlayerSettings> {
  Future<void> _pending = Future.value();
  @override
  Future<ExternalPlayerSettings> build() =>
      ref.watch(externalPlayerSettingsRepositoryProvider).load();
  Future<void> _change(
    Future<ExternalPlayerSettings> Function(ExternalPlayerSettings) change,
  ) {
    final operation = _pending.then((_) async {
      try {
        await future;
      } catch (_) {
        /* An explicit user edit can repair invalid settings. */
      }
      if (!ref.mounted) throw const SourceFailure('设置页面已关闭，请重试。');
      final repository = ref.read(externalPlayerSettingsRepositoryProvider);
      ExternalPlayerSettings current;
      try {
        current = await repository.load();
      } on SourceFailure {
        current = const ExternalPlayerSettings();
      }
      final next = await change(current);
      await repository.save(next);
      if (ref.mounted) state = AsyncData(next);
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> save(ExternalPlayerSettings next) => _change((_) async => next);
  Future<void> setMode(ExternalPlayerMode mode) =>
      _change((current) async => current.copyWith(mode: mode));
  Future<void> selectApplication(String? path) => _change((current) async {
    Uint8List? bookmark;
    if (path != null && path.isNotEmpty) {
      final access = await TransientFileAccess.acquire(path);
      try {
        await ref.read(externalPlayerGatewayProvider).validateApplication(path);
        bookmark = access.bookmark;
      } finally {
        await access.release();
      }
    }
    return ExternalPlayerSettings(
      mode: current.mode,
      applicationPath: path?.isEmpty == true ? null : path,
      applicationBookmark: bookmark,
    );
  });
}

final availableExternalPlayersProvider =
    FutureProvider<List<ExternalPlayerApplication>>((ref) async {
      final settings = await ref.watch(externalPlayerSettingsProvider.future);
      return ref
          .read(externalPlayerGatewayProvider)
          .availablePlayers(customPath: settings.applicationPath);
    });
final externalPlaybackServiceProvider = Provider<ExternalPlaybackLauncher>((
  ref,
) {
  EmbyCacheRepository? acquiredCache;
  EmbyCacheRepository cache() =>
      (acquiredCache ??= ref.read(embyCacheProvider))!;
  final service = ExternalPlaybackService(
    sources: ref.watch(sourceRepositoryProvider),
    settings: ref.watch(externalPlayerSettingsRepositoryProvider),
    gateway: ref.watch(externalPlayerGatewayProvider),
    acquireCache: (id) => cache().acquire(id),
    renewCache: (lease) => cache().renew(lease),
    releaseCache: (lease) => cache().release(lease),
    remoteResource: (item) async =>
        (await ref.read(embyConnectionProvider).preparePlayback(item)).uri
            .toString(),
    diagnostics: PlaybackDiagnostics(),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Child player windows keep all external playback ownership in the main engine.
class ExternalWindowPlaybackLauncher implements ExternalPlaybackLauncher {
  ExternalWindowPlaybackLauncher(this.mainWindowId);
  final String mainWindowId;
  Future<void> _send(Map<String, Object> payload) async {
    try {
      await WindowController.fromWindowId(mainWindowId)
          .invokeMethod('openExternal', payload)
          .timeout(const Duration(seconds: 30));
    } on PlatformException catch (error) {
      throw SourceFailure(
        error.code == 'external_failed'
            ? error.message ?? '外部播放器不可用。'
            : '无法联系主窗口，请重试。',
      );
    } catch (_) {
      throw const SourceFailure('无法联系主窗口，请重试。');
    }
  }

  @override
  Future<void> openLibrary(MediaIdentity identity) =>
      _send({'sourceId': identity.sourceId, 'localId': identity.localId});
  @override
  Future<void> openTransient(TransientPlaybackTarget target) =>
      _send({'transient': target.toJson()});
}
