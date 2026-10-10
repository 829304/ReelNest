import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/emby_library_repository.dart';
import '../domain/emby_library.dart';
import '../../playback/data/player_preferences_repository.dart';
import 'source_providers.dart';
import 'emby_providers.dart';

final embyLibraryRepositoryProvider = Provider<EmbyLibraryRepository>(
  (ref) => EmbyLibraryRepository(ref.watch(sourceRepositoryProvider)),
);
final embyVideoSnapshotProvider = FutureProvider.autoDispose
    .family<EmbyVideoSnapshot, String>((ref, id) {
      ref.watch(sourceChangesProvider);
      return ref.watch(embyLibraryRepositoryProvider).snapshot(id);
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
      final snapshot = await ref.watch(
        embyVideoSnapshotProvider(query.destination.sourceId).future,
      );
      final threshold = await PlayerPreferencesRepository(
        ref.watch(sourceRepositoryProvider).database,
      ).watchedThreshold;
      var scoped = snapshot.scope(query.destination);
      if (query.settings.cachedOnly) {
        final cached = await ref.watch(embyCachedVideosProvider.future);
        final identities = cached.map((c) => c.identity).toSet();
        final parents = snapshot.entries
            .where((e) => identities.contains(e.item.identity))
            .map((e) => e.item.parentId)
            .whereType<String>()
            .toSet();
        scoped = scoped
            .where(
              (e) =>
                  identities.contains(e.item.identity) ||
                  (e.item.isSeries &&
                      parents.contains(e.item.identity.localId)),
            )
            .toList();
      }
      final settings = query.settings;
      // Original defers search/filter work for large snapshots. Isolates receive
      // display models only, never a repository, credential, or HTTP client.
      if (scoped.length > 180) {
        return Isolate.run(
          () => filterVideoLibrary(scoped, settings, threshold),
        );
      }
      return filterVideoLibrary(scoped, settings, threshold);
    });
