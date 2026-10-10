import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/emby/emby_client.dart';
import '../../../platform/secure_credential_store.dart';
import '../data/emby_connection_repository.dart';
import '../data/emby_sync_repository.dart';
import '../data/emby_detail_repository.dart';
import '../data/emby_cache_repository.dart';
import '../data/emby_offline_repository.dart';
import '../../../domain/media_source.dart';
import 'source_providers.dart';

final embyCredentialStoresProvider = Provider<EmbyCredentialStores>(
  (_) =>
      (id) => SecureCredentialStore(
        key: 'io.github.user829304.reelnest.emby.source.$id',
      ),
);
final embyClientProvider = FutureProvider<EmbyClient>((ref) async {
  final device = await embyDeviceIdentity(
    ref.watch(sourceRepositoryProvider).database,
  );
  final client = EmbyClient(deviceId: device);
  if (!ref.mounted) {
    client.close();
    throw const SourceClosedException();
  }
  ref.onDispose(client.close);
  return client;
});

class SourceClosedException implements Exception {
  const SourceClosedException();
}

final embyConnectionProvider = Provider<EmbyConnectionRepository>((ref) {
  final repository = EmbyConnectionRepository(
    sources: ref.watch(sourceRepositoryProvider),
    client: ref.watch(embyClientProvider.future),
    stores: ref.watch(embyCredentialStoresProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final embySyncProvider = Provider<EmbySyncRepository>(
  (ref) => EmbySyncRepository(
    sources: ref.watch(sourceRepositoryProvider),
    connections: ref.watch(embyConnectionProvider),
    onSynced: (id) async {
      final repository = ref.read(sourceRepositoryProvider);
      final items = await repository.indexedSource(id);
      final source = await repository.source(id);
      if (ref.mounted) {
        await ref
            .read(embyCacheProvider)
            .prewarm(
              items,
              revision: source.lastScan?.millisecondsSinceEpoch ?? 0,
            );
      }
    },
  ),
);

final embyCacheProvider = Provider<EmbyCacheRepository>((ref) {
  final cache = EmbyCacheRepository(
    sources: ref.watch(sourceRepositoryProvider),
    connections: ref.watch(embyConnectionProvider),
  );
  ref.onDispose(() => unawaited(cache.dispose()));
  return cache;
});
final embyOfflineProvider = Provider<EmbyOfflineRepository>((ref) {
  final repository = EmbyOfflineRepository(
    sources: ref.watch(sourceRepositoryProvider),
    cache: ref.watch(embyCacheProvider),
  );
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});
final embyCacheStorageProvider = FutureProvider((ref) {
  ref.watch(sourceChangesProvider);
  return ref.watch(embyCacheProvider).storageSummary();
});

final embyCachedVideosProvider = FutureProvider<List<CachedVideo>>((ref) {
  ref.watch(sourceChangesProvider);
  return ref.watch(embyCacheProvider).entries();
});
final embyCacheCandidatesProvider = FutureProvider.autoDispose
    .family<List<IndexedMedia>, MediaIdentity>((ref, id) async {
      ref.watch(sourceChangesProvider);
      final sources = ref.watch(sourceRepositoryProvider);
      final item = await sources.media(id);
      return item.isSeries
          ? (await sources.indexedSource(id.sourceId))
                .where((i) => i.parentId == id.localId)
                .toList()
          : [item];
    });

final embyDetailRepositoryProvider = Provider<EmbyDetailRepository>(
  (ref) => EmbyDetailRepository(
    sources: ref.watch(sourceRepositoryProvider),
    connections: ref.watch(embyConnectionProvider),
  ),
);
typedef EmbyDetailKey = ({MediaIdentity identity, int refresh});
final embyDetailProvider = StreamProvider.autoDispose
    .family<EmbyDetailSnapshot, EmbyDetailKey>((ref, key) async* {
      final cancellation = ScanCancellation();
      ref.onDispose(cancellation.cancel);
      final repository = ref.watch(embyDetailRepositoryProvider);
      try {
        final cached = await repository.read(key.identity);
        cancellation.check();
        if (cached != null) yield cached;
        if (key.refresh == 0 && cached != null && repository.isFresh(cached)) {
          return;
        }
        yield await repository.load(
          key.identity,
          force: key.refresh > 0,
          cancellation: cancellation,
        );
      } on ScanCancelled {
        // Leaving the detail page cancels work without surfacing a page error.
        return;
      }
    });

typedef EmbyDetailImageKey = ({
  String sourceId,
  String itemId,
  bool backdrop,
  int index,
  int width,
  int revision,
});
final embyDetailImageProvider = FutureProvider.autoDispose
    .family<Uint8List, EmbyDetailImageKey>((ref, key) {
      return ref
          .watch(embyCacheProvider)
          .artwork(
            key.sourceId,
            key.itemId,
            backdrop: key.backdrop,
            index: key.index,
            width: key.width,
            revision: key.revision,
          );
    });

typedef EmbyArtworkKey = ({
  String sourceId,
  String itemId,
  bool backdrop,
  int revision,
});
final embyArtworkProvider = FutureProvider.autoDispose
    .family<Uint8List, EmbyArtworkKey>((ref, key) async {
      return ref
          .watch(embyCacheProvider)
          .artwork(
            key.sourceId,
            key.itemId,
            backdrop: key.backdrop,
            revision: key.revision,
          );
    });
