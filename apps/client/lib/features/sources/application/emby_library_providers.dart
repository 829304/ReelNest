import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../home/data/home_search_worker.dart';

import '../data/emby_library_repository.dart';
import '../domain/emby_library.dart';
import '../../playback/data/player_preferences_repository.dart';
import 'source_providers.dart';
import 'emby_providers.dart';

final embyLibraryRepositoryProvider = Provider<EmbyLibraryRepository>(
  (ref) => EmbyLibraryRepository(ref.watch(sourceRepositoryProvider)),
);
final embySidebarSectionsProvider = FutureProvider.autoDispose
    .family<Set<EmbyVideoSection>, String>((ref, id) {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select((_) => sources.sourceViewRevision(id)),
      );
      return ref.watch(embyLibraryRepositoryProvider).sidebarSections(id);
    });
// Playback-window notifications and explicit retries invalidate this base.
final embyVideoContentProvider = FutureProvider.autoDispose
    .family<EmbyVideoSnapshot, String>((ref, id) {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select((_) => sources.sourceContentRevision(id)),
      );
      return ref.watch(embyLibraryRepositoryProvider).snapshot(id);
    });
final embyVideoSnapshotProvider = FutureProvider.autoDispose
    .family<EmbyVideoSnapshot, String>((ref, id) async {
      final sources = ref.watch(sourceRepositoryProvider);
      final repository = ref.watch(embyLibraryRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select(
          (_) => sources.libraryPreferenceRevision(id),
        ),
      );
      final base = await ref.watch(embyVideoContentProvider(id).future);
      if (!ref.mounted) throw const ScanCancelled();
      return repository.refreshPreferences(base);
    });
final videoLibrarySettingsProvider = FutureProvider.autoDispose
    .family<VideoLibrarySettings, EmbyVideoDestination>(
      (ref, id) => ref.watch(embyLibraryRepositoryProvider).settings(id),
    );
typedef VideoLibraryQuery = ({
  EmbyVideoDestination destination,
  VideoLibrarySettings settings,
});
final embyVideoResultsProvider = FutureProvider.autoDispose
    .family<List<VideoLibraryEntry>, VideoLibraryQuery>((ref, query) async {
      final cancellation = ScanCancellation();
      ref.onDispose(cancellation.cancel);
      final snapshot = await ref.watch(
        embyVideoSnapshotProvider(query.destination.sourceId).future,
      );
      cancellation.check();
      final threshold = await PlayerPreferencesRepository(
        ref.watch(sourceRepositoryProvider).database,
      ).watchedThreshold;
      cancellation.check();
      var scoped = snapshot.scope(query.destination);
      if (query.settings.cachedOnly) {
        final cached = await ref.watch(embyCachedVideosProvider.future);
        cancellation.check();
        final identities = cached.map((c) => c.identity).toSet();
        final parents = <MediaIdentity>{};
        for (final id in identities) {
          final parent = snapshot.entryFor(id)?.item.parentId;
          if (parent != null) {
            parents.add((sourceId: id.sourceId, localId: parent));
          }
        }
        scoped = scoped
            .where(
              (e) =>
                  identities.contains(e.item.identity) ||
                  (e.item.isSeries && parents.contains(e.item.identity)),
            )
            .toList();
      }
      final settings = query.settings;
      // Original defers search/filter work for large snapshots. Isolates receive
      // display models only, never a repository, credential, or HTTP client.
      if (scoped.length > 180) {
        return runHomeSearchWorker(
          () => filterVideoLibrary(scoped, settings, threshold),
          cancellation,
        );
      }
      return filterVideoLibrary(scoped, settings, threshold);
    });
