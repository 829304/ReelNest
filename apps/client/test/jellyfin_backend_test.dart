import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/data/emby_browse_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/emby_server_fixture.dart';
import 'support/fake_video_engine.dart';

class _Http extends HttpOverrides {}

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

Map<String, dynamic> jellyfinVideo(
  String id, {
  String type = 'Movie',
  int? episode,
}) => {
  'Id': id,
  'Name': id,
  'Type': type,
  'Overview': 'Jellyfin overview',
  'ProductionYear': 2024,
  'RunTimeTicks': 1000000000,
  'CommunityRating': 8.5,
  'ImageTags': {'Primary': 'poster-1'},
  'BackdropImageTags': ['backdrop-1'],
  if (type == 'Episode') ...{
    'SeriesId': 'show',
    'SeriesName': 'show',
    'ParentIndexNumber': 1,
    'IndexNumber': episode,
  },
  'UserData': {
    'PlaybackPositionTicks': 250000000,
    'Played': false,
    'IsFavorite': false,
  },
  'MediaSources': [
    {
      'Id': 'media-$id',
      'Container': 'mkv',
      'Size': 1024,
      'RunTimeTicks': 1000000000,
      'MediaStreams': [
        {
          'Type': 'Video',
          'Index': 0,
          'Codec': 'h264',
          'Width': 1920,
          'Height': 1080,
        },
        {'Type': 'Audio', 'Index': 1, 'Codec': 'aac', 'Language': 'eng'},
        {
          'Type': 'Subtitle',
          'Index': 2,
          'Codec': 'srt',
          'Language': 'eng',
          'IsExternal': true,
          'IsTextSubtitleStream': true,
          'DeliveryUrl':
              'Videos/$id/media-$id/Subtitles/2/Stream.srt?api_key=stale',
        },
      ],
    },
  ],
  'People': [
    {'Id': 'actor-1', 'Name': 'Actor', 'Type': 'Actor', 'Role': 'Role'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late MediaSource source;
  final stores = <String, _Store>{};
  setUp(() async {
    stores.clear();
    server = EmbyServerFixture(kind: MediaSourceKind.jellyfin);
    await server.start();
    server.catalog['movies'] = [jellyfinVideo('film'), jellyfinVideo('second')];
    server.catalog['shows'] = [
      jellyfinVideo('show', type: 'Series'),
      jellyfinVideo('ep1', type: 'Episode', episode: 1),
      jellyfinVideo('ep2', type: 'Episode', episode: 2),
    ];
    server.catalog['show'] = [
      jellyfinVideo('ep1', type: 'Episode', episode: 1),
      jellyfinVideo('ep2', type: 'Episode', episode: 2),
    ];
    server.detailHandler = (r) async {
      final id = r.uri.pathSegments.last;
      r.response.write(jsonEncode(jellyfinVideo(id)));
      await r.response.close();
    };
    client = EmbyClient(
      deviceId: 'jellyfin-device',
      http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _Http()),
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
    source = await connections.connect(
      server.address,
      'tester',
      'fixture-password',
      kind: MediaSourceKind.jellyfin,
    );
  });
  tearDown(() async {
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
  });
  Future<void> sync() => EmbySyncRepository(
    sources: sources,
    connections: connections,
  ).synchronize(source.id).then((_) {});
  MediaIdentity identity(String id) => (sourceId: source.id, localId: id);

  test('Jellyfin identity, modern login/views, proxy base and token-free SQL are distinct', () async {
    expect(source.kind, MediaSourceKind.jellyfin);
    expect(source.name, 'Jellyfin 媒体库');
    expect(Uri.parse(source.location).scheme, 'jellyfin');
    expect(
      (await connections.session(source.id)).kind,
      MediaSourceKind.jellyfin,
    );
    expect(
      server.requests.first.uri.path,
      '/proxy/jellyfin/Users/AuthenticateByName',
    );
    expect(jsonDecode(server.requests.first.body), {
      'Username': 'tester',
      'Pw': 'fixture-password',
    });
    final views = server.requests.singleWhere(
      (r) => r.uri.path.endsWith('/UserViews'),
    );
    expect(views.uri.queryParameters['UserId'], 'user-1');
    expect(views.uri.queryParameters.containsKey('api_key'), isFalse);
    expect(views.authorization, contains('MediaBrowser'));
    expect(views.authorization, contains('Token="token-1"'));
    final rows = await sources.database
        .customSelect('SELECT key,value FROM player_preferences')
        .get();
    expect(rows.single.read<String>('key'), 'connector.jellyfin.${source.id}');
    expect(rows.single.data.toString(), isNot(contains('token-1')));
    expect(rows.single.data.toString(), isNot(contains('fixture-password')));
    expect(await sources.isReachable(source), isFalse);
    expect(await connections.isReachable(source), isTrue);
  });
  test(
    'restored credentials retain provider and refresh expired session once',
    () async {
      connections.dispose();
      connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: (id) => stores[id]!,
      );
      server.validToken = 'expired';
      final value = await connections.session(source.id);
      expect(value.kind, MediaSourceKind.jellyfin);
      expect(value.token, 'token-2');
      expect(server.loginCount, 2);
      expect(
        jsonDecode(stores[source.id]!.value!)['session']['kind'],
        'jellyfin',
      );
    },
  );
  test('modern foreground paging shows first library without complete sync or episodes', () async {
    final browser = EmbyBrowseRepository(sources, connections);
    final cursor = await browser.open(
      source.id,
      libraryId: 'movies',
      cancellation: ScanCancellation(),
    );
    final page = await cursor.next();
    expect(page.map((i) => i.title), ['film', 'second']);
    expect((await sources.source(source.id)).lastScan, isNull);
    expect(await sources.indexedSource(source.id), hasLength(2));
    final request = server.requests.lastWhere(
      (r) => r.uri.path.endsWith('/Items'),
    );
    expect(request.uri.path, '/proxy/jellyfin/Items');
    expect(request.uri.queryParameters['UserId'], 'user-1');
    expect(request.uri.queryParameters['ParentId'], 'movies');
  });
  test('full sync, source counts, snapshots, home and provider search share real indexed identity', () async {
    await sync();
    final current = await sources.source(source.id);
    expect(current.lastScan, isNotNull);
    expect(current.itemCount, 5);
    final snapshot = await EmbyLibraryRepository(sources).snapshot(source.id);
    expect(snapshot.source.kind, MediaSourceKind.jellyfin);
    expect(snapshot.entries, hasLength(5));
    expect(HomeRepository.accepts(current), isTrue);
    expect(
      await HomeRepository(sources).recommendationCandidates(source.id),
      isNotEmpty,
    );
    final catalogRequests = server.requests.where(
      (r) => r.uri.path.endsWith('/Items'),
    );
    expect(
      catalogRequests.every((r) => r.uri.queryParameters['UserId'] == 'user-1'),
      isTrue,
    );
    expect(catalogRequests.any((r) => r.uri.path.contains('/Users/')), isFalse);
  });
  test(
    'selected libraries scope sync and expansion invalidates completeness',
    () async {
      await connections.selectLibraries(
        source.id,
        all: false,
        selected: ['movies'],
      );
      await sync();
      expect(await sources.indexedSource(source.id), hasLength(2));
      await connections.selectLibraries(source.id, all: true, selected: []);
      expect((await sources.source(source.id)).lastScan, isNull);
      expect(await sources.indexedSource(source.id), hasLength(2));
      await sync();
      expect(await sources.indexedSource(source.id), hasLength(5));
    },
  );
  test('first-browse series hydrates only its own episodes', () async {
    final browser = EmbyBrowseRepository(sources, connections);
    final cursor = await browser.open(
      source.id,
      libraryId: 'shows',
      cancellation: ScanCancellation(),
    );
    await cursor.next();
    expect(await sources.indexedChildren(identity('show')), isEmpty);
    await browser.loadEpisodes(identity('show'), ScanCancellation());
    expect(
      (await sources.indexedChildren(identity('show')))
          .map((i) => i.episodeNumber),
      [1, 2],
    );
    expect((await sources.source(source.id)).lastScan, isNull);
  });
  test('modern item details and subtitle bytes use user scope and refreshed standard authentication', () async {
    await sync();
    final item = await sources.media(identity('film'));
    final detail = await connections.detail(item);
    expect(detail.cast.single.name, 'Actor');
    final tracks = await connections.subtitles(item);
    expect(tracks, hasLength(1));
    server.streamHandler = (r) async {
      r.response.write('1\n00:00:00,000 --> 00:00:01,000\nSubtitle\n');
      await r.response.close();
    };
    final bytes = await connections.subtitle(item, tracks.single);
    expect(utf8.decode(bytes), contains('Subtitle'));
    expect(
      server.requests.last.uri.queryParameters.containsKey('api_key'),
      isFalse,
    );
    expect(server.requests.last.authorization, contains('Token="token-1"'));
  });
  test(
    'favorites and watched write to modern endpoints and local records',
    () async {
      await sync();
      await connections.setFavorite(identity('film'), true);
      expect((await sources.media(identity('film'))).remote!.favorite, isTrue);
      expect(await connections.markPlayed([identity('film')], true), 0);
      expect(
        (await PlaybackRepository(sources.database).read(identity('film')))
            .watched,
        isTrue,
      );
      expect(
        server.requests.any(
          (r) =>
              r.uri.path.endsWith('/UserFavoriteItems/film') &&
              r.uri.queryParameters['UserId'] == 'user-1',
        ),
        isTrue,
      );
      expect(
        server.requests.any(
          (r) => r.uri.path.endsWith('/UserPlayedItems/film'),
        ),
        isTrue,
      );
    },
  );
  test('playback session resumes with ApiKey and reports start/progress/stop without storing URL', () async {
    await sync();
    final engine = FakeVideoEngine();
    final records = PlaybackRepository(sources.database);
    final player = PlaybackSession(
      sources: sources,
      records: records,
      emby: connections,
      createEngine: () => engine,
    );
    try {
      await player.open(identity('film'));
      expect(player.lastOpenSucceeded, isTrue);
      expect(player.error, isNull);
      final uri = Uri.parse(engine.openedPath!);
      expect(uri.path, '/proxy/jellyfin/Videos/film/stream.mkv');
      expect(uri.queryParameters['ApiKey'], 'token-1');
      expect(uri.queryParameters.containsKey('api_key'), isFalse);
      // The original default rewinds five seconds when resuming.
      expect(engine.openedAt, const Duration(seconds: 20));
      engine.emit(position: const Duration(seconds: 40), playing: false);
      await player.close();
      expect(
        (await records.read(identity('film'))).position,
        const Duration(seconds: 40),
      );
      final reports = server.requests
          .where((r) => r.uri.path.contains('/Sessions/Playing'))
          .toList();
      expect(reports.first.uri.path.endsWith('/Sessions/Playing'), isTrue);
      expect(reports.last.uri.path.endsWith('/Stopped'), isTrue);
      expect(
        reports.every(
          (r) => r.authorization?.contains('Token="token-1"') == true,
        ),
        isTrue,
      );
      final rows = await sources.database
          .customSelect('SELECT value FROM remote_media_metadata')
          .get();
      expect(
        rows.map((r) => r.data.toString()).join(),
        isNot(contains('token-1')),
      );
      expect(
        rows.map((r) => r.data.toString()).join(),
        isNot(contains('http://')),
      );
    } finally {
      await player.close();
      player.dispose();
    }
  });
  test(
    'bare stream download preserves ApiKey through same-origin redirect',
    () async {
      await sync();
      final item = await sources.media(identity('film'));
      server.streamHandler = (r) async {
        r.response.headers.contentType = ContentType.binary;
        if (!r.uri.path.endsWith('/redirected')) {
          r.response.statusCode = 307;
          r.response.headers.set(
            HttpHeaders.locationHeader,
            '/proxy/jellyfin/Videos/film/redirected',
          );
        } else {
          r.response.add([1, 2, 3, 4]);
        }
        await r.response.close();
      };
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-jellyfin-download-',
      );
      try {
        final target = File('${sandbox.path}/video.part');
        final resource = await connections.preparePlayback(item);
        await client.download(resource, target, ScanCancellation());
        expect(await target.readAsBytes(), [1, 2, 3, 4]);
        expect(server.requests.last.uri.queryParameters['ApiKey'], 'token-1');
        expect(
          server.requests.last.uri.queryParameters.containsKey('api_key'),
          isFalse,
        );
      } finally {
        await sandbox.delete(recursive: true);
      }
    },
  );
  test(
    'reauthentication rejects a different user and keeps original provider',
    () async {
      await connections.reauthenticate(source.id, 'tester', 'new-password');
      expect(
        (await connections.session(source.id)).kind,
        MediaSourceKind.jellyfin,
      );
      server.userId = 'other-user';
      await expectLater(
        connections.reauthenticate(source.id, 'other', 'other-password'),
        throwsA(isA<EmbyFailure>()),
      );
      expect(
        jsonDecode(stores[source.id]!.value!)['session']['userId'],
        'user-1',
      );
    },
  );
  test(
    'credential provider tampering is rejected before authenticated request',
    () async {
      final data =
          jsonDecode(stores[source.id]!.value!) as Map<String, dynamic>;
      (data['session'] as Map)['kind'] = 'emby';
      stores[source.id]!.value = jsonEncode(data);
      final count = server.requests.length;
      await expectLater(
        connections.session(source.id),
        throwsA(isA<SourceFailure>()),
      );
      expect(server.requests, hasLength(count));
    },
  );
  test(
    'source removal clears Jellyfin configuration and credentials only',
    () async {
      final other = await connections.connect(
        server.address,
        'tester',
        'password',
        kind: MediaSourceKind.jellyfin,
      );
      await sync();
      await connections.remove(source.id);
      expect((await sources.sources()).single.id, other.id);
      expect(stores[source.id]!.value, isNull);
      expect(stores[other.id]!.value, isNotNull);
      final rows = await sources.database
          .customSelect(
            'SELECT key FROM player_preferences WHERE key LIKE \'connector.%\'',
          )
          .get();
      expect(rows.map((r) => r.read<String>('key')), [
        'connector.jellyfin.${other.id}',
      ]);
    },
  );
  for (final mode in [
    RemoteTraceSyncMode.importOnly,
    RemoteTraceSyncMode.disabled,
  ]) {
    test(
      'Jellyfin trace mode ${mode.name} does not write remote state',
      () async {
        await connections.selectLibraries(
          source.id,
          all: true,
          selected: [],
          trace: mode,
        );
        await sync();
        await connections.markPlayed([identity('film')], true);
        final player = PlaybackSession(
          sources: sources,
          records: PlaybackRepository(sources.database),
          emby: connections,
          createEngine: FakeVideoEngine.new,
        );
        try {
          await player.open(identity('film'));
          expect(player.lastOpenSucceeded, isTrue);
          await player.close();
          expect(
            server.requests.where(
              (r) =>
                  r.uri.path.contains('/Sessions/Playing') ||
                  r.uri.path.contains('/UserPlayedItems/'),
            ),
            isEmpty,
          );
        } finally {
          await player.close();
          player.dispose();
        }
      },
    );
  }
  test(
    'provider replacement during sync cannot commit the old provider snapshot',
    () async {
      await sync();
      await connections.selectLibraries(
        source.id,
        all: false,
        selected: ['movies'],
      );
      final before = await sources.source(source.id);
      server.itemsHandler = (r) async {
        await sources.database.customStatement(
          "UPDATE sources SET kind='emby' WHERE id=?",
          [source.id],
        );
        r.response.write(
          jsonEncode({
            'Items': server.catalog['movies'],
            'TotalRecordCount': 2,
          }),
        );
        await r.response.close();
      };
      await expectLater(sync(), throwsA(isA<SourceFailure>()));
      expect(await sources.indexedSource(source.id), hasLength(5));
      expect((await sources.source(source.id)).lastScan, before.lastScan);
    },
  );
  test('source location rejects provider confusion, missing Plex adapter and malformed Plex session', () async {
    await expectLater(
      sources.add(
        kind: MediaSourceKind.jellyfin,
        name: 'bad',
        location: 'emby://host/one',
      ),
      throwsA(isA<SourceFailure>()),
    );
    await expectLater(
      connections.connect(
        server.address,
        'tester',
        'password',
        kind: MediaSourceKind.plex,
      ),
      throwsA(isA<SourceFailure>()),
    );
    expect(
      () => EmbySession.fromJson({
        'server': server.address,
        'username': 'tester',
        'userId': 'u',
        'token': 'secret',
        'kind': 'plex',
      }),
      throwsA(isA<SourceFailure>()),
    );
  });
}
