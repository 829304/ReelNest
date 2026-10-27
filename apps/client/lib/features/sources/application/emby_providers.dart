import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/runtime_observations.dart';
import '../../../api/emby/emby_client.dart';
import '../../../api/plex/plex_client.dart';
import '../../../platform/secure_credential_store.dart';
import '../data/emby_connection_repository.dart';
import '../data/emby_sync_repository.dart';
import '../data/emby_browse_repository.dart';
import '../data/emby_detail_repository.dart';
import '../data/emby_cache_repository.dart';
import '../data/emby_offline_repository.dart';
import '../data/artwork_image_pipeline.dart';
import '../data/artwork_decode_queue.dart';
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

final plexClientProvider = FutureProvider<EmbyClient>((ref) async {
  final device = await embyDeviceIdentity(
    ref.watch(sourceRepositoryProvider).database,
  );
  final client = PlexClient(deviceId: device);
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
    plexClient: ref.watch(plexClientProvider.future),
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

final embyArtworkDecodeProvider = Provider<ArtworkDecodeQueue>((ref) {
  final queue = ArtworkDecodeQueue();
  ref.onDispose(queue.dispose);
  return queue;
});

final embyCacheProvider = Provider<EmbyCacheRepository>((ref) {
  final cache = EmbyCacheRepository(
    decodeQueue: ref.watch(embyArtworkDecodeProvider),
    sources: ref.watch(sourceRepositoryProvider),
    connections: ref.watch(embyConnectionProvider),
  );
  void publishTasks() {
    ref.read(observedTasksProvider.notifier).replace('cache', [
      for (final task in cache.tasks.value.values)
        RuntimeTask(
          id: 'cache:${task.token}',
          group: 'cache',
          sourceId: task.item.identity.sourceId,
          title: '缓存 · ${task.item.cardTitle}',
          detail: task.error ?? '${task.received ~/ (1024 * 1024)} MB 已下载',
          stateTitle: switch (task.state) {
            VideoCacheTaskState.queued => '等待中',
            VideoCacheTaskState.downloading => '进行中',
            VideoCacheTaskState.paused => '已暂停',
            VideoCacheTaskState.saving => '正在保存',
            VideoCacheTaskState.complete => '已完成',
            VideoCacheTaskState.failed => '有错误',
            VideoCacheTaskState.cancelled => '已取消',
          },
          active: const {
            VideoCacheTaskState.queued,
            VideoCacheTaskState.downloading,
            VideoCacheTaskState.paused,
            VideoCacheTaskState.saving,
          }.contains(task.state),
          startedAt: DateTime.now(),
          isCache: true,
          hidesDetail: const {
            'private',
            'privateCollection',
          }.contains(task.item.type),
          progress: (task.expected ?? 0) > 0
              ? (task.received / task.expected!).clamp(0, 1)
              : null,
        ),
    ]);
  }

  cache.tasks.addListener(publishTasks);
  ref.onDispose(() => cache.tasks.removeListener(publishTasks));
  ref.onDispose(() => unawaited(cache.dispose()));
  return cache;
});
final embyImagePipelineProvider = Provider<ArtworkImagePipeline>((ref) {
  final pipeline = ArtworkImagePipeline(
    decodes: ref.watch(embyArtworkDecodeProvider),
  );
  ref.onDispose(pipeline.dispose);
  return pipeline;
});
final embyOfflineProvider = Provider<EmbyOfflineRepository>((ref) {
  final repository = EmbyOfflineRepository(
    sources: ref.watch(sourceRepositoryProvider),
    cache: ref.watch(embyCacheProvider),
  );
  ref.onDispose(() => unawaited(repository.dispose()));
  return repository;
});
final embyCacheStorageProvider = FutureProvider((ref) async {
  final sources = ref.watch(sourceRepositoryProvider);
  ref.watch(sourceChangesProvider.select((_) => sources.contentRevision));
  final summary = await ref.watch(embyCacheProvider).storageSummary();
  if (ref.mounted) {
    ref.read(observedVideoCacheStorageProvider.notifier).record(summary);
  }
  return summary;
});

final embyCachedVideosProvider = FutureProvider<List<CachedVideo>>((ref) {
  final sources = ref.watch(sourceRepositoryProvider);
  ref.watch(sourceChangesProvider.select((_) => sources.contentRevision));
  return ref.watch(embyCacheProvider).entries();
});
final embyCacheCandidatesProvider = FutureProvider.autoDispose
    .family<List<IndexedMedia>, MediaIdentity>((ref, id) async {
      ref.watch(sourceChangesProvider);
      final sources = ref.watch(sourceRepositoryProvider);
      final item = await sources.media(id);
      if (item.isSeries) {
        if (!ref.mounted) throw const ScanCancelled();
        await ref.watch(embySeriesEpisodesProvider(item.identity).future);
      }
      return item.isSeries ? await sources.indexedChildren(id) : [item];
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
            priority: ArtworkPriority.detail,
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

final embyBrowseRepositoryProvider = Provider<EmbyBrowseRepository>(
  (ref) => EmbyBrowseRepository(
    ref.watch(sourceRepositoryProvider),
    ref.watch(embyConnectionProvider),
  ),
);

/// This is deliberately independent of the full-index snapshot provider.
final embyBrowseCatalogProvider = FutureProvider.autoDispose
    .family<List<EmbyLibrary>, String>((ref, id) {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select((_) => sources.sourceContentRevision(id)),
      );
      final token = ScanCancellation();
      ref.onDispose(token.cancel);
      return ref.watch(embyBrowseRepositoryProvider).catalog(id, token);
    });

typedef EmbyPersonWorksKey = ({String sourceId, String personKey});

class EmbyPersonWorks {
  const EmbyPersonWorks(this.items, {this.complete = false, this.warning});
  final List<IndexedMedia> items;
  final bool complete;
  final String? warning;
}

final embyPersonWorksProvider = StreamProvider.autoDispose
    .family<EmbyPersonWorks, EmbyPersonWorksKey>((ref, key) async* {
      final token = ScanCancellation();
      ref.onDispose(token.cancel);
      final repository = ref.watch(embyDetailRepositoryProvider);
      final cached = await repository.cachedPersonWorks(
        key.sourceId,
        key.personKey,
      );
      token.check();
      if (cached.isNotEmpty) yield EmbyPersonWorks(cached);
      var cachedItems = cached;
      try {
        var items = <IndexedMedia>[];
        await for (final page in repository.personWorkPages(
          key.sourceId,
          key.personKey,
          cancellation: token,
        )) {
          token.check();
          items = page;
          // Partial pages cannot authoritatively remove already visible works.
          cachedItems =
              {
                for (final item in cachedItems) item.identity.localId: item,
                for (final item in page) item.identity.localId: item,
              }.values.toList()..sort((a, b) {
                final year = (b.year ?? 0).compareTo(a.year ?? 0);
                return year != 0 ? year : a.title.compareTo(b.title);
              });
          yield EmbyPersonWorks(cachedItems);
        }
        token.check();
        yield EmbyPersonWorks(items, complete: true);
      } on ScanCancelled {
        return;
      } catch (_) {
        token.check();
        if (cachedItems.isEmpty) rethrow;
        yield EmbyPersonWorks(cachedItems, warning: '服务器作品读取失败，仅显示已加载作品。');
      }
    });

final embySeriesEpisodesProvider = FutureProvider.autoDispose
    .family<void, MediaIdentity>((ref, id) {
      final token = ScanCancellation();
      ref.onDispose(token.cancel);
      return ref.watch(embyBrowseRepositoryProvider).loadEpisodes(id, token);
    });

Future<void> prepareEmbySeries(
  WidgetRef ref,
  Iterable<MediaIdentity> identities,
) async {
  final sources = ref.read(sourceRepositoryProvider);
  final browser = ref.read(embyBrowseRepositoryProvider);
  for (final id in identities.toSet()) {
    final item = await sources.media(id);
    if (item.isSeries &&
        item.remote != null &&
        (await sources.source(id.sourceId)).kind.isRemoteVideoSource) {
      await browser.loadEpisodes(id, ScanCancellation());
    }
  }
}
