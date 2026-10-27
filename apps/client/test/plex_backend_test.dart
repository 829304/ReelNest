import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:xml/xml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_playback.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/api/plex/plex_client.dart';
import 'package:reelnest/api/plex/plex_item.dart';
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

import 'support/fake_video_engine.dart';
import 'support/plex_fixture.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlexFixture server;
  late PlexClient client;
  late EmbyClient emby;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late MediaSource source;
  final stores = <String, _Store>{};
  setUp(() async {
    stores.clear();
    server = PlexFixture();
    await server.start();
    client = PlexClient(
      accountEndpoint: server.accountEndpoint,
      deviceId: 'plex-device',
      http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _Http()),
    );
    emby = EmbyClient(deviceId: 'emby-device');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(emby),
      plexClient: Future.value(client),
      stores: (id) => stores.putIfAbsent(id, _Store.new),
    );
    source = await connections.connectPlex(server.serverUri, server.token);
  });
  tearDown(() async {
    connections.dispose();
    client.close();
    emby.close();
    await sources.close();
    await server.close();
  });
  MediaIdentity identity(String id) => (sourceId: source.id, localId: id);
  Future<void> sync() async {
    await EmbySyncRepository(
      sources: sources,
      connections: connections,
    ).synchronize(source.id);
  }

  test(
    'Plex identity, protected authentication, proxy and token-free SQL',
    () async {
      expect(source.kind, MediaSourceKind.plex);
      final authenticated = await connections.session(source.id);
      expect(authenticated.userId, 'plex-account:100');
      expect(authenticated.userId, isNot(authenticated.serverIdentity));
      expect(source.name, 'Plex 媒体库');
      expect(Uri.parse(source.location).scheme, 'plex');
      expect(MediaSourceKind.plex.isEmbyCompatible, isFalse);
      expect(MediaSourceKind.plex.isRemoteVideoSource, isTrue);
      expect(
        (await connections.session(source.id)).serverIdentity,
        'plex-machine',
      );
      final views = await connections.libraries(source.id);
      expect(views.map((v) => v.id), ['section:1', 'section:2']);
      expect(views.map((v) => v.collectionType), ['movies', 'tvshows']);
      final rows = await sources.database
          .customSelect('SELECT key,value FROM player_preferences')
          .get();
      expect(rows.single.read<String>('key'), 'connector.plex.${source.id}');
      expect(rows.toString(), isNot(contains(server.token)));
      final secure = jsonDecode(stores[source.id]!.value!) as Map;
      expect(secure['session']['kind'], 'plex');
      expect(secure['session']['token'], server.token);
      expect(
        server.requests.every(
          (r) =>
              r.headers['x-plex-token'] == server.token &&
              r.headers['x-plex-client-identifier'] == 'plex-device',
        ),
        isTrue,
      );
      expect(
        server.requests.every(
          (r) =>
              r.headers['authorization'] == null &&
              r.headers['x-emby-authorization'] == null &&
              !r.uri.queryParameters.containsKey('api_key'),
        ),
        isTrue,
      );
    },
  );
  test('public identity alone cannot authenticate an invalid token', () async {
    await expectLater(
      connections.connectPlex(server.serverUri, 'invalid-token'),
      throwsA(
        isA<EmbyFailure>().having(
          (e) => e.kind,
          'kind',
          EmbyError.authentication,
        ),
      ),
    );
    expect(await sources.sources(), hasLength(1));
  });
  test(
    'credential restoration, expired token and explicit reauthentication',
    () async {
      final saved = EmbySession.fromJson(
        jsonDecode(stores[source.id]!.value!)['session']
            as Map<String, dynamic>,
      );
      expect(saved.kind, MediaSourceKind.plex);
      server.token = 'replacement-token';
      await expectLater(
        connections.session(source.id),
        throwsA(isA<EmbyFailure>()),
      );
      await connections.reauthenticatePlex(source.id, server.token);
      expect((await connections.session(source.id)).token, server.token);
      server.machineIdentifier = 'replacement-server';
      await expectLater(
        connections.session(source.id),
        throwsA(isA<EmbyFailure>()),
      );
      await expectLater(
        connections.reauthenticatePlex(source.id, server.token),
        throwsA(isA<EmbyFailure>()),
      );
    },
  );
  test('first browse displays movies without a complete sync', () async {
    final cursor = await EmbyBrowseRepository(
      sources,
      connections,
    ).open(source.id, libraryId: 'section:1', cancellation: ScanCancellation());
    final items = await cursor.next();
    expect(items.single.title, 'Plex 测试电影');
    expect(items.single.identity.localId, '101');
    expect(items.single.posterPath, startsWith('plex-artwork:'));
    expect(items.single.remote!.supportsQualitySelection, isFalse);
    expect(EmbyVideoQuality.options(items.single), isEmpty);
    expect((await sources.source(source.id)).lastScan, isNull);
  });
  test(
    'first series browse loads only its episodes with source-scoped IDs',
    () async {
      final browser = EmbyBrowseRepository(sources, connections);
      final cursor = await browser.open(
        source.id,
        libraryId: 'section:2',
        cancellation: ScanCancellation(),
      );
      expect((await cursor.next()).single.identity.localId, '201');
      expect(await sources.indexedChildren(identity('201')), isEmpty);
      await browser.loadEpisodes(identity('201'), ScanCancellation());
      expect(
        (await sources.indexedChildren(identity('201')))
            .map((i) => i.episodeNumber),
        [1, 2],
      );
      expect((await sources.source(source.id)).lastScan, isNull);
    },
  );
  test('complete sync, snapshot, home and selected scopes agree', () async {
    await sync();
    expect((await sources.source(source.id)).itemCount, 4);
    final snapshot = await EmbyLibraryRepository(sources).snapshot(source.id);
    expect(snapshot.entries, hasLength(4));
    expect(HomeRepository.accepts(snapshot.source), isTrue);
    expect(
      await HomeRepository(sources).recommendationCandidates(source.id),
      isNotEmpty,
    );
    await connections.selectLibraries(
      source.id,
      all: false,
      selected: ['section:1'],
    );
    await sync();
    expect(
      (await sources.indexedSource(source.id)).map((i) => i.identity.localId),
      ['101'],
    );
    await connections.selectLibraries(source.id, all: true, selected: []);
    expect((await sources.source(source.id)).lastScan, isNull);
  });
  test('logical TV pagination crosses show and episode boundary without duplicates', () async {
    final session = await connections.session(source.id);
    final values = <String>[];
    for (var start = 0; start < 3; start += 2) {
      final page = await client.itemPage(
        session,
        parentId: 'section:2',
        start: start,
        limit: 2,
      );
      expect(page.total, 3);
      values.addAll(page.items.map((i) => i.id));
    }
    expect(values, ['201', '202', '203']);
  });
  test('details, provider IDs, cast filtering, artwork and subtitles use Plex routes', () async {
    await sync();
    final movie = await sources.media(identity('101'));
    final detail = await connections.detail(movie);
    expect(detail.tmdbId, '123');
    expect(detail.imdbId, 'tt1234567');
    expect(detail.cast.single.key, 'actor:501');
    expect(detail.cast.single.imageId, startsWith('plex-artwork:'));
    final cursor = await EmbyBrowseRepository(sources, connections).open(
      source.id,
      personKey: detail.cast.single.key,
      cancellation: ScanCancellation(),
    );
    expect(
      (await cursor.next()).map((i) => i.identity.localId),
      contains('101'),
    );
    expect(await connections.artwork(source.id, movie.posterPath!), isNotEmpty);
    final tracks = await connections.subtitles(movie);
    expect(tracks.single.displayName, 'Plex 中文字幕');
    expect(
      utf8.decode(await connections.subtitle(movie, tracks.single)),
      contains('Plex 中文字幕'),
    );
    expect(
      (await sources.media(identity('101'))).remote!.toJson().toString(),
      isNot(contains('X-Plex-Token')),
    );
  });
  test(
    'Plex favorites stay local across complete sync in every trace mode',
    () async {
      await sync();
      for (final mode in RemoteTraceSyncMode.values) {
        await connections.selectLibraries(
          source.id,
          all: true,
          selected: [],
          trace: mode,
        );
        await connections.setFavorite(identity('101'), true);
        await sync();
        expect((await sources.media(identity('101'))).remote!.favorite, isTrue);
      }
      expect(
        server.requests.any(
          (r) => r.uri.path.toLowerCase().contains('favorite'),
        ),
        isFalse,
      );
    },
  );
  test('watched and unwatched call scrobble without Emby user flags', () async {
    await sync();
    expect(await connections.markPlayed([identity('101')], true), 0);
    expect(await connections.markPlayed([identity('101')], false), 0);
    expect(
      server.requests.any(
        (r) =>
            r.uri.path == '/plex/:/scrobble' &&
            r.uri.queryParameters['key'] == '101',
      ),
      isTrue,
    );
    expect(
      server.requests.any((r) => r.uri.path == '/plex/:/unscrobble'),
      isTrue,
    );
  });
  test('direct playback uses actual Part.key and live token, resume, progress and stop', () async {
    await sync();
    final engine = FakeVideoEngine();
    final player = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      emby: connections,
      createEngine: () => engine,
    );
    try {
      await player.open(identity('101'));
      expect(
        Uri.parse(engine.openedPath!).path,
        '/plex/library/parts/9001/1700000000/file.avi',
      );
      expect(
        Uri.parse(engine.openedPath!).queryParameters['X-Plex-Token'],
        server.token,
      );
      expect(engine.openedAt, const Duration(seconds: 6));
      await player.close();
      final reports = server.requests.where(
        (r) => r.uri.path == '/plex/:/progress',
      );
      expect(
        reports.map((r) => r.uri.queryParameters['state']),
        containsAll(['playing', 'stopped']),
      );
      expect(
        reports.every(
          (r) =>
              r.uri.queryParameters['identifier'] ==
              'com.plexapp.plugins.library',
        ),
        isTrue,
      );
    } finally {
      await player.close();
      player.dispose();
    }
  });
  test('disabled trace never uploads playback or watched state', () async {
    await sync();
    await connections.selectLibraries(
      source.id,
      all: true,
      selected: [],
      trace: RemoteTraceSyncMode.disabled,
    );
    final movie = await sources.media(identity('101'));
    await connections.reportPlayback(
      movie,
      playSessionId: 'test',
      phase: EmbyPlaybackPhase.progress,
      position: const Duration(seconds: 5),
      duration: const Duration(seconds: 24),
      paused: false,
    );
    await connections.markPlayed([identity('101')], true);
    expect(
      server.requests.any((r) => r.uri.path.startsWith('/plex/:/')),
      isFalse,
    );
  });
  test(
    'malformed/DTD XML and oversized bodies retain the previous index',
    () async {
      await sync();
      for (final content in [
        '<invalid/>',
        '<!DOCTYPE MediaContainer [<!ENTITY x "unsafe">]><MediaContainer size="0"/>',
        'x' * (4 * 1024 * 1024 + 1),
      ]) {
        server.itemsHandler = (r) async {
          r.response.write(content);
          await r.response.close();
        };
        await expectLater(sync(), throwsA(isA<SourceFailure>()));
        expect(await sources.indexedSource(source.id), hasLength(4));
      }
    },
  );
  test('cancellation interrupts a stalled Plex response body', () async {
    final reached = Completer<void>();
    server.itemsHandler = (r) async {
      r.response.write('<MediaContainer');
      await r.response.flush();
      reached.complete();
    };
    final cancellation = ScanCancellation();
    final pending = connections.browsePage(
      source.id,
      parentId: 'section:1',
      start: 0,
      cancellation: cancellation,
    );
    final expected = expectLater(pending, throwsA(isA<ScanCancelled>()));
    await reached.future;
    cancellation.cancel();
    await expected.timeout(const Duration(seconds: 1));
  });
  test(
    'cross-origin Part.key and redirects never receive the Plex token',
    () async {
      await sync();
      server.details['101'] = plexMovie(
        partKey: 'http://example.invalid/video',
      );
      await expectLater(
        connections.preparePlayback(await sources.media(identity('101'))),
        throwsA(isA<EmbyFailure>()),
      );
      server.itemsHandler = (r) async {
        r.response.statusCode = 302;
        r.response.headers.set('location', 'http://example.invalid/steal');
        await r.response.close();
      };
      await expectLater(
        connections.browsePage(source.id, parentId: 'section:1', start: 0),
        throwsA(isA<EmbyFailure>()),
      );
    },
  );
  test(
    'remove clears only the Plex credential and scoped configuration',
    () async {
      await connections.remove(source.id);
      expect(stores[source.id]!.value, isNull);
      expect(await sources.sources(), isEmpty);
      expect(
        await sources.database
            .customSelect('SELECT * FROM player_preferences')
            .get(),
        isEmpty,
      );
    },
  );

  test('missing totalSize never treats a page size as the complete index', () async {
    server.itemsHandler = (r) async {
      final section = r.uri.pathSegments[3];
      final type = {
        '1': 'movie',
        '2': 'show',
        '4': 'episode',
      }[r.uri.queryParameters['type']];
      final items = server.catalog[section]!
          .where((v) => v.contains('type="$type"'))
          .toList();
      final offset = int.parse(r.headers.value('X-Plex-Container-Start')!);
      final size = int.parse(r.headers.value('X-Plex-Container-Size')!);
      final page = items.skip(offset).take(size).toList();
      r.response.write(
        '<MediaContainer size="${page.length}" offset="$offset">${page.join()}</MediaContainer>',
      );
      await r.response.close();
    };
    await sync();
    expect((await sources.source(source.id)).itemCount, 4);
    expect(
      (await sources.indexedChildren(identity('201')))
          .map((e) => e.episodeNumber),
      [1, 2],
    );
  });
  test(
    'oversized pages shrink at the same offset and retain learned page size',
    () async {
      final small = PlexClient(
        accountEndpoint: server.accountEndpoint,
        deviceId: 'bounded',
        maxResponseBytes: 4096,
        http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _Http()),
      );
      addTearDown(small.close);
      final session = await small.authenticate(
        server.serverUri,
        '',
        server.token,
      );
      server.itemsHandler = (r) async {
        final size = int.parse(r.headers.value('X-Plex-Container-Size')!);
        final start = int.parse(r.headers.value('X-Plex-Container-Start')!);
        r.response.write(
          size > 1
              ? 'x' * 5000
              : PlexFixture.container(
                  plexMovie(id: '${101 + start}'),
                  total: 3,
                  offset: start,
                ),
        );
        await r.response.close();
      };
      expect(
        (await small.itemPage(session, parentId: 'section:1')).items.single.id,
        '101',
      );
      final before = server.requests.length;
      expect(
        (await small.itemPage(
          session,
          parentId: 'section:1',
          start: 1,
        )).items.single.id,
        '102',
      );
      expect(server.requests.length, before + 1);
    },
  );
  test(
    'Plex downloads retain the current token across same-origin redirects',
    () async {
      await sync();
      final folder = await Directory.systemTemp.createTemp(
        'reelnest-plex-test-',
      );
      addTearDown(() => folder.delete(recursive: true));
      server.streamHandler = (r) async {
        if (!r.uri.path.endsWith('/redirected.avi')) {
          r.response.statusCode = 307;
          r.response.headers.set(
            'location',
            '/plex/library/parts/9001/redirected.avi?X-Plex-Token=stale',
          );
        } else {
          r.response.contentLength = 5;
          r.response.add([1, 2, 3, 4, 5]);
        }
        await r.response.close();
      };
      final destination = File('${folder.path}/video.part');
      final result = await connections.downloadVideo(
        await sources.media(identity('101')),
        destination,
        ScanCancellation(),
      );
      expect(result.received, 5);
      expect(await destination.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(
        server.requests.last.uri.queryParameters['X-Plex-Token'],
        server.token,
      );
    },
  );
  test('external public artwork receives no Plex credentials', () async {
    final public = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => public.close(force: true));
    final headers = Completer<Map<String, String>>();
    public.listen((r) async {
      final values = <String, String>{};
      r.headers.forEach((key, value) => values[key] = value.join(','));
      headers.complete(values);
      r.response.add([1, 2, 3]);
      await r.response.close();
    });
    final session = await connections.session(source.id);
    final reference = plexArtworkReference(
      'http://127.0.0.1:${public.port}/actor.jpg?X-Plex-Token=stale',
      session.server,
    )!;
    expect(await client.artwork(session, reference), [1, 2, 3]);
    expect(await headers.future, isNot(contains('x-plex-token')));
    expect(await headers.future, isNot(contains('x-plex-client-identifier')));
  });
  test(
    'Plex personal rating seeds preferences without overwriting local edits',
    () async {
      server.catalog['1'] = [
        plexMovie().replaceFirst(
          'audienceRating="8.5"',
          'audienceRating="8.5" userRating="6"',
        ),
      ];
      await sync();
      var row = await sources.database
          .customSelect(
            "SELECT user_rating FROM media_library_preferences WHERE local_id = '101'",
          )
          .getSingle();
      expect(row.read<double>('user_rating'), 3);
      await sources.database.customStatement(
        "UPDATE media_library_preferences SET user_rating = 2 WHERE local_id = '101'",
      );
      await sync();
      row = await sources.database
          .customSelect(
            "SELECT user_rating FROM media_library_preferences WHERE local_id = '101'",
          )
          .getSingle();
      expect(row.read<double>('user_rating'), 2);
    },
  );
  test(
    'a replacement Plex server cannot publish over the original index',
    () async {
      await sync();
      final before = await sources.source(source.id);
      server.machineIdentifier = 'replacement-machine';
      await expectLater(sync(), throwsA(isA<EmbyFailure>()));
      expect((await sources.source(source.id)).lastScan, before.lastScan);
      expect(await sources.indexedSource(source.id), hasLength(4));
    },
  );
  test(
    'restricted tokens on the same Plex server keep separate library caches',
    () async {
      final original = await connections.session(source.id);
      server.override = (r) async {
        r.response.write(
          r.uri.path.endsWith('/account')
              ? jsonEncode({'id': 200, 'username': 'Other account'})
              : r.uri.path.endsWith('/identity')
              ? '<MediaContainer machineIdentifier="plex-machine"/>'
              : '<MediaContainer size="1"><Directory key="2" title="Restricted TV" type="show"/></MediaContainer>',
        );
        await r.response.close();
      };
      final other = await client.authenticate(
        server.serverUri,
        '',
        'other-account-token',
      );
      expect(other.serverIdentity, original.serverIdentity);
      expect(other.userId, isNot(original.userId));
      server.override = null;
      final page = await client.itemPage(original, parentId: 'section:1');
      expect(page.items.single.id, '101');
    },
  );
  test(
    'original Plex mixed-case provider IDs and child precedence are retained',
    () {
      final node = XmlDocument.parse(
        '<Video guid="IMDB://ttlegacy?source=plex"><Guid id="TmDb://Collection/ABC?foo=bar"/><Guid id="ImDb://ttChild"/></Video>',
      ).rootElement;
      expect(plexProviderId(node, 'tmdb'), 'Collection/ABC');
      expect(plexProviderId(node, 'imdb'), 'ttChild');
      final legacy = XmlDocument.parse(
        '<Video guid="IMDB://tt1234567?source=plex"><Guid id="local://abc"/></Video>',
      ).rootElement;
      expect(plexProviderId(legacy, 'imdb'), 'tt1234567');
      expect(plexProviderId(legacy, 'tmdb'), isNull);
    },
  );
  test('cross-account reauthentication cannot inherit a source index or offline cache', () async {
    await sync();
    await sources.database.customStatement(
      'INSERT INTO video_disk_cache(source_id, local_id, bundle, root, filename, bytes, quality_id, quality_label, created_at, accessed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        source.id,
        '101',
        'owned-bundle',
        'fixture-root',
        'video.avi',
        1024,
        'original',
        '原画',
        1,
        1,
      ],
    );
    final oldCredential = stores[source.id]!.value;
    final oldSource = await sources.source(source.id);
    server.token = 'restricted-user-token';
    server.accountId = '200';
    await expectLater(
      connections.reauthenticatePlex(source.id, server.token),
      throwsA(isA<EmbyFailure>()),
    );
    expect(stores[source.id]!.value, oldCredential);
    expect((await sources.source(source.id)).lastScan, oldSource.lastScan);
    expect(await sources.indexedSource(source.id), hasLength(4));
    final caches = await sources.database
        .customSelect('SELECT source_id FROM video_disk_cache')
        .get();
    expect(caches.single.read<String>('source_id'), source.id);
    final separate = await connections.connectPlex(
      server.serverUri,
      server.token,
    );
    expect(separate.id, isNot(source.id));
    expect(await sources.indexedSource(separate.id), isEmpty);
    expect(
      (await sources.database
              .customSelect('SELECT source_id FROM video_disk_cache')
              .get())
          .single
          .read<String>('source_id'),
      source.id,
    );
  });
  test(
    'verified same-account token rotation preserves source ownership and index',
    () async {
      await sync();
      final previous = await sources.source(source.id);
      final identityBefore = (await connections.session(source.id)).userId;
      server.token = 'rotated-token';
      server.accountName = 'Renamed display name';
      server.accountBody = jsonEncode({
        'id': 100,
        'username': server.accountName,
        'email': 'private-profile@example.invalid',
        'authToken': 'response-secret-not-for-storage',
      });
      await connections.reauthenticatePlex(source.id, server.token);
      final restored = await connections.session(source.id);
      expect(restored.userId, identityBefore);
      expect(restored.userId, 'plex-account:100');
      expect(restored.token, server.token);
      expect((await sources.source(source.id)).lastScan, previous.lastScan);
      expect(await sources.indexedSource(source.id), hasLength(4));
      final rows = await sources.database
          .customSelect('SELECT value FROM player_preferences')
          .get();
      expect(rows.toString(), isNot(contains(server.token)));
      expect(rows.toString(), isNot(contains(server.accountName)));
      expect(
        stores[source.id]!.value,
        isNot(contains('private-profile@example.invalid')),
      );
      expect(
        stores[source.id]!.value,
        isNot(contains('response-secret-not-for-storage')),
      );
    },
  );
  test(
    'unverifiable official account responses never replace saved credentials',
    () async {
      final before = stores[source.id]!.value;
      for (final body in [
        '{}',
        '{"id":0}',
        '<html>not an account</html>',
        'x' * (256 * 1024 + 1),
      ]) {
        server.accountBody = body;
        await expectLater(
          connections.reauthenticatePlex(source.id, server.token),
          throwsA(isA<EmbyFailure>()),
        );
        expect(stores[source.id]!.value, before);
      }
      server.accountStatus = 503;
      await expectLater(
        connections.reauthenticatePlex(source.id, server.token),
        throwsA(isA<EmbyFailure>()),
      );
      expect(stores[source.id]!.value, before);
    },
  );
  test(
    'server-only token fallback stays credential-bound across reauthentication',
    () async {
      server.accountStatus = 401;
      final scoped = await connections.connectPlex(
        server.serverUri,
        server.token,
      );
      final session = await connections.session(scoped.id);
      expect(session.userId, PlexClient.credentialIdentity(server.token));
      expect(session.userId, isNot(session.serverIdentity));
      final before = stores[scoped.id]!.value;
      server.token = 'other-server-token';
      await expectLater(
        connections.reauthenticatePlex(scoped.id, server.token),
        throwsA(isA<EmbyFailure>()),
      );
      expect(stores[scoped.id]!.value, before);
    },
  );
  test('official account redirects cannot forward credentials or change the source', () async {
    final before = stores[source.id]!.value;
    server.accountHandler = (r) async {
      r.response.statusCode = 302;
      r.response.headers.set('location', '/plex/steal-account-token');
      await r.response.close();
    };
    await expectLater(
      connections.reauthenticatePlex(source.id, server.token),
      throwsA(isA<EmbyFailure>()),
    );
    expect(
      server.requests.any((r) => r.uri.path.endsWith('/steal-account-token')),
      isFalse,
    );
    expect(stores[source.id]!.value, before);
  });
  test('account lookup cancellation interrupts the HTTP body', () async {
    final reached = Completer<void>();
    server.accountHandler = (r) async {
      r.response.write('{');
      await r.response.flush();
      reached.complete();
    };
    final cancellation = ScanCancellation();
    final pending = client.authenticate(
      server.serverUri,
      '',
      server.token,
      cancellation: cancellation,
    );
    final expected = expectLater(pending, throwsA(isA<ScanCancelled>()));
    await reached.future;
    cancellation.cancel();
    await expected.timeout(const Duration(seconds: 1));
  });
}
