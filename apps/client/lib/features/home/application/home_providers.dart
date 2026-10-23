import 'dart:async';
import 'dart:isolate';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../playback/data/player_preferences_repository.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/application/emby_providers.dart';
import '../data/home_repository.dart';
import '../domain/home_snapshot.dart';
import '../domain/home_recommendation.dart';

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref.watch(sourceRepositoryProvider)),
);
final homePlaybackRevisionsProvider =
    NotifierProvider<HomePlaybackRevisions, Map<String, int>>(
      HomePlaybackRevisions.new,
    );

class HomePlaybackRevisions extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => {};
  void refresh(Iterable<String> ids) => state = {
    ...state,
    for (final id in ids.toSet()) id: (state[id] ?? 0) + 1,
  };
}

final homeThresholdProvider = FutureProvider.autoDispose<double>((ref) {
  final sources = ref.watch(sourceRepositoryProvider);
  ref.watch(sourceChangesProvider.select((_) => sources.globalContentRevision));
  return PlayerPreferencesRepository(
    ref.watch(sourceRepositoryProvider).database,
  ).watchedThreshold;
});

typedef HomeQuery = ({String sourceId, HomeCollection collection, int offset});
final homeVideoPageProvider = FutureProvider.autoDispose
    .family<HomeVideoPage, HomeQuery>((ref, query) async {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select(
          (_) => sources.sourceViewRevision(query.sourceId),
        ),
      );
      ref.watch(
        homePlaybackRevisionsProvider.select(
          (values) => values[query.sourceId],
        ),
      );
      final threshold = await ref.watch(homeThresholdProvider.future);
      if (!ref.mounted) throw const ScanCancelled();
      return ref
          .watch(homeRepositoryProvider)
          .page(
            query.sourceId,
            query.collection,
            offset: query.offset,
            threshold: threshold,
          );
    });
final homeSourceStatsProvider = FutureProvider.autoDispose
    .family<HomeStats, String>((ref, id) async {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select((_) => sources.sourceViewRevision(id)),
      );
      ref.watch(homePlaybackRevisionsProvider.select((values) => values[id]));
      final threshold = await ref.watch(homeThresholdProvider.future);
      if (!ref.mounted) throw const ScanCancelled();
      return ref.watch(homeRepositoryProvider).stats(id, threshold);
    });

/// Refresh at local midnight and when returning from suspension across a day.
/// A timer never starts a scan or network synchronization.
final homeDateProvider = NotifierProvider.autoDispose<HomeDate, DateTime>(
  HomeDate.new,
);

