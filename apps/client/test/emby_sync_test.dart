import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_item.dart';
import 'package:reelnest/app/reelnest_app.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/emby/emby_library_synchronizer.dart';
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

Map<String, dynamic> movie(String id, {String title = 'Movie'}) => {
  'Id': id,
  'Name': title,
  'Type': 'Movie',
  'ProductionYear': 2024,
  'OriginalTitle': 'Original',
  'Overview': 'A film overview',
  'RunTimeTicks': 900000000,
  'CommunityRating': 8.4,
  'ImageTags': {'Primary': 'poster-tag'},
  'BackdropImageTags': ['backdrop-tag'],
  'UserData': {
    'Played': false,
    'IsFavorite': true,
    'PlaybackPositionTicks': 100000000,
  },
  'Genres': ['Drama'],
  'MediaSources': [
    {'Id': 'media-$id', 'Container': 'mkv', 'Size': 1024},
  ],
};
Map<String, dynamic> episode(String id, int season, int number) => {
  ...movie(id, title: 'Episode $number'),
  'Type': 'Episode',
  'SeriesId': 'show',
  'SeriesName': 'A series',
  'ParentId': 'season-$season',
  'ParentIndexNumber': season,
  'IndexNumber': number,
};

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbySyncRepository sync;
  late MediaSource source;
  final stores = <String, _Store>{};
  bool closed = false;
  setUp(() async {
    closed = false;
    stores.clear();
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(
      deviceId: 'sync-device',
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
    sync = EmbySyncRepository(sources: sources, connections: connections);
    source = await connections.connect(server.address, 'tester', 'pw');
  });
  tearDown(() async {
    if (!closed) {
      connections.dispose();
      client.close();
      await sources.close();
      await server.close();
    }
  });
  Future<List<String>> ids() async =>
      (await sources.browse(source.id)).items
          .map((i) => i.identity.localId)
          .toList();

  test('real paginated requests map metadata, deduplicate libraries and synthesize series', () async {
    server.catalog['movies'] = [movie('m1'), movie('m2'), movie('m3')];
    server.catalog['shows'] = [
      movie('m1'),
      episode('e1', 0, 1),
      episode('e2', 2, 3),
    ];
    final result = await sync.synchronize(source.id);
    expect(result.importedItems, 6);
    final item = await sources.media((sourceId: source.id, localId: 'm1'));
    expect(item.remote!.durationMs, 90000);
    expect(item.remote!.positionMs, 10000);
    expect(item.remote!.favorite, isTrue);
    expect(item.remote!.container, 'mkv');
    expect(item.remote!.libraryId, 'movies');
    expect(item.remote!.genres, ['Drama']);
    expect(item.posterPath, 'm1');
    final seasons = await sources.seasons((
      sourceId: source.id,
      localId: 'show',
    ));
    expect(seasons.map((s) => s.number), [0, 2]);
    expect((await sources.browse(source.id, topLevelOnly: true)).total, 4);
    final requests = server.requests
        .where((r) => r.uri.path.endsWith('/Items'))
        .toList();
    expect(requests.map((r) => r.uri.queryParameters['StartIndex']), [
      '0',
      '2',
      '0',
      '2',
    ]);
    expect(
      requests.first.uri.queryParameters['IncludeItemTypes'],
      'Movie,Series,Episode,Audio',
    );
    expect(requests.first.uri.queryParameters['Limit'], '300');
    expect(
      requests.first.uri.queryParameters['Fields'],
      isNot(contains('Path,')),
    );
    final rows = await sources.database
        .customSelect('SELECT value FROM remote_media_metadata')
        .get();
    expect(
      rows.map((r) => r.read<String>('value')).join(),
      isNot(contains('token-')),
    );
  });
  test('provider ratings retain original 0-to-10 validity rules instead of clamping', () async {
    for (final rating in [0, -1, 11, 8.4]) {
      server.catalog['movies'] = [
        {...movie('rated'), 'CommunityRating': rating},
      ];
      await sync.synchronize(source.id);
      final item = await sources.media((sourceId: source.id, localId: 'rated'));
      expect(item.remote!.rating, rating == 8.4 ? 8.4 : null);
    }
  });
  test('specified scope queries only selected views and missing selected libraries produce empty scope', () async {
    server.catalog['movies'] = [movie('m')];
    server.catalog['shows'] = [episode('e', 1, 1)];
    await connections.selectLibraries(
      source.id,
      all: false,
      selected: ['shows'],
    );
    await sync.synchronize(source.id);
    expect(await ids(), ['e']);
    expect(
      server.requests
          .where((r) => r.uri.path.endsWith('/Items'))
          .every((r) => r.uri.queryParameters['ParentId'] == 'shows'),
      isTrue,
    );
    await connections.selectLibraries(
      source.id,
      all: false,
      selected: ['deleted-view'],
    );
    await sync.synchronize(source.id);
    expect(await ids(), isEmpty);
  });
  test('empty Views falls back to root only in all-libraries mode', () async {
    server.views = {'Items': []};
    server.catalog[''] = [movie('root')];
    await sync.synchronize(source.id);
    expect(await ids(), ['root']);
    expect(
      server.requests.last.uri.queryParameters.containsKey('ParentId'),
      isFalse,
    );
  });
  test(
    'without total continues after a short page until an empty page',
    () async {
      server.includeTotal = false;
      server.itemPageSize = 1;
      server.catalog['movies'] = [movie('a'), movie('b')];
      await sync.synchronize(source.id);
      final starts = server.requests
          .where((r) => r.uri.queryParameters['ParentId'] == 'movies')
          .map((r) => r.uri.queryParameters['StartIndex']);
      expect(starts, ['0', '1', '2']);
      expect(await ids(), ['a', 'b']);
    },
  );
  test('unsupported raw types do not prematurely stop pagination; audio is retained', () async {
    server.includeTotal = false;
    server.catalog['movies'] = [
      {'Id': 'unsupported', 'Name': 'Folder', 'Type': 'Folder'},
      {
        ...movie('audio'),
        'Type': 'Audio',
        'Artists': ['Artist'],
        'Album': 'Album',
      },
    ];
    await sync.synchronize(source.id);
    final item = (await sources.browse(source.id)).items.single;
    expect(item.type, 'music');
    expect(item.remote!.artist, 'Artist');
  });
  test('actual series metadata replaces synthetic candidate even if it arrives later', () async {
    server.catalog['shows'] = [
      episode('e', 1, 1),
      {
        'Id': 'show',
        'Name': 'Actual series',
        'Type': 'Series',
        'Overview': 'Show overview',
      },
    ];
    await sync.synchronize(source.id);
    final show = await sources.media((sourceId: source.id, localId: 'show'));
    expect(show.title, 'Actual series');
    expect(show.overview, 'Show overview');
  });
  test('later page failure retains full old index, local progress and last successful timestamp', () async {
    server.catalog['movies'] = [movie('old')];
    await sync.synchronize(source.id);
    final timestamp = (await sources.source(source.id)).lastScan;
    await sources.database.customStatement(
      'INSERT OR REPLACE INTO playback_states VALUES (?, ?, 1000, 90000, 0, 123)',
      [source.id, 'old'],
    );
    server.itemsHandler = (request) async {
      if (request.uri.queryParameters['StartIndex'] == '0') {
        request.response.write(
          jsonEncode({
            'Items': [movie('new')],
            'TotalRecordCount': 2,
          }),
        );
      } else {
        request.response.statusCode = 503;
      }
      await request.response.close();
    };
    await expectLater(
      sync.synchronize(source.id),
      throwsA(isA<SourceFailure>()),
    );
    expect(await ids(), ['old']);
    final retained = await sources.database
        .customSelect('SELECT position_ms FROM playback_states')
        .getSingle();
    expect(retained.read<int>('position_ms'), 1000);
    expect((await sources.source(source.id)).lastScan, timestamp);
    expect(
      (await sources.database
          .customSelect('SELECT * FROM playback_states')
          .get()),
      hasLength(1),
    );
  });
  test(
    'repeated pages with or without totals cannot prune old entries',
    () async {
      server.catalog['movies'] = [movie('old')];
      await sync.synchronize(source.id);
      for (final total in [null, 2, 100]) {
        server.itemsHandler = (request) async {
          request.response.write(
            jsonEncode({
              'Items': [movie('repeat')],
              'TotalRecordCount': ?total,
            }),
          );
          await request.response.close();
        };
        await expectLater(
          sync.synchronize(source.id),
          throwsA(isA<SourceFailure>()),
        );
        expect(await ids(), ['old']);
      }
    },
  );
  test(
    'overlapping pages or changing totals cannot commit an incomplete snapshot',
    () async {
      server.catalog['movies'] = [movie('old')];
      await sync.synchronize(source.id);
      for (final changeTotal in [false, true]) {
        server.itemsHandler = (request) async {
          final first = request.uri.queryParameters['StartIndex'] == '0';
          request.response.write(
            jsonEncode({
              'Items': first
                  ? [movie('a'), movie('b')]
                  : [movie('b'), movie('c')],
              'TotalRecordCount': first || !changeTotal ? 4 : 3,
            }),
          );
          await request.response.close();
        };
        await expectLater(
          sync.synchronize(source.id),
          throwsA(isA<SourceFailure>()),
        );
        expect(await ids(), ['old']);
      }
    },
  );
  test('iteration cap rejects incomplete snapshots', () async {
    final fetcher = EmbyLibrarySynchronizer(
      maxPages: 1,
      libraries: (_) async => [const EmbyLibrary(id: 'movies', name: 'Movies')],
      page: (_, _, _) async =>
          EmbyItemPage([EmbyItem.fromJson(movie('x'))], null),
    );
    await expectLater(
      fetcher.fetch(source, ScanCancellation()),
      throwsA(isA<SourceFailure>()),
    );
  });
  test('dangling series relations reject the snapshot instead of inventing standalone episodes', () async {
    server.catalog['movies'] = [movie('old')];
    await sync.synchronize(source.id);
    server.catalog['shows'] = [
      {...episode('broken', 1, 1)}..remove('SeriesName'),
    ];
    await expectLater(
      sync.synchronize(source.id),
      throwsA(isA<SourceFailure>()),
    );
    expect(await ids(), ['old']);
  });
  test('malformed or prematurely empty pages leave old index intact', () async {
    server.catalog['movies'] = [movie('old')];
    await sync.synchronize(source.id);
    for (final payload in [
      {'Items': [], 'TotalRecordCount': 10},
      {
        'Items': [
          {'Id': 'broken', 'Name': 'Bad'},
        ],
      },
      {'TotalRecordCount': 0},
    ]) {
      server.itemsHandler = (request) async {
        request.response.write(jsonEncode(payload));
        await request.response.close();
      };
      await expectLater(
        sync.synchronize(source.id),
        throwsA(isA<SourceFailure>()),
      );
      expect(await ids(), ['old']);
    }
  });
  test(
    'cancel aborts an in-flight HTTP request and keeps the last snapshot',
    () async {
      server.catalog['movies'] = [movie('old')];
      await sync.synchronize(source.id);
      final arrived = Completer<void>(), release = Completer<void>();
      server.itemsHandler = (request) async {
        arrived.complete();
        await release.future;
        try {
          await request.response.close();
        } catch (_) {}
      };
      final work = sync.synchronize(source.id);
      final assertion = expectLater(work, throwsA(isA<ScanCancelled>()));
      await arrived.future;
      sources.cancel(source.id);
      await assertion.timeout(const Duration(seconds: 2));
      release.complete();
      expect(await ids(), ['old']);
    },
  );
  test('SQL failure rolls back replacement and success later prunes only this source', () async {
    server.catalog['movies'] = [movie('old')];
    await sync.synchronize(source.id);
    final other = await connections.connect(server.address, 'tester', 'pw');
    await sync.synchronize(other.id);
    await sources.database.customStatement(
      "CREATE TRIGGER fail_import BEFORE INSERT ON media WHEN NEW.local_id = 'new' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    server.catalog['movies'] = [movie('new')];
    await expectLater(sync.synchronize(source.id), throwsA(anything));
    expect(await ids(), ['old']);
    await sources.database.customStatement('DROP TRIGGER fail_import');
    await sync.synchronize(source.id);
    expect(await ids(), ['new']);
    expect(
      (await sources.browse(other.id)).items.single.identity.localId,
      'old',
    );
  });
  test(
    'settings and removal are locked while syncing; cancellation unlocks them',
    () async {
      final arrived = Completer<void>(), release = Completer<void>();
      server.itemsHandler = (r) async {
        arrived.complete();
        await release.future;
        try {
          await r.response.close();
        } catch (_) {}
      };
      final work = sync.synchronize(source.id);
      final assertion = expectLater(work, throwsA(isA<ScanCancelled>()));
      await arrived.future;
      await expectLater(
        connections.selectLibraries(source.id, all: false, selected: ['shows']),
        throwsA(isA<SourceFailure>()),
      );
      await expectLater(
        connections.remove(source.id),
        throwsA(isA<SourceFailure>()),
      );
      sources.cancel(source.id);
      await assertion;
      release.complete();
      await connections.selectLibraries(
        source.id,
        all: false,
        selected: ['shows'],
      );
      expect((await sources.source(source.id)).options.selectedEmbyLibraryIDs, [
        'shows',
      ]);
    },
  );
  test('successful resync clears absent remote descriptions and metadata; deletion cascades', () async {
    server.catalog['movies'] = [movie('m')];
    await sync.synchronize(source.id);
    server.catalog['movies'] = [
      {'Id': 'm', 'Name': 'Updated', 'Type': 'Movie'},
    ];
    await sync.synchronize(source.id);
    final updated = await sources.media((sourceId: source.id, localId: 'm'));
    expect(updated.overview, isNull);
    expect(updated.posterPath, isNull);
    expect(updated.remote!.rating, isNull);
    await connections.remove(source.id);
    expect(
      await sources.database
          .customSelect('SELECT * FROM remote_media_metadata')
          .get(),
      isEmpty,
    );
  });
  test('artwork uses current credentials, proxy prefix and original sizing; a 401 refreshes once', () async {
    server.validToken = 'expired';
    final bytes = await connections.artwork(source.id, 'movie');
    expect(bytes.take(4), [137, 80, 78, 71]);
    expect(server.loginCount, 2);
    await connections.artwork(source.id, 'movie', backdrop: true);
    expect(
      server.requests.last.uri.path,
      '/proxy/emby/Items/movie/Images/Backdrop/0',
    );
    expect(server.requests.last.uri.queryParameters['maxWidth'], '1280');
    expect(server.requests.last.uri.queryParameters['quality'], '90');
  });
  test('artwork response limit aborts streaming and restrictions do not refresh credentials', () async {
    client.close();
    client = EmbyClient(
      deviceId: 'sync-device',
      maxArtworkBytes: 64,
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
    );
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores[id]!,
    );
    server.artworkHandler = (r) async {
      r.response.add(List.filled(1000, 1));
      await r.response.close();
    };
    await expectLater(
      connections.artwork(source.id, 'poster'),
      throwsA(
        isA<EmbyFailure>().having((e) => e.kind, 'kind', EmbyError.tooLarge),
      ),
    );
    server.artworkHandler = (r) async {
      r.response.statusCode = 403;
      await r.response.close();
    };
    await expectLater(
      connections.artwork(source.id, 'poster'),
      throwsA(
        isA<EmbyFailure>().having((e) => e.kind, 'kind', EmbyError.restricted),
      ),
    );
    expect(server.loginCount, 1);
  });
  testWidgets(
    'adding Emby through the wizard automatically queues synchronization',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      server.catalog['movies'] = [movie('automatic')];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sources),
            embyClientProvider.overrideWith((_) async => client),
            embyCredentialStoresProvider.overrideWithValue(
              (id) => stores.putIfAbsent(id, _Store.new),
            ),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理媒体源'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emby'));
      await tester.pump();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('emby-server')),
        server.address,
      );
      await tester.enterText(
        find.byKey(const ValueKey('emby-username')),
        'tester',
      );
      await tester.enterText(find.byKey(const ValueKey('emby-password')), 'pw');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录并同步'));
      for (
        var n = 0;
        n < 150 && find.text('同步完成：1 个媒体条目').evaluate().isEmpty;
        n++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('同步完成：1 个媒体条目'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      connections.dispose();
      client.close();
      await tester.runAsync(sources.close);
      await tester.runAsync(server.close);
      closed = true;
    },
  );
  testWidgets(
    'synced remote source browses posters, opens detail and groups episodes without local file probes',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      server.catalog['shows'] = [episode('e1', 1, 1), episode('e2', 2, 1)];
      Future<void> finish(Future<void> work) async {
        var done = false;
        work.then((_) => done = true);
        for (var n = 0; n < 200 && !done; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(done, isTrue);
      }

      await finish(sync.synchronize(source.id).then((_) {}));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sources),
            embyClientProvider.overrideWith((_) async => client),
            embyCredentialStoresProvider.overrideWithValue((id) => stores[id]!),
          ],
          child: const ReelNestApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('管理媒体源'));
      await tester.pumpAndSettle();
      for (var n = 0; n < 100 && find.text('浏览媒体').evaluate().isEmpty; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(find.text('浏览媒体'));
      await tester.pumpAndSettle();
      for (
        var n = 0;
        n < 100 && find.text('A series').evaluate().isEmpty;
        n++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is TextButton &&
                  w.child is SizedBox &&
                  (w.child as SizedBox).width == double.infinity,
            )
            .last,
      );
      await tester.pumpAndSettle();
      for (var n = 0; n < 100 && find.text('第 1 季').evaluate().isEmpty; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('第 1 季'), findsOneWidget);
      expect(find.text('第 2 季'), findsOneWidget);
      expect(find.text('所选文件当前不可访问。'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      connections.dispose();
      client.close();
      await finish(sources.close());
      await tester.runAsync(server.close);
      closed = true;
    },
  );
}
