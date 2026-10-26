import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/emby_library_providers.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/data/remote_index_writer.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/sources/presentation/emby_video_library_page.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';
import 'package:reelnest/features/sources/presentation/emby_video_context_menu.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';
import 'support/fake_video_engine.dart';

class _Store implements CredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _Http extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbySyncRepository sync;
  late EmbyLibraryRepository library;
  late PlaybackRepository records;
  late MediaSource source;
  MediaIdentity id(String local) => (sourceId: source.id, localId: local);
  Map<String, dynamic> movie(String value) => {
    'Id': value,
    'Name': value,
    'Type': 'Movie',
    'CommunityRating': 8.2,
    'RunTimeTicks': 1000000000,
    'MediaSources': [
      {'Id': 'media-$value', 'Container': 'mkv'},
    ],
    'UserData': {
      'PlaybackPositionTicks': 200000000,
      'LastPlayedDate': '2026-10-10T00:00:00Z',
      'Played': false,
    },
  };
  List<String> flags() => server.requests
      .where((r) => r.uri.path.contains('/PlayedItems/'))
      .map((r) => r.uri.pathSegments.last)
      .toList();
  Future<void> refresh() => sync.synchronize(source.id).then((_) {});
  setUp(() async {
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(
      deviceId: 'batch-fixture',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    final stores = <String, _Store>{};
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (key) => stores.putIfAbsent(key, _Store.new),
    );
    source = await connections.connect(server.address, 'tester', 'pw');
    server.catalog['movies'] = [movie('a'), movie('b')];
    server.catalog['shows'] = [
      {'Id': 'show', 'Name': '系列', 'Type': 'Series'},
      for (var number = 1; number <= 2; number++)
        {
          ...movie('ep$number'),
          'Type': 'Episode',
          'SeriesId': 'show',
          'SeriesName': '系列',
          'ParentIndexNumber': 1,
          'IndexNumber': number,
        },
    ];
    sync = EmbySyncRepository(sources: sources, connections: connections);
    library = EmbyLibraryRepository(sources);
    records = PlaybackRepository(sources.database);
    await refresh();
  });
  tearDown(() async {
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
  });
  test('initial sync persists 5-star seeds while community scores stay on 10 points', () async {
    final entry = (await library.snapshot(source.id)).entries
        .firstWhere((e) => e.item.identity == id('a'));
    expect(entry.userRating, 4);
    expect(entry.item.remote!.rating, 8.2);
    final row = await sources.database
        .customSelect(
          "SELECT user_rating FROM media_library_preferences WHERE local_id='a'",
        )
        .getSingle();
    expect(row.read<double>('user_rating'), 4);
    final series = (await library.snapshot(source.id)).entries
        .firstWhere((e) => e.item.identity == id('show'));
    expect(series.userRating, isNull);
  });
  test('missing preference fallback and watchlist insertion seed stars but explicit null stays cleared', () async {
    await sources.database.customStatement(
      "DELETE FROM media_library_preferences WHERE local_id='a'",
    );
    var entry = (await library.snapshot(source.id)).entries
        .firstWhere((e) => e.item.identity == id('a'));
    expect(entry.userRating, 4);
    await library.setWatchlist(id('a'), true);
    entry = (await library.snapshot(source.id)).entries
        .firstWhere((e) => e.item.identity == id('a'));
    expect(entry.userRating, 4);
    expect(entry.watchlist, isTrue);
    await library.setRating([id('a')], null);
    await library.setWatchlist(id('a'), false);
    await refresh();
    entry = (await library.snapshot(source.id)).entries
        .firstWhere((e) => e.item.identity == id('a'));
    expect(entry.userRating, isNull);
    expect(entry.item.remote!.rating, 8.2);
  });
  test('changed community scores do not overwrite manual ratings or explicit clears', () async {
    await library.setRating([id('a')], 2);
    await library.setRating([id('b')], null);
    server.catalog['movies'] = [
      {...movie('a'), 'CommunityRating': 9.8},
      {...movie('b'), 'CommunityRating': 9.8},
      {...movie('new'), 'CommunityRating': 9.8},
    ];
    await refresh();
    final entries = (await library.snapshot(source.id)).entries;
    expect(entries.firstWhere((e) => e.item.identity == id('a')).userRating, 2);
    expect(
      entries.firstWhere((e) => e.item.identity == id('b')).userRating,
      isNull,
    );
    expect(
      entries.firstWhere((e) => e.item.identity == id('new')).userRating,
      5,
    );
    expect(
      entries.firstWhere((e) => e.item.identity == id('a')).item.remote!.rating,
      9.8,
    );
  });
  test('library classification refresh is atomic and works from the stored index without network', () async {
    server.views = {
      'Items': [
        {'Id': 'movies', 'Name': '纪录片', 'CollectionType': 'movies'},
        {'Id': 'shows', 'Name': '电视剧', 'CollectionType': 'tvshows'},
      ],
    };
    server.itemsHandler = (request) async {
      request.response.statusCode = 500;
      await request.response.close();
    };
    await expectLater(refresh(), throwsA(isA<SourceFailure>()));
    expect((await sources.media(id('a'))).displayType, 'movie');
    server.itemsHandler = null;
    await refresh();
    final requests = server.requests.length;
    final item = await sources.media(id('a'));
    expect(item.remote!.collectionType, 'movies');
    expect(item.displayType, 'documentary');
    expect(item.type, 'movie');
    final restored = (await EmbyLibraryRepository(sources).snapshot(source.id))
        .entries
        .firstWhere((e) => e.item.identity == id('a'));
    expect(restored.item.displayType, 'documentary');
    expect(server.requests.length, requests);
    final row = await sources.database
        .customSelect(
          "SELECT type, identity_kind FROM media WHERE local_id='a'",
        )
        .getSingle();
    expect(row.read<String>('type'), 'movie');
    expect(row.read<String>('identity_kind'), 'movie');
  });
  test('genre and collection hints classify imported movies while episodes retain hierarchy', () async {
    server.views = {
      'Items': [
        {'Id': 'movies', 'Name': 'Archive', 'CollectionType': 'homevideos'},
        {'Id': 'shows', 'Name': '新番', 'CollectionType': 'tvshows'},
      ],
    };
    server.catalog['movies'] = [
      {
        ...movie('a'),
        'Genres': ['Documentary'],
      },
      movie('b'),
    ];
    await refresh();
    expect((await sources.media(id('a'))).displayType, 'documentary');
    expect((await sources.media(id('b'))).displayType, 'homeVideo');
    final series = await sources.media(id('show'));
    expect(series.displayType, 'anime');
    expect(series.type, 'tvShow');
    expect(series.isSeries, isTrue);
    final episode = await sources.media(id('ep1'));
    expect(episode.displayType, 'episode');
    expect(episode.parentId, 'show');
    expect((await sources.episodes(id('show'), seasonNumber: 1)).total, 2);
  });
  test('synthetic series inherits genre hint and star seed', () async {
    await library.removeFromLibrary([id('show')]);
    server.views = {
      'Items': [
        {'Id': 'shows', 'Name': 'Archive', 'CollectionType': 'tvshows'},
      ],
    };
    server.catalog['shows'] = [
      {
        ...movie('ep1'),
        'Genres': ['Animation'],
        'Type': 'Episode',
        'SeriesId': 'show',
        'SeriesName': '系列',
        'ParentIndexNumber': 1,
        'IndexNumber': 1,
      },
    ];
    await refresh();
    final series = await sources.media(id('show'));
    expect(series.remote!.collectionType, 'tvshows');
    expect(series.displayType, 'anime');
    expect(series.isSeries, isTrue);
    final entry = (await library.snapshot(source.id)).entries
        .firstWhere((e) => e.item.identity == id('show'));
    expect(entry.userRating, 4);
    expect(entry.item.remote!.rating, 8.2);
    expect((await sources.media(id('ep1'))).displayType, 'episode');
  });

  test('music display classification is excluded from videos without deleting indexed media', () async {
    server.views = {
      'Items': [
        {'Id': 'movies', 'Name': 'Archive', 'CollectionType': 'music'},
        {'Id': 'shows', 'Name': '电视剧', 'CollectionType': 'tvshows'},
      ],
    };
    server.catalog['movies'] = [
      movie('a'),
      {...movie('audio'), 'Type': 'Audio'},
    ];
    await refresh();
    final snapshot = await library.snapshot(source.id);
    expect(
      snapshot
          .scope((
            sourceId: source.id,
            section: EmbyVideoSection.videos,
            libraryId: null,
          ))
          .map((e) => e.item.identity.localId),
      ['show'],
    );
    expect(snapshot.libraries.map((l) => l.id), ['shows']);
    expect((await sources.media(id('a'))).type, 'movie');
    expect((await sources.media(id('a'))).displayType, 'music');
    expect((await sources.media(id('audio'))).type, 'music');
  });

  test('cached-only filter includes an episode parent without leaking other sources', () async {
    final snapshot = await library.snapshot(source.id);
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        embyVideoSnapshotProvider(source.id)
            .overrideWith((ref) async => snapshot),
        embyCachedVideosProvider.overrideWith(
          (ref) async => [
            CachedVideo(id('ep1'), 'bundle', 'video.mp4', 1, 'source'),
            const CachedVideo(
              (sourceId: 'other', localId: 'a'),
              'bundle2',
              'video.mp4',
              1,
              'source',
            ),
            CachedVideo(id('missing'), 'bundle3', 'video.mp4', 1, 'source'),
          ],
        ),
      ],
    );
    try {
      final result = await container.read(
        embyVideoResultsProvider((
          destination: (
            sourceId: source.id,
            section: EmbyVideoSection.videos,
            libraryId: null,
          ),
          settings: const VideoLibrarySettings(cachedOnly: true),
        )).future,
      );
      expect(result.map((e) => e.item.identity), [id('show')]);
    } finally {
      container.dispose();
    }
  });

  test('incremental writes preserve local favorites without reading unrelated metadata', () async {
    final incoming = await sources.media(id('a'));
    await sources.setRemoteFavorite(id('a'), true);
    await sources.database.customStatement(
      "UPDATE remote_media_metadata SET value='invalid-json' WHERE source_id=? AND local_id='b'",
      [source.id],
    );
    await sources.database.transaction(
      () => RemoteIndexWriter(sources.database).write(
        source.id,
        [incoming],
        traceMode: RemoteTraceSyncMode.disabled,
        cancellation: ScanCancellation(),
      ),
    );
    expect((await sources.media(id('a'))).remote!.favorite, isTrue);
  });

  test('small actions and series queries never decode unrelated metadata', () async {
    // A sentinel that would fail JSON decoding if any full-library read leaked
    // into a small operation. This is only the isolated test database.
    await sources.database.customStatement(
      "UPDATE remote_media_metadata SET value='invalid-json' WHERE source_id=? AND local_id='b'",
      [source.id],
    );
    await library.setWatchlistMany([id('a')], true);
    await library.setRating([id('a')], 3);
    final rows = await sources.database
        .customSelect(
          "SELECT watchlist,user_rating FROM media_library_preferences WHERE local_id='a'",
        )
        .getSingle();
    expect(rows.read<int>('watchlist'), 1);
    expect(rows.read<double>('user_rating'), 3);
    expect(
      (await sources.indexedChildren(id('show')))
          .map((e) => e.identity.localId)
          .toSet(),
      {'ep1', 'ep2'},
    );
    expect(
      (await library.targets([
        id('show'),
      ], descendants: true)).map((e) => e.identity.localId).toSet(),
      {'show', 'ep1', 'ep2'},
    );
    final selected = await sources.indexedSelection(source.id, [
      'a',
      'a',
      for (var i = 0; i < 1500; i++) 'missing$i',
    ]);
    expect(selected.single.identity, id('a'));
  });

  test('selection expansion is source isolated and terminates parent cycles', () async {
    final other = await connections.connect(server.address, 'tester', 'pw');
    await sync.synchronize(other.id);
    // Deliberately corrupt only parent relationships in a temporary fixture.
    await sources.database.customStatement(
      "UPDATE media SET parent_id='ep1' WHERE source_id=? AND local_id='show'",
      [source.id],
    );
    final result = await library.targets([
      id('show'),
      id('ep1'),
    ], descendants: true);
    expect(result.map((e) => e.identity.localId).toSet(), {
      'show',
      'ep1',
      'ep2',
    });
    expect(result.length, 3);
    expect(result.every((e) => e.identity.sourceId == source.id), isTrue);
    await expectLater(
      library.targets([id('a'), (sourceId: other.id, localId: 'a')]),
      throwsA(isA<SourceFailure>()),
    );
  });

  test(
    'series expansion deduplicates episodes and validates before changes',
    () async {
      final targets = await library.targets([
        id('show'),
        id('ep1'),
      ], descendants: true);
      expect(targets.map((i) => i.identity.localId).toSet(), {
        'show',
        'ep1',
        'ep2',
      });
      await connections.markPlayed(targets.map((i) => i.identity), true);
      expect(flags().toSet(), {'show', 'ep1', 'ep2'});
      expect((await records.read(id('ep2'))).watched, isTrue);
      await expectLater(
        library.setWatchlistMany([id('a'), id('missing')], true),
        throwsA(isA<SourceFailure>()),
      );
      expect(
        (await library.snapshot(source.id)).entries.where((e) => e.watchlist),
        isEmpty,
      );
    },
  );
  test(
    'watchlist batch rolls back all rows when a later SQL write fails',
    () async {
      await sources.database.customStatement("""
      CREATE TRIGGER reject_second BEFORE UPDATE OF watchlist ON media_library_preferences
      WHEN NEW.local_id='b' BEGIN SELECT RAISE(ABORT, 'fixture'); END
    """);
      await expectLater(
        library.setWatchlistMany([id('a'), id('b')], true),
        throwsA(anything),
      );
      expect(
        (await library.snapshot(source.id)).entries.where((e) => e.watchlist),
        isEmpty,
      );
    },
  );
  test('local rating preserves watchlist and explicit clear survives a server resync', () async {
    await library.setWatchlist(id('a'), true);
    final count = server.requests.length;
    await library.setRating([id('a'), id('b')], 3);
    var entries = (await library.snapshot(source.id)).entries;
    expect(entries.firstWhere((e) => e.item.identity == id('a')).userRating, 3);
    expect(
      entries.firstWhere((e) => e.item.identity == id('a')).watchlist,
      isTrue,
    );
    await library.setRating([id('a')], null);
    expect(server.requests.length, count);
    await refresh();
    entries = (await library.snapshot(source.id)).entries;
    final a = entries.firstWhere((e) => e.item.identity == id('a'));
    expect(a.userRating, isNull);
    expect(a.item.remote!.rating, 8.2);
    expect(a.watchlist, isTrue);
    expect(entries.firstWhere((e) => e.item.identity == id('b')).userRating, 3);
  });
  test(
    'rating write failure is atomic and out of range values are rejected',
    () async {
      final before = (await library.snapshot(source.id)).entries
          .firstWhere((e) => e.item.identity == id('a'))
          .userRating;
      await sources.database.customStatement("""
      CREATE TRIGGER reject_rating BEFORE UPDATE OF user_rating ON media_library_preferences
      WHEN NEW.local_id='b' BEGIN SELECT RAISE(ABORT, 'fixture'); END
    """);
      await expectLater(
        library.setRating([id('a'), id('b')], 4),
        throwsA(anything),
      );
      expect(
        (await library.snapshot(source.id)).entries
            .firstWhere((e) => e.item.identity == id('a'))
            .userRating,
        before,
      );
      for (final rating in [double.nan, double.infinity, 0.0, 6.0]) {
        await expectLater(
          library.setRating([id('a')], rating),
          throwsA(isA<SourceFailure>()),
        );
      }
    },
  );
  test('clearing history ignores flag-only records and reports later failures independently', () async {
    await records.clearHistory([id('show')]);
    await records.markWatched([id('show')], true);
    server.userFlagHandler = (request) async {
      request.response.statusCode = request.uri.pathSegments.last == 'ep1'
          ? 500
          : 204;
      await request.response.close();
    };
    final targets = await library.targets([id('show')], descendants: true);
    final failed = await connections.markPlayed(
      targets.map((i) => i.identity),
      false,
      clearHistory: true,
    );
    expect(failed, 1);
    expect(flags().toSet(), {'ep1', 'ep2'});
    expect((await records.read(id('show'))).watched, isTrue);
    expect((await records.read(id('ep1'))).position, Duration.zero);
    expect((await records.read(id('ep2'))).lastPlayedAt, isNull);
  });
  test('stale player checkpoint cannot restore history, a newly opened player can save', () async {
    final epoch = await records.historyEpoch(id('a'));
    await records.clearHistory([id('a')]);
    await records.save(
      id('a'),
      position: const Duration(seconds: 45),
      duration: const Duration(seconds: 100),
      historyEpoch: epoch,
    );
    expect((await records.read(id('a'))).position, Duration.zero);
    final fresh = await records.historyEpoch(id('a'));
    expect(fresh, isNot(epoch));
    await records.save(
      id('a'),
      position: const Duration(seconds: 5),
      duration: const Duration(seconds: 100),
      historyEpoch: fresh,
    );
    expect((await records.read(id('a'))).position, const Duration(seconds: 5));
  });
  test('open playback session respects clear generation on save and stop reporting', () async {
    final engine = FakeVideoEngine();
    final player = PlaybackSession(
      sources: sources,
      records: records,
      createEngine: () => engine,
      emby: connections,
    );
    try {
      await player.open(id('a'));
      engine.emit(position: const Duration(seconds: 50));
      await player.save();
      await connections.markPlayed([id('a')], false, clearHistory: true);
      engine.emit(position: const Duration(seconds: 60));
      await player.save();
      await player.close();
      expect((await records.read(id('a'))).position, Duration.zero);
      final stops = server.requests.where(
        (r) => r.uri.path.endsWith('/Playing/Stopped'),
      );
      expect(stops, isNotEmpty);
      expect(jsonDecode(stops.last.body)['PositionTicks'], 0);
    } finally {
      await player.close();
      player.dispose();
    }
  });
  test(
    'index removal cascades series, keeps another source and restores on sync',
    () async {
      final other = await connections.connect(server.address, 'tester', 'pw');
      await sync.synchronize(other.id);
      final count = server.requests.length;
      expect(await library.removeFromLibrary([id('show')]), 3);
      expect(
        (await sources.indexedSource(source.id)).map((i) => i.identity.localId),
        ['a', 'b'],
      );
      expect(
        (await sources.indexedSource(other.id))
            .any((i) => i.identity.localId == 'ep1'),
        isTrue,
      );
      expect(server.requests.length, count);
      await refresh();
      expect(
        (await sources.indexedSource(source.id))
            .any((i) => i.identity.localId == 'show'),
        isTrue,
      );
    },
  );
  test(
    'remove blocks while syncing and does not publish partial removal',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      server.viewsHandler = (r) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        r.response.write(jsonEncode(server.views));
        await r.response.close();
      };
      final pending = refresh();
      await entered.future;
      try {
        await expectLater(
          library.removeFromLibrary([id('show')]),
          throwsA(isA<SourceFailure>()),
        );
        expect(
          (await sources.indexedSource(source.id))
              .any((i) => i.identity.localId == 'show'),
          isTrue,
        );
      } finally {
        release.complete();
        await pending;
      }
    },
  );
  test('import-only clearing never writes a remote user flag', () async {
    await connections.selectLibraries(
      source.id,
      all: true,
      selected: [],
      trace: RemoteTraceSyncMode.importOnly,
    );
    final count = server.requests.length;
    await connections.markPlayed([id('a')], false, clearHistory: true);
    expect(server.requests.length, count);
    expect((await records.read(id('a'))).lastPlayedAt, isNull);
  });
  testWidgets(
    'episode without its own trace can clear the parent series history',
    (tester) async {
      await tester.runAsync(() async {
        server.catalog['shows']!.first['UserData'] = {
          'PlaybackPositionTicks': 10000000,
          'LastPlayedDate': '2026-10-10T00:00:00Z',
        };
        await refresh();
        await records.clearHistory([id('ep1')]);
        await connections.selectLibraries(
          source.id,
          all: true,
          selected: [],
          trace: RemoteTraceSyncMode.importOnly,
        );
      });
      final episode = await sources.media(id('ep1'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sources),
            embyConnectionProvider.overrideWithValue(connections),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: EmbyVideoContextMenu(
                  item: episode,
                  child: const SizedBox(
                    width: 200,
                    height: 60,
                    child: Text('单集'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('单集'), buttons: 2);
      await tester.pumpAndSettle();
      expect(find.text('外部打开'), findsOneWidget);
      expect(find.text('自动缓存系列'), findsOneWidget);
      await tester.tap(find.text('删除本系列播放记录'));
      await tester.pumpAndSettle();
      final parent = (await library.snapshot(source.id)).entries
          .firstWhere((e) => e.item.identity == id('show'));
      expect(parent.hasTrace, isFalse);
      expect((await records.read(id('ep2'))).position, Duration.zero);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  Future<void> page(WidgetTester tester) async {
    tester.view.physicalSize = const Size(836, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await connections.selectLibraries(
      source.id,
      all: true,
      selected: [],
      trace: RemoteTraceSyncMode.importOnly,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          embyConnectionProvider.overrideWithValue(connections),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: EmbyVideoLibraryPage(
              destination: (
                sourceId: source.id,
                section: EmbyVideoSection.videos,
                libraryId: 'movies',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selection retains hidden choices; select-all only affects visible results',
    (tester) async {
      await tester.runAsync(
        () => connections.selectLibraries(
          source.id,
          all: true,
          selected: [],
          trace: RemoteTraceSyncMode.importOnly,
        ),
      );
      await page(tester);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is LocalMediaCard && widget.item.identity == id('a'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已选 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'b');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2'), findsOneWidget);
      await tester.tap(find.text('想看').last);
      await tester.pumpAndSettle();
      expect(
        (await library.snapshot(source.id)).entries.where((e) => e.watchlist),
        hasLength(2),
      );
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
  testWidgets(
    'right click exposes local rating, favorite and caching without changing selection',
    (tester) async {
      await page(tester);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is LocalMediaCard && widget.item.identity == id('a'),
        ),
        buttons: 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('已选 0'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text('喜欢'),
        ),
        findsOneWidget,
      );
      expect(find.text('本地分类'), findsNothing);
      await tester.tap(find.text('加入想看'));
      await tester.pumpAndSettle();
      expect(
        (await library.snapshot(source.id)).entries.where((e) => e.watchlist),
        hasLength(1),
      );
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is LocalMediaCard && widget.item.identity == id('a'),
        ),
        buttons: 2,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SubmenuButton),
          matching: find.text('评级'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('★★★'));
      await tester.pumpAndSettle();
      expect(
        (await library.snapshot(source.id)).entries
            .firstWhere((e) => e.item.identity == id('a'))
            .userRating,
        3,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
  testWidgets(
    'index removal requires confirmation; cancel preserves selection and data',
    (tester) async {
      await page(tester);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出库'));
      await tester.pumpAndSettle();
      expect(find.text('移出所选 2 个条目？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2'), findsOneWidget);
      await tester.tap(find.text('移出库'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出媒体库'));
      await tester.pumpAndSettle();
      expect(find.text('共 0 项'), findsOneWidget);
      expect(find.text('已选 2'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
}