class HomeDate extends Notifier<DateTime> with WidgetsBindingObserver {
  Timer? _timer;
  @override
  DateTime build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });
    _schedule();
    return DateTime.now();
  }

  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _timer = Timer(
      tomorrow.difference(now) + const Duration(seconds: 1),
      refresh,
    );
  }

  void refresh() {
    final now = DateTime.now();
    if (HomeRecommendationPolicy.daySeed(now) !=
        HomeRecommendationPolicy.daySeed(state)) {
      state = now;
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}

final homeRecommendationCandidatesProvider = FutureProvider.autoDispose
    .family<List<HomeVideo>, String>((ref, id) {
      final sources = ref.watch(sourceRepositoryProvider);
      ref.watch(
        sourceChangesProvider.select((_) => sources.sourceViewRevision(id)),
      );
      ref.watch(homePlaybackRevisionsProvider.select((values) => values[id]));
      return ref.watch(homeRepositoryProvider).recommendationCandidates(id);
    });

final homeOfflineIDsProvider = FutureProvider.autoDispose<Set<MediaIdentity>>((
  ref,
) {
  final cached = ref.watch(embyCachedVideosProvider).value ?? [];
  if (cached.isEmpty) return <MediaIdentity>{};
  final repository = ref.watch(sourceRepositoryProvider);
  ref.watch(sourceChangesProvider.select((_) => repository.contentRevision));
  return ref
      .watch(homeRepositoryProvider)
      .offlineParents(cached.map((c) => c.identity).toSet());
});

/// Observe each source separately: available local rows can render while a
/// different source is still loading/failing. Riverpod discards stale futures.
final homeRecommendationProvider =
    FutureProvider.autoDispose<HomeRecommendation>((ref) async {
      final now = ref.watch(homeDateProvider);
      final threshold = ref.watch(homeThresholdProvider).value ?? .9;
      final sources =
          ref.watch(sidebarSourcesProvider).value ?? const <MediaSource>[];
      final videos = <HomeVideo>[];
      final signals = <HomeVideo>[];
      for (final source in sources.where(HomeRepository.accepts)) {
        videos.addAll(
          (ref.watch(homeRecommendationCandidatesProvider(source.id)).value ??
                  [])
              .where((v) => _matchesRecommendationSource(v, source)),
        );
        signals.addAll(
          ref
                  .watch(
                    homeVideoPageProvider((
                      sourceId: source.id,
                      collection: HomeCollection.continueWatching,
                      offset: 0,
                    )),
                  )
                  .value
                  ?.items
                  .where((v) => _matchesRecommendationSource(v, source)) ??
              [],
        );
      }
      // File validation is an independent dependency; a disconnected cache disk
      // does not suppress online recommendations or block their first result.
      final Set<MediaIdentity> offline =
          sources.any(
            (s) => HomeRepository.accepts(s) && s.kind == MediaSourceKind.emby,
          )
          ? ref.watch(homeOfflineIDsProvider).value ?? {}
          : {};
      if (videos.length <= 180) {
        return HomeRecommendationPolicy.build(
          videos,
          now: now,
          threshold: threshold,
          playbackSignals: signals,
          offline: offline,
        );
      }
      // Coalesce startup dependencies / bursts of browse notifications before
      // spawning a large scoring job. Retired providers never start that job.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!ref.mounted) throw const ScanCancelled();
      return Isolate.run(
        () => HomeRecommendationPolicy.build(
          videos,
          now: now,
          threshold: threshold,
          playbackSignals: signals,
          offline: offline,
        ),
      );
    });

bool _matchesRecommendationSource(HomeVideo video, MediaSource source) =>
    video.source.kind == source.kind &&
    video.source.location == source.location &&
    (source.kind != MediaSourceKind.emby ||
        source.options.selectedEmbyLibraryIDs.isEmpty ||
        source.options.selectedEmbyLibraryIDs.contains(
          video.item.remote?.libraryId,
        ));

/// One bounded foreground page only if an unsynchronized source has no cache.
/// This never starts a complete scan, and cancellation belongs to this view.
final homeSeedProvider = FutureProvider.autoDispose.family<void, String>((
  ref,
  id,
) async {
  final repository = ref.watch(homeRepositoryProvider);
  final source = await repository.sources.source(id, includeCounts: false);
  if (!ref.mounted) return;
  if (!await repository.needsSeed(source) || !ref.mounted) return;
  final token = ScanCancellation();
  ref.onDispose(token.cancel);
  final cursor = await ref
      .read(embyBrowseRepositoryProvider)
      .open(id, cancellation: token);
  token.check();
  if (cursor.hasMore) await cursor.next();
});

class HomeCollectionState {
  const HomeCollectionState({
    this.items = const [],
    this.loading = false,
    this.partial = false,
    this.errors = const {},
  });
  final List<HomeVideo> items;
  final bool loading, partial;
  final Map<String, String> errors;
}

final homeCollectionProvider = Provider.autoDispose
    .family<HomeCollectionState, HomeCollection>((ref, collection) {
      if (collection == HomeCollection.seriesRecommendations ||
          collection == HomeCollection.highRated ||
          collection == HomeCollection.recentSeries) {
        final board = ref.watch(homeRecommendationProvider);
        final sources = ref.watch(sidebarSourcesProvider);
        final errors = <String, String>{};
        var loading = board.isLoading || sources.isLoading;
        for (final source in (sources.value ?? <MediaSource>[]).where(
          HomeRepository.accepts,
        )) {
          final candidates = ref.watch(
            homeRecommendationCandidatesProvider(source.id),
          );
          loading |= candidates.isLoading;
          if (candidates.hasError) {
            errors[source.id] =
                '${source.name}：${sourceErrorMessage(candidates.error!)}';
          }
        }
        if (board.hasError) {
          errors['recommendation'] = sourceErrorMessage(board.error!);
        }
        return HomeCollectionState(
          items: collection == HomeCollection.seriesRecommendations
              ? board.value?.series ?? []
              : collection == HomeCollection.highRated
              ? board.value?.highRated ?? []
              : board.value?.recentSeries ?? [],
          loading: loading,
          errors: errors,
        );
      }
      final sources = ref.watch(sidebarSourcesProvider);
      final values = sources.value ?? const <MediaSource>[];
      final items = <HomeVideo>[];
      final errors = <String, String>{};
      var loading = sources.isLoading;
      var partial = false;
      for (final source in values.where(HomeRepository.accepts)) {
        partial |=
            source.kind == MediaSourceKind.emby && source.lastScan == null;
        final page = ref.watch(
          homeVideoPageProvider((
            sourceId: source.id,
            collection: collection,
            offset: 0,
          )),
        );
        items.addAll(page.value?.items ?? []);
        loading |= page.isLoading;
        if (page.hasError) {
          errors[source.id] =
              '${source.name}：${sourceErrorMessage(page.error!)}';
        }
      }
      return HomeCollectionState(
        items: HomeVideoPolicy.merge(collection, items, limit: 36),
        loading: loading,
        partial: partial,
        errors: errors,
      );
    });
