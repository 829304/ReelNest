import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../data/tmdb_artwork_store.dart';
import '../data/tmdb_client.dart';
import '../data/tmdb_settings_repository.dart';
import '../domain/tmdb_models.dart';
import 'tmdb_video_service.dart';

final tmdbSettingsRepositoryProvider = Provider<TmdbSettingsRepository>(
  (ref) => TmdbSettingsRepository(ref.watch(sourceRepositoryProvider).database),
);
final tmdbSettingsProvider =
    AsyncNotifierProvider<TmdbSettingsController, TmdbSettings>(
      TmdbSettingsController.new,
      retry: (_, _) => null,
    );

class TmdbSettingsController extends AsyncNotifier<TmdbSettings> {
  Future<void> _pending = Future.value();
  @override
  Future<TmdbSettings> build() =>
      ref.watch(tmdbSettingsRepositoryProvider).read();
  Future<void> _change(Future<void> Function(TmdbSettingsRepository) change) {
    final work = _pending.then((_) async {
      try {
        await future;
      } catch (_) {
        /* Explicit edits may repair configuration. */
      }
      if (!ref.mounted) throw const SourceFailure('设置页面已关闭。');
      final repository = ref.read(tmdbSettingsRepositoryProvider);
      await change(repository);
      final value = await repository.read();
      if (ref.mounted) state = AsyncData(value);
    });
    _pending = work.catchError((Object _) {});
    return work;
  }

  Future<void> saveCredential(String value) =>
      _change((repository) => repository.saveCredential(value));
  Future<void> setLanguage(String value) =>
      _change((repository) => repository.setLanguage(value));
}

final tmdbClientProvider = Provider<TmdbClient>((_) => TmdbClient());
final tmdbArtworkStoreProvider = Provider<TmdbArtworkStore>(
  (_) => TmdbArtworkStore(),
);
final tmdbMovieServiceProvider = Provider<TmdbVideoService>((ref) {
  final service = TmdbVideoService(
    sources: ref.watch(sourceRepositoryProvider),
    settings: ref.watch(tmdbSettingsRepositoryProvider),
    client: ref.watch(tmdbClientProvider),
    artwork: ref.watch(tmdbArtworkStoreProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
final tmdbMovieMetadataProvider = FutureProvider.autoDispose
    .family<TmdbMetadata?, MediaIdentity>((ref, identity) {
      ref.watch(sourceChangesProvider);
      return ref.watch(tmdbMovieServiceProvider).metadata(identity);
    }, retry: (_, _) => null);
final tmdbSeriesServiceProvider = Provider<TmdbVideoService>((ref) {
  final service = TmdbVideoService(
    sources: ref.watch(sourceRepositoryProvider),
    settings: ref.watch(tmdbSettingsRepositoryProvider),
    client: ref.watch(tmdbClientProvider),
    artwork: ref.watch(tmdbArtworkStoreProvider),
    kind: TmdbMediaKind.tv,
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
final tmdbSeriesMetadataProvider = FutureProvider.autoDispose
    .family<TmdbMetadata?, MediaIdentity>((ref, identity) {
      ref.watch(sourceChangesProvider);
      return ref.watch(tmdbSeriesServiceProvider).metadata(identity);
    }, retry: (_, _) => null);
final tmdbEpisodeMetadataProvider = FutureProvider.autoDispose
    .family<TmdbEpisodeMetadata?, MediaIdentity>((ref, identity) {
      ref.watch(sourceChangesProvider);
      return ref.watch(tmdbSeriesServiceProvider).episodeMetadata(identity);
    }, retry: (_, _) => null);
final tmdbArtworkFileProvider = FutureProvider.autoDispose.family<File, String>(
  (ref, reference) => ref.watch(tmdbArtworkStoreProvider).file(reference),
  retry: (_, _) => null,
);
