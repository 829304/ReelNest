import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/library/data/video_preferences_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/data/remote_index_writer.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late SourceRepository sources;
  late HomeRepository home;
  late VideoPreferencesRepository prefs;
  late MediaSource local, remote;
  Future<MediaSource> source(
    String id, {
    bool file = false,
    String mediaType = 'auto',
  }) async {
    final value = await sources.add(
      sourceId: id,
      kind: MediaSourceKind.emby,
      name: id,
      location: 'emby://fixture/$id',
    );
    await sources.database.customStatement(
      'UPDATE sources SET kind=?,media_type=?,last_scan=1 WHERE id=?',
      [file ? 'localFolder' : 'emby', mediaType, value.id],
    );
    return sources.source(id, includeCounts: false);
  }

  Future<void> seed(
    MediaSource source,
    String id, {
    String type = 'movie',
    String? parent,
    int? season,
    int? episode,
    bool series = false,
    bool favorite = false,
    String library = 'movies',
    String collection = 'movies',
    int position = 0,
    int duration = 100000,
    bool watched = false,
    int date = 1000,
    bool listed = false,
    double rating = 8,
    List<String> genres = const [],
  }) async {
    await sources.database.customStatement(
      '''INSERT INTO media(source_id,local_id,title,type,bytes,modified,
      identity_kind,parent_id,is_series,season_number,episode_number) VALUES (?,?,?,?,0,?,'video',?,?,?,?)''',
      [source.id, id, id, type, date, parent, series ? 1 : 0, season, episode],
    );
    if (source.kind == MediaSourceKind.emby) {
      await sources.database.customStatement(
        'INSERT INTO remote_media_metadata VALUES (?,?,?)',
        [
          source.id,
          id,
          jsonEncode({
            'externalId': id,
            'libraryId': library,
            'collectionType': collection,
            'favorite': favorite,
            'durationMs': duration,
            'positionMs': position,
            'watched': watched,
            'rating': rating,
            'genres': genres,
          }),
        ],
      );
    }
    await sources.database.customStatement(
      'INSERT INTO media_library_preferences VALUES (?,?,?,?,?)',
      [source.id, id, listed ? 1 : 0, rating / 2, date],
    );
    await sources.database.customStatement(
      'INSERT INTO playback_states VALUES (?,?,?,?,?,?)',
      [
        source.id,
        id,
        position,
        duration,
        watched ? 1 : 0,
        position > 0 ? date : 0,
      ],
    );
    if (favorite && source.kind.isFileSource) {
      await prefs.setLocalFavorite((sourceId: source.id, localId: id), true);
    }
  }

  setUp(() async {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    home = HomeRepository(sources);
    prefs = VideoPreferencesRepository(sources);
    local = await source('local', file: true);
    remote = await source('remote');
  });
  tearDown(() => sources.close());
  List<String> ids(HomeVideoPage page) =>
      page.items.map((v) => v.item.identity.localId).toList();

  test(
    'local and Emby share collections but identities and state remain isolated',
    () async {
      await seed(local, 'same', favorite: true, listed: true, position: 20000);
      await seed(remote, 'same', favorite: true, listed: true, position: 30000);
      final favorites = HomeVideoPolicy.merge(HomeCollection.favorites, [
        ...(await home.page(local.id, HomeCollection.favorites)).items,
        ...(await home.page(remote.id, HomeCollection.favorites)).items,
      ]);
      expect(favorites, hasLength(2));
      expect(favorites.map((v) => v.item.identity.sourceId).toSet(), {
        'local',
        'remote',
      });
      expect(
        (await prefs.read((sourceId: remote.id, localId: 'same'))).favorite,
        isTrue,
      );
      await prefs.setLocalFavorite((
        sourceId: local.id,
        localId: 'same',
      ), false);
      expect(
        (await home.page(local.id, HomeCollection.favorites)).items,
        isEmpty,
      );
      expect(
        (await home.page(remote.id, HomeCollection.favorites)).items,
        hasLength(1),
      );
      await prefs.setWatchlist((sourceId: local.id, localId: 'same'), false);
      expect(
        (await home.page(local.id, HomeCollection.watchlist)).items,
        isEmpty,
      );
      expect(
        (await home.page(remote.id, HomeCollection.watchlist)).items,
        hasLength(1),
      );
    },
  );

  test('private descendants, photo/music sources, music classification and unselected libraries never leak', () async {
    await seed(local, 'vault', type: 'private');
    await seed(
      local,
      'secret-show',
      type: 'tvShow',
      series: true,
      parent: 'vault',
      favorite: true,
      listed: true,
    );
    await seed(
      local,
      'secret-ep',
      type: 'episode',
      parent: 'secret-show',
      favorite: true,
      position: 40000,
    );
    final photos = await source('photos', file: true, mediaType: 'photo');
    await seed(photos, 'photo-video', favorite: true);
    await seed(remote, 'visible', favorite: true);
    await seed(remote, 'excluded', favorite: true, library: 'excluded');
    await seed(remote, 'audio', type: 'music', favorite: true);
    await seed(remote, 'classified-music', collection: 'music', favorite: true);
    await sources.updateSettings(
      remote.id,
      options: SourceOptions(selectedEmbyLibraryIDs: ['movies']),
    );
    expect(ids(await home.page(remote.id, HomeCollection.favorites)), [
      'visible',
    ]);
    expect(await home.recommendationCandidates(local.id), isEmpty);
    expect(await home.recommendationCandidates(photos.id), isEmpty);
    expect(
      (await home.recommendationCandidates(remote.id))
          .map((v) => v.item.identity.localId),
      ['visible'],
    );
    for (final c in HomeCollection.values.where(
      (c) =>
          c != HomeCollection.seriesRecommendations &&
          c != HomeCollection.highRated,
    )) {
      expect((await home.page(local.id, c)).items, isEmpty);
      expect((await home.page(photos.id, c)).items, isEmpty);
    }
    final counts = await home.stats(remote.id, .9);
    expect(counts.movies, 1);
    expect(counts.series, 0);
    expect(counts.unwatched, 1);
    expect((await home.stats(local.id, .9)).episodes, 0);
  });

  test('resume uses fixed 0.95 boundary and next up follows last finished across season gaps', () async {
    await seed(local, 'film', position: 92000);
    await seed(local, 'almost', position: 95000);
    expect(
      ids(
        await home.page(
          local.id,
          HomeCollection.continueWatching,
          threshold: .7,
        ),
      ),
      ['film'],
    );
    await seed(local, 'show', type: 'tvShow', series: true);
    await seed(
      local,
      's0e1',
      type: 'episode',
      parent: 'show',
      season: 0,
      episode: 1,
      watched: true,
    );
    await seed(
      local,
      's1e2',
      type: 'episode',
      parent: 'show',
      season: 1,
      episode: 2,
      watched: true,
    );
    await seed(
      local,
      's2e5',
      type: 'episode',
      parent: 'show',
      season: 2,
      episode: 5,
    );
    await seed(
      local,
      's2e8',
      type: 'episode',
      parent: 'show',
      season: 2,
      episode: 8,
    );
    final combined = HomeVideoPolicy.merge(
      HomeCollection.continueWatching,
      (await home.page(local.id, HomeCollection.continueWatching)).items,
    );
    expect(combined.map((v) => v.item.identity.localId), ['s2e5']);
    expect(
      (await home.playbackTarget((
        sourceId: local.id,
        localId: 'show',
      ), .9)).localId,
      's2e5',
    );
    await PlaybackRepository(sources.database)
        .markWatched([(sourceId: local.id, localId: 's2e8')], true);
    expect(ids(await home.page(local.id, HomeCollection.continueWatching)), [
      'film',
    ]);
  });

  test(
    'next-up preference is applied before the first 36 candidates',
    () async {
      for (var n = 0; n < 45; n++) {
        await seed(local, 'film-$n', position: 30000, date: 1000 + n);
      }
      await seed(local, 'show', type: 'tvShow', series: true);
      await seed(
        local,
        'done',
        type: 'episode',
        parent: 'show',
        episode: 1,
        watched: true,
      );
      await seed(local, 'next', type: 'episode', parent: 'show', episode: 4);
      expect(ids(await home.page(local.id, HomeCollection.continueWatching)), [
        'next',
      ]);
    },
  );

  test('public detail guard follows selection, privacy, classification and removal', () async {
    await seed(remote, 'film', favorite: true, library: 'movies');
    await seed(remote, 'audio', collection: 'music');
    await seed(local, 'vault', type: 'private');
    await seed(local, 'secret', parent: 'vault');
    final id = (sourceId: remote.id, localId: 'film');
    await home.ensurePublic(id);
    expect(
      () => home.ensurePublic((sourceId: remote.id, localId: 'audio')),
      throwsA(isA<SourceFailure>()),
    );
    expect(
      () => home.ensurePublic((sourceId: local.id, localId: 'secret')),
      throwsA(isA<SourceFailure>()),
    );
    await sources.updateSettings(
      remote.id,
      options: SourceOptions(selectedEmbyLibraryIDs: ['other']),
    );
    expect(() => home.ensurePublic(id), throwsA(isA<SourceFailure>()));
    expect(
      (await home.page(remote.id, HomeCollection.favorites)).items,
      isEmpty,
    );
    await sources.remove(remote.id);
    expect(() => home.ensurePublic(id), throwsA(isA<SourceFailure>()));
  });

  test(
    'a cached or fully synchronized source never needs foreground seeding',
    () async {
      await sources.database.customStatement(
        'UPDATE sources SET last_scan=NULL WHERE id=?',
        [remote.id],
      );
      remote = await sources.source(remote.id, includeCounts: false);
      expect(await home.needsSeed(remote), isTrue);
      expect(await home.needsSeed(local), isFalse);
      await seed(remote, 'cached');
      expect(await home.needsSeed(remote), isFalse);
      await sources.database.customStatement(
        'DELETE FROM media WHERE source_id=?',
        [remote.id],
      );
      await sources.database.customStatement(
        'UPDATE sources SET last_scan=1 WHERE id=?',
        [remote.id],
      );
      expect(
        await home.needsSeed(
          await sources.source(remote.id, includeCounts: false),
        ),
        isFalse,
      );
    },
  );

  test('recent history requires traces, clearing blocks delayed checkpoints and refreshes home', () async {
    await seed(local, 'never');
    await seed(remote, 'played', position: 30000);
    expect(
      (await home.page(local.id, HomeCollection.recentlyPlayed)).items,
      isEmpty,
    );
    final id = (sourceId: remote.id, localId: 'played');
    final records = PlaybackRepository(sources.database);
    final epoch = await records.historyEpoch(id);
    await records.clearHistory([id]);
    await records.save(
      id,
      position: const Duration(seconds: 80),
      duration: const Duration(seconds: 100),
      historyEpoch: epoch,
    );
    expect(
      (await home.page(remote.id, HomeCollection.recentlyPlayed)).items,
      isEmpty,
    );
    expect(
      (await home.page(remote.id, HomeCollection.continueWatching)).items,
      isEmpty,
    );
  });

  test('view-more pages extend beyond initial 36 without details or whole connector snapshot', () async {
    for (var n = 0; n < 75; n++) {
      await seed(
        remote,
        'film-${n.toString().padLeft(3, '0')}',
        favorite: true,
        date: n + 1,
      );
    }
    await sources.database.customStatement(
      'INSERT INTO remote_media_details VALUES (?,?,?,0)',
      [remote.id, 'film-000', 'bad JSON'],
    );
    final first = await home.page(remote.id, HomeCollection.favorites);
    final second = await home.page(
      remote.id,
      HomeCollection.favorites,
      offset: first.nextOffset,
    );
    final third = await home.page(
      remote.id,
      HomeCollection.favorites,
      offset: second.nextOffset,
    );
    expect(first.items, hasLength(36));
    expect(second.items, hasLength(36));
    expect(third.items, hasLength(3));
    expect(third.hasMore, isFalse);
    expect(
      [
        ...first.items,
        ...second.items,
        ...third.items,
      ].map((v) => v.item.identity).toSet(),
      hasLength(75),
    );
    expect(first.items.first.item.identity.localId, 'film-074');
    expect(
      (await home.page(remote.id, HomeCollection.recentSeries)).items,
      isEmpty,
    );
  });

  test('percentage-only series progress is readable and cleared local state suppresses remote fallback', () async {
    await seed(
      remote,
      'percentage-show',
      type: 'tvShow',
      series: true,
      collection: 'tvshows',
    );
    await sources.database.customStatement(
      'DELETE FROM playback_states WHERE source_id=?',
      [remote.id],
    );
    await sources.database.customStatement(
      "UPDATE remote_media_metadata SET value=json_set(value,'\$.playedPercentage',40,'\$.durationMs',NULL) WHERE source_id=?",
      [remote.id],
    );
    final page = await home.page(remote.id, HomeCollection.recentlyPlayed);
    expect(page.items.single.entry.progress, .4);
    expect(page.items.single.entry.record.duration, Duration.zero);
    expect((await home.stats(remote.id, .3)).unwatched, 0);
    expect((await home.stats(remote.id, .9)).unwatched, 1);
    await PlaybackRepository(sources.database)
        .clearHistory([(sourceId: remote.id, localId: 'percentage-show')]);
    expect(
      (await home.page(remote.id, HomeCollection.recentlyPlayed)).items,
      isEmpty,
    );
    expect(
      (await home.page(
        remote.id,
        HomeCollection.recentSeries,
      )).items.single.entry.progress,
      0,
    );
  });

  test('synced empty movie clocks retain percentage until explicitly cleared or locally played', () async {
    await seed(remote, 'percentage-film', duration: 0);
    await sources.database.customStatement(
      "UPDATE remote_media_metadata SET value=json_set(value,'\$.playedPercentage',40) WHERE source_id=?",
      [remote.id],
    );
    final id = (sourceId: remote.id, localId: 'percentage-film');
    final imported = await sources.media(id);
    Future<void> sync(RemoteTraceSyncMode mode) => sources.database.transaction(
      () => RemoteIndexWriter(sources.database).write(
        remote.id,
        [imported],
        traceMode: mode,
        cancellation: ScanCancellation(),
      ),
    );
    await sync(RemoteTraceSyncMode.bidirectional);
    final records = PlaybackRepository(sources.database);
    expect((await records.read(id)).position, Duration.zero);
    expect((await records.read(id)).duration, Duration.zero);
    expect(
      (await home.page(
        remote.id,
        HomeCollection.continueWatching,
      )).items.single.entry.progress,
      .4,
    );
    expect(
      (await home.page(
        remote.id,
        HomeCollection.recentlyPlayed,
      )).items.single.entry.progress,
      .4,
    );
    expect(
      (await home.recommendationCandidates(remote.id)).single.entry.progress,
      .4,
    );
    expect((await home.stats(remote.id, .3)).unwatched, 0);

    final beforeClear = await records.historyEpoch(id);
    await records.clearHistory([id]);
    final afterClear = await records.historyEpoch(id);
    expect(afterClear, isNot(beforeClear));
    await sync(RemoteTraceSyncMode.disabled);
    expect(
      (await home.page(remote.id, HomeCollection.continueWatching)).items,
      isEmpty,
    );
    expect(
      (await home.page(remote.id, HomeCollection.recentlyPlayed)).items,
      isEmpty,
    );
    expect(
      (await home.recommendationCandidates(remote.id)).single.entry.progress,
      0,
    );
    expect((await home.stats(remote.id, .3)).unwatched, 1);

    // Re-imports may legitimately restore remote traces, without admitting
    // stale checkpoints from a player opened before the clear.
    await sync(RemoteTraceSyncMode.importOnly);
    expect(
      (await home.recommendationCandidates(remote.id)).single.entry.progress,
      .4,
    );
    expect(await records.historyEpoch(id), afterClear);
    await records.save(
      id,
      position: const Duration(seconds: 80),
      duration: const Duration(seconds: 100),
      historyEpoch: beforeClear,
    );
    expect(
      (await home.recommendationCandidates(remote.id)).single.entry.progress,
      .4,
    );
    await records.save(
      id,
      position: const Duration(seconds: 10),
      duration: const Duration(seconds: 100),
      historyEpoch: afterClear,
    );
    expect(
      (await home.recommendationCandidates(remote.id)).single.entry.progress,
      .1,
    );
    await records.markWatched([id], false);
    expect(
      (await home.recommendationCandidates(remote.id)).single.entry.progress,
      0,
    );
  });

  test(
    'series playback target uses percentage-only episode progress',
    () async {
      await seed(
        remote,
        'percentage-series',
        type: 'tvShow',
        series: true,
        collection: 'tvshows',
      );
      await seed(
        remote,
        'first',
        type: 'episode',
        parent: 'percentage-series',
        episode: 1,
        duration: 0,
      );
      await seed(
        remote,
        'second',
        type: 'episode',
        parent: 'percentage-series',
        episode: 2,
        duration: 0,
      );
      await sources.database.customStatement(
        "UPDATE remote_media_metadata SET value=json_set(value,'\$.playedPercentage',CASE local_id WHEN 'first' THEN 95 ELSE 40 END) WHERE source_id=? AND local_id IN ('first','second')",
        [remote.id],
      );
      expect(
        await home.playbackTarget((
          sourceId: remote.id,
          localId: 'percentage-series',
        ), .9),
        (sourceId: remote.id, localId: 'second'),
      );
    },
  );

  test('series candidates preserve remote classification and do not include movies', () async {
    await seed(remote, 'movie');
    await seed(remote, 'anime', type: 'movie', collection: 'tvshows');
    await seed(local, 'show', type: 'tvShow', series: true);
    expect(ids(await home.page(remote.id, HomeCollection.recentSeries)), [
      'anime',
    ]);
    expect(ids(await home.page(local.id, HomeCollection.recentSeries)), [
      'show',
    ]);
    final counts = await home.stats(remote.id, .9);
    expect(counts.movies, 1);
    expect(counts.series, 1);
  });

  test(
    'series classification keys preserve empty and multilingual genre arrays',
    () async {
      await seed(
        remote,
        'empty-array-show',
        type: 'tvShow',
        series: true,
        collection: 'tvshows',
      );
      await seed(remote, 'genre-anime', type: 'movie', genres: ['剧情', '动画']);
      await seed(remote, 'ordinary-film', genres: ['剧情']);
      expect(ids(await home.page(remote.id, HomeCollection.recentSeries)), [
        'empty-array-show',
        'genre-anime',
      ]);
    },
  );

  test('recommendation decoding excludes episodes and offline parents require validated child identities', () async {
    await seed(
      remote,
      'series',
      type: 'tvShow',
      series: true,
      collection: 'tvshows',
    );
    await seed(remote, 'episode', type: 'episode', parent: 'series');
    for (var n = 0; n < 190; n++) {
      await seed(remote, 'movie$n');
    }
    final candidates = await home.recommendationCandidates(remote.id);
    expect(candidates, hasLength(191));
    expect(candidates.any((v) => v.item.type == 'episode'), isFalse);
    final child = (sourceId: remote.id, localId: 'episode');
    expect(await home.offlineParents({child}), {
      child,
      (sourceId: remote.id, localId: 'series'),
    });
    expect(await home.offlineParents({}), isEmpty);
    await sources.updateSettings(
      remote.id,
      options: SourceOptions(selectedEmbyLibraryIDs: ['other']),
    );
    expect(await home.recommendationCandidates(remote.id), isEmpty);
    expect(await home.offlineParents({child}), {child});
  });

  test(
    'player revision refreshes all loaded pages only for the affected source',
    () async {
      await seed(local, 'played', position: 20000);
      await seed(remote, 'played', position: 30000);
      final container = ProviderContainer(
        overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
      );
      addTearDown(container.dispose);
      HomeQuery query(String id) =>
          (sourceId: id, collection: HomeCollection.recentlyPlayed, offset: 0);
      final subscriptions = [
        for (final id in [local.id, remote.id])
          container.listen(homeVideoPageProvider(query(id)), (_, _) {}),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });
      final oldLocal = await container.read(
        homeVideoPageProvider(query(local.id)).future,
      );
      final oldRemote = await container.read(
        homeVideoPageProvider(query(remote.id)).future,
      );
      await PlaybackRepository(sources.database).save(
        (sourceId: local.id, localId: 'played'),
        position: const Duration(seconds: 60),
        duration: const Duration(seconds: 100),
      );
      container.read(homePlaybackRevisionsProvider.notifier).refresh([
        local.id,
      ]);
      final updated = await container.read(
        homeVideoPageProvider(query(local.id)).future,
      );
      expect(
        updated.items.single.entry.record.position,
        const Duration(seconds: 60),
      );
      expect(identical(updated, oldLocal), isFalse);
      expect(
        identical(
          await container.read(homeVideoPageProvider(query(remote.id)).future),
          oldRemote,
        ),
        isTrue,
      );
    },
  );
}
