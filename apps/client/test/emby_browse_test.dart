import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/features/playback/application/playback_providers.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_browse_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_detail_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/sources/presentation/emby_video_library_page.dart';
import 'package:reelnest/features/sources/presentation/emby_video_context_menu.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';

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

class _Launcher implements PlaybackLauncher {
  final opened = Completer<MediaIdentity>();
  @override
  Future<void> open(MediaIdentity identity) async => opened.complete(identity);
}

Map<String, dynamic> _movie(String id, {String? person, String? name}) => {
  'Id': id,
  'Name': 'Film $id',
  'Type': 'Movie',
  'ProductionYear': 2024,
  'CommunityRating': 8.4,
  'UserData': {'IsFavorite': true, 'PlaybackPositionTicks': 10000000},
  'People': [
    if (person != null || name != null)
      {'Id': ?person, 'Name': name ?? '演员', 'Type': 'Actor'},
  ],
};
Map<String, dynamic> _episode(String id, int number) => {
  ..._movie(id, person: 'actor'),
  'Type': 'Episode',
  'SeriesId': 'show',
  'SeriesName': 'Show',
  'ParentId': 'season',
  'ParentIndexNumber': 1,
  'IndexNumber': number,
};
Future<void> _respond(
  HttpRequest r,
  List<Map<String, dynamic>> items, {
  int? total,
}) async {
  r.response.write(
    jsonEncode({'Items': items, 'TotalRecordCount': total ?? items.length}),
  );
  await r.response.close();
}

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbyBrowseRepository browse;
  late MediaSource source;
  final stores = <String, _Store>{};
  setUp(() async {
    stores.clear();
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(
      deviceId: 'foreground-test',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores.putIfAbsent(id, _Store.new),
    );
    browse = EmbyBrowseRepository(sources, connections);
    source = await connections.connect(server.address, 'tester', 'fixture');
  });
  tearDown(() async {
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
  });
  Future<EmbyBrowseCursor> cursor([String library = 'movies']) => browse.open(
    source.id,
    libraryId: library,
    cancellation: ScanCancellation(),
  );

  test('Views appear before indexing; 30000-item library needs one first-page request', () async {
    final catalog = await EmbyLibraryRepository(sources).snapshot(source.id);
    expect(
      catalog.libraries.map((v) => v.id),
      containsAll(['movies', 'shows']),
    );
    expect(catalog.entries, isEmpty);
    server.itemPageSize = 300;
    server.catalog['movies'] = List.generate(30000, (i) => _movie('$i'));
    final page = await cursor();
    final watch = Stopwatch()..start();
    expect((await page.next()).length, 60);
    debugPrint(
      'FOREGROUND_SIMULATED_30000 first60_ms=${watch.elapsedMilliseconds}',
    );
    expect(page.hasMore, isTrue);
    final requests = server.requests
        .where((r) => r.uri.path.endsWith('/Items'))
        .toList();
    expect(requests.length, 1);
    expect(requests.single.uri.queryParameters['Limit'], '60');
    expect(
      requests.single.uri.queryParameters['IncludeItemTypes'],
      'Movie,Series',
    );
    expect(
      requests.single.uri.queryParameters['Fields'],
      isNot(contains('MediaSources')),
    );
    expect((await sources.source(source.id)).lastScan, isNull);
    expect((await sources.indexedSource(source.id)).length, 60);
  });

  test('foreground page, artwork and detail finish while background network is held', () async {
    final entered = Completer<void>(), release = Completer<void>();
    server.itemsHandler = (r) async {
      final q = r.uri.queryParameters;
      if (q['IncludeItemTypes']!.contains('Audio') &&
          q['ParentId'] == 'movies') {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
      await _respond(r, q['ParentId'] == 'movies' ? [_movie('first')] : []);
    };
    server.detailHandler = (r) async {
      r.response.write(jsonEncode({'Id': 'first', 'People': []}));
      await r.response.close();
    };
    var completed = false;
    final syncing =
        EmbySyncRepository(
          sources: sources,
          connections: connections,
        ).synchronize(source.id).then((v) {
          completed = true;
          return v;
        });
    try {
      await entered.future.timeout(const Duration(seconds: 3));
      final page = await cursor();
      final items = await page.next().timeout(const Duration(seconds: 3));
      expect(items.single.identity.localId, 'first');
      expect(
        await connections
            .artwork(source.id, 'first')
            .timeout(const Duration(seconds: 3)),
        isNotEmpty,
      );
      expect(
        (await connections
                .detail(items.single)
                .timeout(const Duration(seconds: 3)))
            .itemId,
        'first',
      );
      final resource = await connections
          .preparePlayback(items.single)
          .timeout(const Duration(seconds: 3));
      expect(resource.uri.path, contains('first'));
      expect(completed, isFalse);
    } finally {
      release.complete();
      await syncing;
    }
  });

  test('unknown totals and server page caps visit every offset without eager loading', () async {
    server.includeTotal = false;
    server.catalog['movies'] = List.generate(5, (i) => _movie('$i'));
    final page = await cursor();
    expect((await page.next()).length, 2);
    expect((await sources.indexedSource(source.id)).length, 2);
    final ids = <String>['0', '1'];
    while (page.hasMore) {
      ids.addAll((await page.next()).map((i) => i.identity.localId));
    }
    expect(ids, ['0', '1', '2', '3', '4']);
    expect(
      server.requests
          .where((r) => r.uri.path.endsWith('/Items'))
          .map((r) => r.uri.queryParameters['StartIndex']),
      ['0', '2', '4', '5'],
    );
  });

  for (final episodes in [false, true]) {
    test(
      'completed sync rejects a delayed ${episodes ? 'episode' : 'video'} page',
      () async {
        server.catalog['movies'] = [_movie('obsolete')];
        server.catalog['shows'] = [
          {'Id': 'show', 'Name': 'Show', 'Type': 'Series'},
        ];
        await (await cursor(episodes ? 'shows' : 'movies')).next();
        final before = await sources.indexedSource(source.id);
        final staleCursor = episodes ? null : await cursor();
        final entered = Completer<void>(), release = Completer<void>();
        server.itemsHandler = (request) async {
          entered.complete();
          await release.future;
          await _respond(request, [
            if (episodes) _episode('obsolete', 1) else _movie('obsolete'),
          ]);
        };
        final pending = episodes
            ? browse.loadEpisodes((
                sourceId: source.id,
                localId: 'show',
              ), ScanCancellation())
            : staleCursor!.next();
        final rejected = expectLater(
          pending,
          throwsA(
            isA<SourceFailure>().having(
              (error) => error.message,
              'message',
              contains('已重新同步'),
            ),
          ),
        );
        try {
          await entered.future.timeout(const Duration(seconds: 3));
          // Keep the series parent so a stale episode could otherwise be
          // inserted successfully. A full snapshot removes the old movie.
          await sources.syncRemote(
            source.id,
            (_, _) async => [if (episodes) ...before],
          );
          expect((await sources.source(source.id)).lastScan, isNotNull);
        } finally {
          release.complete();
          await rejected;
        }
        expect(
          (await sources.indexedSource(source.id))
              .map((i) => i.identity.localId),
          episodes ? ['show'] : isEmpty,
        );
        // A newly opened cursor uses the completed version and still works.
        server.itemsHandler = null;
        server.catalog['movies'] = [_movie('current')];
        expect(
          (await (await cursor()).next()).single.identity.localId,
          'current',
        );
      },
    );
  }

  test(
    'successful remote sync advances its version even if the clock moves back',
    () async {
      final previous = DateTime.utc(2100).millisecondsSinceEpoch;
      await sources.database.customStatement(
        'UPDATE sources SET last_scan = ? WHERE id = ?',
        [previous, source.id],
      );
      await sources.syncRemote(source.id, (_, _) async => []);
      expect(
        (await sources.source(source.id)).lastScan!.millisecondsSinceEpoch,
        previous + 1,
      );
    },
  );

  test(
    'preview preserves existing trace, preferences and complete timestamp',
    () async {
      server.catalog['movies'] = [_movie('existing')];
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(source.id);
      final before = await sources.source(source.id);
      final id = (sourceId: source.id, localId: 'existing');
      await sources.setRemoteFavorite(id, false);
      await EmbyLibraryRepository(sources).setRating([id], 1);
      server.catalog['movies'] = [
        {..._movie('existing'), 'Name': 'Changed remotely'},
      ];
      await (await cursor()).next();
      expect((await sources.media(id)).title, 'Film existing');
      expect((await sources.media(id)).remote!.favorite, isFalse);
      expect(
        (await EmbyLibraryRepository(sources).snapshot(source.id))
            .entries
            .single
            .userRating,
        1,
      );
      expect((await sources.source(source.id)).lastScan, before.lastScan);
    },
  );

  test('changed scope and cancellation prevent stale preview writes', () async {
    server.catalog['movies'] = [_movie('stale')];
    final page = await cursor();
    await connections.selectLibraries(
      source.id,
      all: false,
      selected: ['shows'],
    );
    await expectLater(page.next(), throwsA(isA<SourceFailure>()));
    expect(await sources.indexedSource(source.id), isEmpty);
    await expectLater(
      browse.open(source.id, cancellation: ScanCancellation()..cancel()),
      throwsA(isA<ScanCancelled>()),
    );
  });

  test('repeated pages do not silently claim completeness', () async {
    server.catalog['movies'] = [_movie('a'), _movie('b'), _movie('c')];
    final page = await cursor();
    await page.next();
    server.itemsHandler = (r) =>
        _respond(r, [_movie('a'), _movie('b')], total: 3);
    await expectLater(page.next(), throwsA(isA<SourceFailure>()));
    expect(page.hasMore, isTrue);
    expect((await sources.indexedSource(source.id)).length, 2);
  });

  test('person provider exposes first page while next page waits and retains it on failure', () async {
    final entered = Completer<void>(), release = Completer<void>();
    server.itemsHandler = (r) async {
      if (r.uri.queryParameters['StartIndex'] == '0') {
        await _respond(r, [_movie('first', person: 'actor')], total: 2);
      } else {
        entered.complete();
        await release.future;
        r.response.statusCode = 503;
        await r.response.close();
      }
    };
    final repository = EmbyDetailRepository(
      sources: sources,
      connections: connections,
    );
    final container = ProviderContainer(
      overrides: [embyDetailRepositoryProvider.overrideWithValue(repository)],
    );
    final first = Completer<EmbyPersonWorks>();
    final fallback = Completer<EmbyPersonWorks>();
    final subscription = container.listen(
      embyPersonWorksProvider((sourceId: source.id, personKey: 'actor')),
      (_, value) {
        final data = value.asData?.value;
        if (data == null) return;
        if (data.items.isNotEmpty && !first.isCompleted) first.complete(data);
        if (data.warning != null && !fallback.isCompleted) {
          fallback.complete(data);
        }
      },
      fireImmediately: true,
    );
    try {
      await entered.future.timeout(const Duration(seconds: 3));
      final visible = await first.future.timeout(const Duration(seconds: 1));
      expect(visible.items.single.identity.localId, 'first');
      expect(visible.complete, isFalse);
      expect(release.isCompleted, isFalse);
      release.complete();
      expect(
        (await fallback.future.timeout(const Duration(seconds: 3)))
            .items
            .single
            .identity
            .localId,
        'first',
      );
    } finally {
      if (!release.isCompleted) release.complete();
      subscription.close();
      container.dispose();
    }
  });

  test('person works include unopened details, all pages and guest appearances in selected scope', () async {
    server.catalog['movies'] = [
      for (var i = 0; i < 5; i++) _movie('work$i', person: 'actor'),
      _movie('unrelated', person: 'elsewhere'),
    ];
    server.catalog['shows'] = [_episode('guest', 1)];
    final details = EmbyDetailRepository(
      sources: sources,
      connections: connections,
    );
    final all = await details.personWorks(source.id, 'actor');
    expect(all.map((i) => i.identity.localId).toSet(), {
      'work0',
      'work1',
      'work2',
      'work3',
      'work4',
      'show',
    });
    expect(await details.read((sourceId: source.id, localId: 'work4')), isNull);
    final requestCount = server.requests.length;
    expect((await details.cachedPersonWorks(source.id, 'actor')).length, 6);
    expect(server.requests.length, requestCount);
    expect(
      server.requests
          .where((r) => r.uri.path.endsWith('/Items'))
          .every((r) => r.uri.queryParameters['PersonIds'] == 'actor'),
      isTrue,
    );
    await connections.selectLibraries(
      source.id,
      all: false,
      selected: ['movies'],
    );
    // The recent full result must not leak works from the removed library.
    expect(await details.cachedPersonWorks(source.id, 'actor'), isEmpty);
    expect((await details.personWorks(source.id, 'actor')).length, 5);
  });

  test(
    'anonymous person uses exact name filter rather than title search',
    () async {
      server.catalog['movies'] = [
        _movie('named', name: '演员 & 甲'),
        _movie('other', name: '其他演员'),
      ];
      final details = EmbyDetailRepository(
        sources: sources,
        connections: connections,
      );
      expect(
        (await details.personWorks(
          source.id,
          'name:演员 & 甲',
        )).single.identity.localId,
        'named',
      );
      final q = server.requests
          .firstWhere((r) => r.uri.path.endsWith('/Items'))
          .uri
          .queryParameters;
      expect(q['Person'], '演员 & 甲');
      expect(q.containsKey('PersonIds'), isFalse);
      expect(q.containsKey('SearchTerm'), isFalse);
    },
  );

  test('preview series reads its own episodes without scanning unrelated libraries', () async {
    server.catalog['shows'] = [
      {'Id': 'show', 'Name': 'Show', 'Type': 'Series'},
    ];
    await (await cursor('shows')).next();
    server.catalog['show'] = [
      for (var i = 1; i <= 5; i++) _episode('episode$i', i),
    ];
    await browse.loadEpisodes((
      sourceId: source.id,
      localId: 'show',
    ), ScanCancellation());
    expect(
      (await sources.seasons((sourceId: source.id, localId: 'show')))
          .single
          .episodeCount,
      5,
    );
    expect((await sources.source(source.id)).lastScan, isNull);
  });

  testWidgets(
    'first-browse series right-click play prepares episodes before launching',
    (tester) async {
      final seriesId = (sourceId: source.id, localId: 'show');
      late IndexedMedia series;
      await tester.runAsync(() async {
        server.catalog['shows'] = [
          {'Id': 'show', 'Name': 'Show', 'Type': 'Series'},
        ];
        await (await cursor('shows')).next();
        series = await sources.media(seriesId);
        expect(await sources.seasons(seriesId), isEmpty);
        server.catalog['show'] = [
          _episode('episode1', 1),
          _episode('episode2', 2),
        ];
      });
      final launcher = _Launcher();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sources),
            embyConnectionProvider.overrideWithValue(connections),
            playbackLauncherProvider.overrideWithValue(launcher),
            // Playback must prepare independently of cache-menu prefetch.
            embyCacheCandidatesProvider.overrideWith((ref, id) async => []),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: EmbyVideoContextMenu(
                  item: series,
                  child: const SizedBox(
                    width: 200,
                    height: 60,
                    child: Text('Show'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show'), buttons: 2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('播放'));
      // MenuItemButton dispatches its action after the next frame.
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 100 && !launcher.opened.isCompleted;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(launcher.opened.isCompleted, isTrue);
      await tester.runAsync(() async {
        expect(
          await launcher.opened.future.timeout(const Duration(seconds: 3)),
          (sourceId: source.id, localId: 'episode1'),
        );
        expect((await sources.seasons(seriesId)).single.episodeCount, 2);
        expect((await sources.source(source.id)).lastScan, isNull);
      });
      await tester.pumpAndSettle();
      expect(find.text('此媒体没有可播放文件。'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      client.close(); // Retire HTTP keep-alive timers created by the widget action.
    },
  );

  testWidgets('first cards render without a complete scan', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    server.catalog['movies'] = List.generate(100, (i) => _movie('$i'));
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        embyConnectionProvider.overrideWithValue(connections),
        embyClientProvider.overrideWith((_) async => client),
        embyCredentialStoresProvider.overrideWithValue((id) => stores[id]!),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    for (
      var i = 0;
      i < 30 && find.byType(LocalMediaCard).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(LocalMediaCard), findsWidgets);
    expect(find.textContaining('已载入'), findsOneWidget);
    expect(
      (await tester.runAsync(() => sources.source(source.id)))!.lastScan,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    client.close();
    await tester.pump();
  });

  test(
    'cancellation after a batch rolls back every chunk of the snapshot',
    () async {
      server.catalog['movies'] = [_movie('old')];
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(source.id);
      final before = await sources.source(source.id);
      final items = List.generate(
        501,
        (i) => IndexedMedia(
          identity: (sourceId: source.id, localId: '$i'),
          title: '$i',
          type: 'movie',
          bytes: 0,
          modified: DateTime.utc(2026),
          remote: RemoteMediaMetadata(externalId: '$i'),
        ),
      );
      await expectLater(
        sources.syncRemote(
          source.id,
          (_, _) async => items,
          onProgress: (p) {
            if (p.phase == SourceScanPhase.persisting &&
                p.processedFiles == 250) {
              sources.cancel(source.id);
            }
          },
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(
        (await sources.indexedSource(source.id)).single.identity.localId,
        'old',
      );
      expect((await sources.source(source.id)).lastScan, before.lastScan);
    },
  );

  test('30000-row snapshot persists through the background SQLite isolate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reelnest-emby-batch-',
    );
    final repository = SourceRepository(
      database: LibraryDatabase(
        NativeDatabase.createInBackground(
          File('${directory.path}/library.sqlite'),
        ),
      ),
      adapters: {},
    );
    try {
      final target = await repository.add(
        kind: MediaSourceKind.emby,
        name: 'Benchmark',
        location: 'emby://fixture/benchmark',
        sourceId: 'benchmark',
        minimumFileSize: 0,
      );
      final items = List.generate(
        30000,
        (i) => IndexedMedia(
          identity: (sourceId: target.id, localId: '$i'),
          title: 'Film $i',
          type: 'movie',
          bytes: 1000,
          modified: DateTime.utc(2026),
          overview: 'Synthetic large-library benchmark.',
          remote: RemoteMediaMetadata(
            externalId: '$i',
            genres: const ['剧情'],
            rating: 8.4,
          ),
        ),
      );
      final progress = <int>[], watch = Stopwatch()..start();
      await repository.syncRemote(
        target.id,
        (_, _) async => items,
        onProgress: (p) {
          if (p.phase == SourceScanPhase.persisting) {
            progress.add(p.processedFiles);
          }
        },
      );
      debugPrint(
        'SQLITE_BACKGROUND_30000 persist_ms=${watch.elapsedMilliseconds}',
      );
      expect(progress.first, 0);
      expect(progress.last, 30000);
      expect(progress.length, 121);
      watch.reset();
      final library = EmbyLibraryRepository(repository);
      final snapshot = await library.snapshot(target.id);
      expect(snapshot.entries.length, 30000);
      final first = snapshot.entries.first;
      expect(first.userRating, 4);
      expect(first.searchTerms, contains("剧情"));
      final records = PlaybackRepository(repository.database);
      await records.save(
        first.item.identity,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 100),
      );
      final refreshed = await library.snapshot(target.id);
      expect(
        refreshed.entries.first.record.position,
        const Duration(seconds: 50),
      );
      expect(refreshed.entries.first.searchTerms, first.searchTerms);
      debugPrint(
        "BACKGROUND_SNAPSHOT_30000 two_refresh_ms=${watch.elapsedMilliseconds}",
      );
      expect((await repository.browse(target.id)).total, 30000);
      expect((await repository.source(target.id)).lastScan, isNotNull);
      final counted = await repository.source(target.id);
      final configWatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        final config = await repository.source(target.id, includeCounts: false);
        expect(config.options.toJson(), counted.options.toJson());
        expect(config.lastScan, counted.lastScan);
        expect(config.location, counted.location);
      }
      expect(counted.itemCount, 30000);
      debugPrint(
        'SOURCE_CONFIG_30000 100_reads_ms=${configWatch.elapsedMilliseconds}',
      );
    } finally {
      await repository.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
