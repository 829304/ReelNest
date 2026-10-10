import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/emby/emby_client.dart';
import '../../../platform/secure_credential_store.dart';
import '../data/emby_connection_repository.dart';
import '../data/emby_sync_repository.dart';
import '../data/emby_detail_repository.dart';
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
  ),
);

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
      final cancellation = ScanCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .watch(embyConnectionProvider)
          .artwork(
            key.sourceId,
            key.itemId,
            backdrop: key.backdrop,
            index: key.index,
            maxWidth: key.width,
            cancellation: cancellation,
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
      final cancellation = ScanCancellation();
      ref.onDispose(cancellation.cancel);
      return ref
          .watch(embyConnectionProvider)
          .artwork(
            key.sourceId,
            key.itemId,
            backdrop: key.backdrop,
            cancellation: cancellation,
          );
    });
