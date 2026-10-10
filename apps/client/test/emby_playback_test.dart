import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelnest/features/playback/application/playback_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_playback.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_queue.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
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

class _Records extends PlaybackRepository {
  _Records(super.database);
  bool fail = false;
  @override
  Future<void> save(
    MediaIdentity id, {
    required Duration position,
    required Duration duration,
    DateTime? playedAt,
    bool autoMarkWatched = true,
    double watchedThreshold = .9,
  }) {
    if (fail) throw StateError('fixture SQL failure');
    return super.save(
      id,
      position: position,
      duration: duration,
      playedAt: playedAt,
      autoMarkWatched: autoMarkWatched,
      watchedThreshold: watchedThreshold,
    );
  }
}

void main() {
  late EmbyServerFixture server;
  late EmbyClient client;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbySyncRepository sync;
  late MediaSource source;
  late PlaybackSession player;
  late _Records records;
  final engines = <FakeVideoEngine>[];
  final stores = <String, _Store>{};
  bool failNextOpen = false;
  Map<String, dynamic> movie(String id) => {
    'Id': id,
    'Name': id,
    'Type': 'Movie',
    'RunTimeTicks': 1000000000,
    'MediaSources': [
      {'Id': 'media-$id', 'Container': ' MKV '},
    ],
    'UserData': {
      'PlaybackPositionTicks': 300000000,
      'Played': false,
      'LastPlayedDate': '2026-10-08T12:00:00Z',
    },
  };
  MediaIdentity id(String item) => (sourceId: source.id, localId: item);
  List<Map<String, dynamic>> reports([String? suffix]) => server.requests
      .where(
        (r) =>
            r.uri.path.contains('/Sessions/Playing') &&
            (suffix == null || r.uri.path.endsWith(suffix)),
      )
      .map((r) => jsonDecode(r.body) as Map<String, dynamic>)
      .toList();
  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Expected asynchronous event');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    engines.clear();
    stores.clear();
    failNextOpen = false;
    server = EmbyServerFixture();
    await server.start();
    client = EmbyClient(
      deviceId: 'playback-device',
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
    source = await connections.connect(
      server.address,
      'tester',
      'fixture-password',
    );
    server.catalog['movies'] = [movie('film')];
    sync = EmbySyncRepository(sources: sources, connections: connections);
    await sync.synchronize(source.id);
    records = _Records(sources.database);
    player = PlaybackSession(
      sources: sources,
      records: records,
      emby: connections,
      createEngine: () {
        final engine = FakeVideoEngine()..failOpen = failNextOpen;
        engines.add(engine);
        return engine;
      },
    );
  });
  tearDown(() async {
    records.fail = false;
    await player.close();
    player.dispose();
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
  });

  test('prepares fresh proxy stream, refreshes expired auth, keeps URL out of SQLite', () async {
    server.validToken = 'expired';
    await player.open(id('film'));
    expect(player.error, isNull);
    expect(server.loginCount, 2);
    final uri = Uri.parse(engines.single.openedPath!);
    expect(uri.path, '/proxy/emby/Videos/film/stream.mkv');
    expect(uri.queryParameters, {
      'Static': 'true',
      'DeviceId': 'playback-device',
      'api_key': 'token-2',
      'MediaSourceId': 'media-film',
    });
    expect(engines.single.openedAt, const Duration(seconds: 25));
    expect(player.filePath, isNull);
    expect(player.sidecarSubtitles, isEmpty);
    final rows = await sources.database
        .customSelect('SELECT value FROM remote_media_metadata')
        .get();
    expect(rows.single.read<String>('value'), isNot(contains('token-')));
    expect(rows.single.read<String>('value'), isNot(contains('http://')));
  });

  test(
    'stream path encodes opaque IDs and does not accept a path as extension',
    () {
      final resource = client.playbackResource(
        EmbySession(
          server: Uri.parse(server.address),
          username: 'tester',
          userId: 'user-1',
          token: 'secret',
        ),
        const RemoteMediaMetadata(
          externalId: 'a/b 空格',
          container: '../../else',
        ),
        audio: true,
      );
      expect(resource.uri.pathSegments, contains('a/b 空格'));
      expect(resource.uri.pathSegments.last, 'stream');
      expect(resource.toString(), isNot(contains('secret')));
    },
  );

  test(
    '204 start/pause/seek/stop reports ordered, one play session, exact ticks',
    () async {
      await player.open(id('film'));
      await waitFor(() => reports().length == 1);
      await player.toggle();
      await waitFor(() => reports().length == 2);
      await player.seek(const Duration(seconds: 40));
      await waitFor(() => reports().length == 3);
      await player.close();
      final events = reports();
      expect(events, hasLength(4));
      expect(events.map((e) => e['PlaySessionId']).toSet(), hasLength(1));
      expect(
        events.every(
          (e) =>
              e['ItemId'] == 'film' &&
              e['MediaSourceId'] == 'media-film' &&
              e['PlayMethod'] == 'DirectStream',
        ),
        isTrue,
      );
      expect(events[0]['PositionTicks'], 250000000);
      expect(events[1]['IsPaused'], isTrue);
      expect(events[2]['PositionTicks'], 400000000);
      expect(events.last['PositionTicks'], 400000000);
      expect(events.last['RunTimeTicks'], 1000000000);
      expect(player.syncError, isNull);
      expect(
        (await records.read(id('film'))).position,
        const Duration(seconds: 40),
      );
    },
  );

  test('clock observations are throttled and completed close reports full duration once', () async {
    await player.setEndAction(VideoEndAction.holdLastFrame);
    await player.open(id('film'));
    await waitFor(() => reports().isNotEmpty);
    for (var i = 30; i < 90; i++) {
      engines.single.emit(position: Duration(seconds: i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(reports(), hasLength(1));
    engines.single.emit(position: const Duration(seconds: 99), completed: true);
    await player.close();
    await player.close();
    expect(reports('Stopped'), hasLength(1));
    expect(reports('Stopped').single['PositionTicks'], 1000000000);
    expect((await records.read(id('film'))).watched, isTrue);
  });

  test('upload failure is nonfatal, progress remains local, 403 does not reauthenticate', () async {
    server.playbackHandler = (request) async {
      request.response.statusCode = 403;
      await request.response.close();
    };
    await player.open(id('film'));
    await waitFor(() => player.syncError != null);
    expect(player.error, isNull);
    expect(server.loginCount, 1);
    engines.single.emit(position: const Duration(seconds: 55));
    await player.close();
    expect(
      (await records.read(id('film'))).position,
      const Duration(seconds: 55),
    );
    expect(engines.single.disposals, 1);
  });

  test(
    'report 401 retries once with refreshed credential and same playSessionId',
    () async {
      await player.open(id('film'));
      await waitFor(() => reports().length == 1);
      server.validToken = 'expired';
      await player.close();
      expect(server.loginCount, 2);
      expect(reports('Stopped'), hasLength(2));
      expect(
        reports('Stopped').map((r) => r['PlaySessionId']).toSet(),
        hasLength(1),
      );
      expect(player.syncError, isNull);
    },
  );

  for (final mode in RemoteTraceSyncMode.values) {
    test(
      'trace mode ${mode.name} controls import and outbound events',
      () async {
        await records.save(
          id('film'),
          position: const Duration(seconds: 60),
          duration: const Duration(seconds: 100),
        );
        await connections.selectLibraries(
          source.id,
          all: true,
          selected: [],
          trace: mode,
        );
        server.catalog['movies'] = [
          {
            ...movie('film'),
            'UserData': {'PlaybackPositionTicks': 200000000, 'Played': false},
          },
        ];
        await sync.synchronize(source.id);
        expect(
          (await records.read(id('film'))).position,
          Duration(seconds: mode == RemoteTraceSyncMode.disabled ? 60 : 20),
        );
        await player.open(id('film'));
        await player.close();
        expect(reports().isEmpty, mode != RemoteTraceSyncMode.bidirectional);
      },
    );
  }

  test('failed switch preserves old decoder and sends no stop/start for failed target', () async {
    server.catalog['movies']!.add(movie('second'));
    await sync.synchronize(source.id);
    await player.open(id('film'));
    await waitFor(() => reports().length == 1);
    failNextOpen = true;
    await player.open(id('second'));
    expect(player.item!.identity, id('film'));
    expect(player.transitionMessage, isNotNull);
    expect(engines.first.disposals, 0);
    expect(engines.last.disposals, 1);
    expect(reports('Stopped'), isEmpty);
    expect(reports().any((r) => r['ItemId'] == 'second'), isFalse);
  });

  test(
    'failed local save keeps remote session open until successful close retry',
    () async {
      await player.open(id('film'));
      await waitFor(() => reports().length == 1);
      records.fail = true;
      await player.close();
      expect(player.saveError, isNotNull);
      expect(engines.single.disposals, 0);
      expect(reports('Stopped'), isEmpty);
      records.fail = false;
      await player.close();
      expect(reports('Stopped'), hasLength(1));
      expect(engines.single.disposals, 1);
    },
  );

  test('episode EOF advances source scoped queue and stops each session exactly once', () async {
    server.catalog['shows'] = [
      for (var n = 1; n <= 2; n++)
        {
          ...movie('ep$n'),
          'Type': 'Episode',
          'SeriesId': 'series',
          'SeriesName': 'Show',
          'ParentIndexNumber': 1,
          'IndexNumber': n,
        },
    ];
    await sync.synchronize(source.id);
    await player.open(id('ep1'));
    engines.single.emit(
      position: const Duration(seconds: 100),
      completed: true,
    );
    await waitFor(() => player.item?.identity == id('ep2') && !player.loading);
    await player.close();
    expect(reports('Stopped').map((e) => e['ItemId']), ['ep1', 'ep2']);
    expect(reports().map((e) => e['PlaySessionId']).toSet(), hasLength(2));
  });
  test('server sync refreshes a mounted playback record provider', () async {
    final container = ProviderContainer(
      overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
    );
    final subscription = container.listen(
      playbackRecordProvider(id('film')),
      (_, _) {},
    );
    try {
      expect(
        (await container.read(playbackRecordProvider(id('film')).future))
            .position
            .inSeconds,
        30,
      );
      server.catalog['movies'] = [
        {
          ...movie('film'),
          'UserData': {'PlaybackPositionTicks': 200000000},
        },
      ];
      await sync.synchronize(source.id);
      await waitFor(
        () =>
            container
                .read(playbackRecordProvider(id('film')))
                .asData
                ?.value
                .position
                .inSeconds ==
            20,
      );
    } finally {
      subscription.close();
      container.dispose();
    }
  });

  test('unresponsive reporting aborts within budget and cannot prevent local close', () async {
    final release = Completer<void>();
    server.playbackHandler = (request) async {
      await release.future;
      try {
        await request.response.close();
      } on HttpException {
        /* client cancelled */
      }
    };
    final bounded = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores[id]!,
      playbackReportTimeout: const Duration(milliseconds: 50),
    );
    final session = PlaybackSession(
      sources: sources,
      records: records,
      emby: bounded,
      createEngine: FakeVideoEngine.new,
    );
    try {
      await session.open(id('film'));
      await waitFor(() => session.syncError != null);
      final elapsed = Stopwatch()..start();
      await session.close();
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
      expect((await records.read(id('film'))).position.inSeconds, 25);
    } finally {
      release.complete();
      await session.close(discardProgress: true);
      session.dispose();
      bounded.dispose();
    }
  });
  test('slow progress upload retains the latest forced seek without accumulating ticks', () async {
    final release = Completer<void>();
    var progressCount = 0;
    server.playbackHandler = (request) async {
      if (request.uri.path.endsWith('/Progress') && ++progressCount == 1) {
        await release.future;
      }
      request.response.statusCode = 204;
      await request.response.close();
    };
    try {
      await player.open(id('film'));
      await waitFor(() => reports().length == 1);
      await player.toggle();
      await waitFor(() => reports('Progress').length == 1);
      await player.seek(const Duration(seconds: 40));
      await player.seek(const Duration(seconds: 45));
      engines.single.emit(position: const Duration(seconds: 46));
      release.complete();
      await waitFor(() => reports('Progress').length == 2);
      expect(reports('Progress').map((r) => r['PositionTicks']), [
        250000000,
        450000000,
      ]);
      await player.close();
      expect(reports('Stopped').single['PositionTicks'], 460000000);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });
  test('candidate stays paused through old stop upload and until its surface is attached', () async {
    server.catalog['movies']!.add(movie('second'));
    await sync.synchronize(source.id);
    await player.open(id('film'));
    await waitFor(() => reports().length == 1);
    await player.changeOptions(
      (o) =>
          o.copyWith(useLaunchVolume: true, launchVolume: 37, defaultRate: 1.5),
    );
    final stopEntered = Completer<void>(), releaseStop = Completer<void>();
    final surfaceEntered = Completer<void>(),
        releaseSurface = Completer<void>();
    server.playbackHandler = (request) async {
      if (request.uri.path.endsWith('/Stopped') && !stopEntered.isCompleted) {
        stopEntered.complete();
        await releaseStop.future;
      }
      request.response.statusCode = 204;
      await request.response.close();
    };
    player.waitForSurface = () async {
      surfaceEntered.complete();
      await releaseSurface.future;
    };
    final switching = player.open(id('second'));
    try {
      await stopEntered.future.timeout(const Duration(seconds: 2));
      expect(player.item!.identity, id('film'));
      expect(engines.last, isNot(same(player.engine)));
      expect(engines.last.clock.playing, isFalse);
      expect(engines.last.clock.position, const Duration(seconds: 25));
      releaseStop.complete();
      await surfaceEntered.future.timeout(const Duration(seconds: 2));
      expect(player.engine, same(engines.last));
      expect(player.item!.identity, id('second'));
      expect(engines.last.clock.playing, isFalse);
      expect(engines.last.clock.volume, 37);
      expect(engines.last.clock.rate, 1.5);
      expect(reports().any((r) => r['ItemId'] == 'second'), isFalse);
      releaseSurface.complete();
      await switching;
      expect(player.clock.playing, isTrue);
      expect(player.clock.position, const Duration(seconds: 25));
      await waitFor(() => reports().any((r) => r['ItemId'] == 'second'));
    } finally {
      if (!releaseStop.isCompleted) releaseStop.complete();
      if (!releaseSurface.isCompleted) releaseSurface.complete();
      await switching;
      player.waitForSurface = null;
    }
  });

  for (final predecessorFails in [false, true]) {
    test(
      'queued report times out before predecessor ends, never sends later (failed=$predecessorFails)',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        server.artworkHandler = (request) async {
          entered.complete();
          await release.future;
          request.response.statusCode = predecessorFails ? 500 : 200;
          request.response.add([1, 2, 3]);
          await request.response.close();
        };
        final bounded = EmbyConnectionRepository(
          sources: sources,
          client: Future.value(client),
          stores: (id) => stores[id]!,
          playbackReportTimeout: const Duration(milliseconds: 50),
        );
        final preceding = bounded
            .artwork(source.id, 'film')
            .then<Object?>((_) => null, onError: (Object e) => e);
        try {
          await entered.future;
          final elapsed = Stopwatch()..start();
          await expectLater(
            bounded
                .reportPlayback(
                  await sources.media(id('film')),
                  playSessionId: 'expired-queued-report',
                  phase: EmbyPlaybackPhase.stopped,
                  position: const Duration(seconds: 40),
                  duration: const Duration(seconds: 100),
                  paused: true,
                )
                .timeout(const Duration(seconds: 1)),
            throwsA(isA<EmbyFailure>()),
          );
          expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
          expect(release.isCompleted, isFalse);
          expect(reports(), isEmpty);
        } finally {
          release.complete();
          final failure = await preceding;
          expect(failure != null, predecessorFails);
          // A subsequent operation drains the queued tombstone without sleeping.
          await bounded.session(source.id);
          expect(reports(), isEmpty);
          bounded.dispose();
        }
      },
    );
  }

  test('close releases decoder within report budget while source predecessor is still blocked', () async {
    final bounded = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (id) => stores[id]!,
      playbackReportTimeout: const Duration(milliseconds: 50),
    );
    final decoder = FakeVideoEngine();
    final session = PlaybackSession(
      sources: sources,
      records: records,
      emby: bounded,
      createEngine: () => decoder,
    );
    final entered = Completer<void>(), release = Completer<void>();
    Future<Object?>? preceding;
    try {
      await session.open(id('film'));
      await waitFor(() => reports().isNotEmpty);
      server.artworkHandler = (request) async {
        entered.complete();
        await release.future;
        await request.response.close();
      };
      preceding = bounded
          .artwork(source.id, 'film')
          .then<Object?>((_) => null, onError: (Object e) => e);
      await entered.future;
      final elapsed = Stopwatch()..start();
      await session.close().timeout(const Duration(seconds: 1));
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 1)));
      expect(release.isCompleted, isFalse);
      expect(decoder.disposals, 1);
      expect((await records.read(id('film'))).position.inSeconds, 25);
    } finally {
      release.complete();
      await preceding;
      await session.close(discardProgress: true);
      await bounded.session(source.id);
      expect(reports('Stopped'), isEmpty);
      session.dispose();
      bounded.dispose();
    }
  });
}
