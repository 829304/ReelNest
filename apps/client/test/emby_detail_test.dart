import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_detail.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_detail_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/emby_detail_extras.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/platform/external_links.dart';
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

Map<String, dynamic> fixtureDetail(String id) => {
  'Id': id,
  'Type': 'Movie',
  'Name': 'Server title',
  'Overview': '服务器简介',
  'RunTimeTicks': 900000000,
  'Status': 'Ended',
  'OfficialRating': 'PG-13',
  'ProductionLocations': ['中国', '美国'],
  'Studios': [
    {'Name': 'Studio'},
  ],
  'Genres': ['剧情', '科幻'],
  'ProviderIds': {'Tmdb': '123', 'Imdb': 'tt456'},
  'BackdropImageTags': ['first', 'second'],
  'ImageTags': {'Primary': 'poster'},
  'People': [
    {
      'Id': 'director',
      'Name': '导演甲',
      'Type': 'Director',
      'PrimaryImageTag': 'tag',
    },
    {
      'Id': 'actor',
      'Name': '演员乙',
      'Type': 'Actor',
      'Role': '角色乙',
      'PrimaryImageTag': 'tag',
    },
    {'Name': '客串', 'Type': 'GuestStar'},
  ],
  'MediaSources': [
    {
      'Id': 'wrong',
      'MediaStreams': [
        {'Type': 'Video', 'Codec': 'h264'},
      ],
    },
    {
      'Id': 'resource',
      'Size': 987654321,
      'Bitrate': 12345678,
      'Container': 'mkv',
      'Path': 'http://server/video?api_key=SECRET',
      'MediaStreams': [
        {
          'Type': 'Video',
          'Codec': 'hevc',
          'Width': 3840,
          'Height': 2160,
          'BitRate': 10000000,
        },
        {'Type': 'Audio', 'Codec': 'aac'},
        {'Type': 'Subtitle', 'DeliveryUrl': '/sub?api_key=SECRET'},
      ],
    },
  ],
  'UserData': {'IsFavorite': true, 'Played': true},
};

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbySyncRepository sync;
  late EmbyDetailRepository details;
  late MediaSource source;
  final stores = <String, _Store>{};
  var time = DateTime.utc(2026, 10, 9);
  MediaIdentity id(String key) => (sourceId: source.id, localId: key);
  int getRequests() =>
      server.requests.where((r) => r.uri.path.endsWith('/Items/film')).length;
  setUp(() async {
    time = DateTime.utc(2026, 10, 9);
    stores.clear();
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(
      deviceId: 'details-test',
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
    source = await connections.connect(server.address, 'tester', 'fixture');
    server.catalog['movies'] = [
      {
        'Id': 'film',
        'Name': '本地片名',
        'Type': 'Movie',
        'ProductionYear': 2024,
        'Overview': '基础简介',
        'RunTimeTicks': 900000000,
        'MediaSources': [
          {
            'Id': 'resource',
            'Container': 'mkv',
            'MediaStreams': [
              {'Type': 'Video', 'Codec': 'hevc', 'Width': 3840, 'Height': 2160},
              {'Type': 'Audio', 'Codec': 'aac'},
            ],
          },
        ],
        'UserData': {
          'PlaybackPositionTicks': 200000000,
          'Played': false,
          'IsFavorite': false,
        },
      },
    ];
    sync = EmbySyncRepository(sources: sources, connections: connections);
    await sync.synchronize(source.id);
    details = EmbyDetailRepository(
      sources: sources,
      connections: connections,
      now: () => time,
    );
    server.detailHandler = (r) async {
      r.response.write(jsonEncode(fixtureDetail(r.uri.pathSegments.last)));
      await r.response.close();
    };
  });
  tearDown(() async {
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
  });
  test('detail authenticates, requests extras fields, caches sanitized identity-only data', () async {
    server.validToken = 'expired';
    final snapshot = await details.load(id('film'));
    expect(server.loginCount, 2);
    expect(snapshot.detail.cast.map((p) => p.name), ['演员乙', '客串']);
    expect(snapshot.detail.crew.single.role, '导演');
    expect(snapshot.detail.technical.resolution, '3840x2160');
    expect(snapshot.detail.technical.videoCodec, 'hevc');
    expect(snapshot.detail.technical.audioCodec, 'aac');
    expect(snapshot.detail.technical.bitrate, 12345678);
    expect(snapshot.detail.backdropCount, 2);
    expect(snapshot.detail.hasPoster, isTrue);
    final request = server.requests.last;
    expect(request.uri.path, '/proxy/emby/Users/user-1/Items/film');
    expect(request.uri.queryParameters['Fields'], contains('People'));
    final raw =
        (await sources.database
                .customSelect('SELECT value FROM remote_media_details')
                .getSingle())
            .read<String>('value');
    expect(raw, isNot(contains('SECRET')));
    expect(raw, isNot(contains('api_key')));
    expect(raw, isNot(contains(server.address)));
    expect(raw, isNot(contains('token-')));
    expect(
      (await details.read(id('film')))!.detail.technical.resolution,
      '3840x2160',
    );
  });
  test(
    'detail never replaces title, scope, favorite or playback trace',
    () async {
      final before = await PlaybackRepository(sources.database)
          .read(id('film'));
      await details.load(id('film'));
      final item = await sources.media(id('film'));
      final after = await PlaybackRepository(sources.database).read(id('film'));
      expect(item.title, '本地片名');
      expect(item.remote!.favorite, isFalse);
      expect(item.remote!.libraryId, 'movies');
      expect(after.watched, isFalse);
      expect(after.position, before.position);
      expect(item.remote!.videoCodec, 'hevc');
      expect(item.remote!.resolution, '3840x2160');
    },
  );
  test('30-day cache persists and force refresh bypasses it', () async {
    await details.load(id('film'));
    expect(getRequests(), 1);
    final restarted = EmbyDetailRepository(
      sources: sources,
      connections: connections,
      now: () => time,
    );
    time = time.add(const Duration(days: 29));
    await restarted.load(id('film'));
    expect(getRequests(), 1);
    time = time.add(const Duration(days: 1));
    await restarted.load(id('film'));
    expect(getRequests(), 2);
    await restarted.load(id('film'), force: true);
    expect(getRequests(), 3);
  });
  test('failed refresh preserves previous snapshot and timestamp', () async {
    final first = await details.load(id('film'));
    server.detailHandler = (r) async {
      r.response.statusCode = 503;
      await r.response.close();
    };
    final fallback = await details.load(id('film'), force: true);
    expect(fallback.refreshError, isNotNull);
    expect(fallback.detail.cast.first.name, '演员乙');
    expect(fallback.fetchedAt, first.fetchedAt);
    expect((await details.read(id('film')))!.refreshError, isNull);
  });
  test('mismatched or malformed detail does not overwrite cache', () async {
    await details.load(id('film'));
    server.detailHandler = (r) async {
      r.response.write(
        jsonEncode({...fixtureDetail('other'), 'People': 'invalid'}),
      );
      await r.response.close();
    };
    expect(
      (await details.load(id('film'), force: true)).refreshError,
      isNotNull,
    );
    expect((await details.read(id('film')))!.detail.itemId, 'film');
  });
  test('empty optional fields are supported; invalid image URLs never become links', () {
    final empty = EmbyDetail.fromServer({'Id': 'film'}, 'film');
    expect(empty.people, isEmpty);
    expect(empty.backdropCount, 0);
    expect(empty.technical.resolution, isNull);
    final malicious = EmbyDetail.fromServer({
      ...fixtureDetail('film'),
      'ProviderIds': {
        'Tmdb': '../x?api_key=SECRET',
        'Imdb': 'https://evil.invalid',
      },
    }, 'film');
    expect(detailLinks('A&B 中文', malicious).length, 2);
    expect(
      detailLinks('A&B 中文', malicious)['豆瓣']!.queryParameters['search_text'],
      'A&B 中文',
    );
  });
  test('people capped before filtering; countries/studios capped, fallback roles stable', () {
    final dto = {
      ...fixtureDetail('film'),
      'People': [
        for (var n = 0; n < 35; n++) {'Name': 'Person$n', 'Type': 'Writer'},
      ],
      'ProductionLocations': List.generate(12, (i) => 'Country$i'),
      'Studios': List.generate(12, (i) => {'Name': 'Studio$i'}),
    };
    final detail = EmbyDetail.fromServer(dto, 'film');
    expect(detail.people.length, 28);
    expect(detail.crew.first.role, '编剧');
    expect(detail.countries.length, 8);
    expect(detail.companies.length, 8);
    expect(
      EmbyDetail.fromServer(dto, 'film').people.first.key,
      detail.people.first.key,
    );
  });
  test('image endpoints support person portrait, indexed backdrop, bounds and live auth', () async {
    await connections.artwork(source.id, 'actor', maxWidth: 185);
    expect(
      server.requests.last.uri.path,
      endsWith('/Items/actor/Images/Primary'),
    );
    expect(server.requests.last.uri.queryParameters['maxWidth'], '185');
    await connections.artwork(
      source.id,
      'film',
      backdrop: true,
      index: 1,
      maxWidth: 500,
    );
    expect(server.requests.last.uri.path, endsWith('/Images/Backdrop/1'));
    expect(server.requests.last.uri.queryParameters['maxWidth'], '500');
    server.validToken = 'expired';
    await connections.artwork(source.id, 'film', maxWidth: 100000);
    expect(server.requests.last.uri.queryParameters['maxWidth'], '2048');
    expect(server.requests.last.uri.queryParameters['api_key'], 'token-2');
  });
  test(
    'queued cancellation exits promptly and never sends or caches later',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      server.artworkHandler = (r) async {
        entered.complete();
        await release.future;
        r.response.add([1]);
        await r.response.close();
      };
      final blocker = connections.artwork(source.id, 'film');
      await entered.future;
      final token = ScanCancellation();
      final request = details.load(id('film'), cancellation: token);
      final expected = expectLater(request, throwsA(isA<ScanCancelled>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      token.cancel();
      await expected.timeout(const Duration(milliseconds: 200));
      release.complete();
      await blocker;
      expect(getRequests(), 0);
      expect(await details.read(id('film')), isNull);
    },
  );
  test(
    'queue timeout returns cached result and obsolete task never sends',
    () async {
      await details.load(id('film'));
      final entered = Completer<void>(), release = Completer<void>();
      server.artworkHandler = (r) async {
        entered.complete();
        await release.future;
        r.response.add([1]);
        await r.response.close();
      };
      final blocker = connections.artwork(source.id, 'film');
      await entered.future;
      final bounded = EmbyDetailRepository(
        sources: sources,
        connections: connections,
        timeout: const Duration(milliseconds: 40),
        now: () => time,
      );
      final result = await bounded.load(id('film'), force: true);
      expect(result.refreshError, isNotNull);
      release.complete();
      await blocker;
      await connections.session(source.id);
      expect(getRequests(), 1);
    },
  );
  test('removing item during fetch prevents caching and foreign keys clean snapshots', () async {
    await details.load(id('film'));
    final entered = Completer<void>(), release = Completer<void>();
    server.detailHandler = (r) async {
      entered.complete();
      await release.future;
      r.response.write(jsonEncode(fixtureDetail('film')));
      await r.response.close();
    };
    final request = details.load(id('film'), force: true);
    await entered.future;
    await sources.database.customStatement(
      'DELETE FROM media WHERE source_id = ? AND local_id = ?',
      [source.id, 'film'],
    );
    release.complete();
    await request;
    expect(await details.read(id('film')), isNull);
  });
  test('same IDs from another account remain isolated; person works use cached credits', () async {
    await details.load(id('film'));
    final other = await connections.connect(
      server.address,
      'tester',
      'fixture',
    );
    await sync.synchronize(other.id);
    expect(await details.read((sourceId: other.id, localId: 'film')), isNull);
    expect(
      (await details.personWorks(source.id, 'actor')).single.identity,
      id('film'),
    );
    expect(await details.personWorks(other.id, 'actor'), isEmpty);
  });

  testWidgets(
    'desktop detail renders metadata, people, artwork, collapse and browser links',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1088, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final snapshot = await tester.runAsync(() => details.load(id('film')));
      final opened = <Uri>[];
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourceRepositoryProvider.overrideWithValue(sources),
            embyConnectionProvider.overrideWithValue(connections),
            embyDetailRepositoryProvider.overrideWithValue(details),
            embyDetailProvider.overrideWith(
              (ref, key) => Stream.value(snapshot!),
            ),
            embyDetailImageProvider.overrideWith((ref, key) async => png),
            embyArtworkProvider.overrideWith((ref, key) async => png),
            externalLinkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
            }),
          ],
          child: MaterialApp(
            home: Scaffold(body: LocalMediaDetailPage(identity: id('film'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('服务器简介'), findsOneWidget);
      expect(find.textContaining('3840x2160'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('演员').first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('导演甲'), findsOneWidget);
      expect(find.text('演员乙'), findsOneWidget);
      await tester.tap(find.text('演员乙'));
      await tester.pumpAndSettle();
      expect(find.text('人物'), findsOneWidget);
      expect(find.text('库中作品'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(EmbyPersonPage),
          matching: find.text('本地片名'),
        ),
        findsWidgets,
      );
      await tester.tap(find.text('返回'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('IMDb'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('IMDb'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://www.imdb.com/title/tt456/');
      final detailsToggle = find.descendant(
        of: find.byType(TextButton),
        matching: find.text('详情'),
      );
      // This sliver is taller than the viewport: scroll its header into view,
      // rather than ensureVisible aligning the entire extras sliver.
      while (tester.getCenter(detailsToggle).dy < 40) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 220));
        await tester.pumpAndSettle();
      }
      await tester.tap(detailsToggle);
      await tester.pumpAndSettle();
      expect(find.text('演员'), findsNothing);
      expect(tester.takeException(), isNull);
      client.close();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('artwork viewer pages, zooms and closes with Escape', (
    tester,
  ) async {
    final detail = EmbyDetail.fromServer(fixtureDetail('film'), 'film');
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          embyDetailImageProvider.overrideWith((ref, key) async => png),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => EmbyArtworkViewer(
                    source: source,
                    title: 'Film',
                    detail: detail,
                    initialIndex: 0,
                    revision: 1,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      2,
    );
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(EmbyArtworkViewer), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
