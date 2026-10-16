import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_download.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/playback_marker_repository.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/playback/domain/video_subtitle_settings.dart';
import 'package:reelnest/player/video_timeline.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EmbyServerFixture server;
  late EmbyClient client;
  late HttpClient http;
  late SourceRepository sources;
  late EmbyConnectionRepository connections;
  late EmbyCacheRepository cache;
  late Directory directory;
  late MediaSource source;
  late IndexedMedia film;
  final stores = <String, _Store>{};
  final video = List<int>.generate(32768, (i) => i % 251);
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  Map<String, dynamic> movie(
    String id, {
    int height = 2160,
    int bitrate = 40000000,
  }) => {
    'Id': id,
    'Name': id,
    'Type': 'Movie',
    'RunTimeTicks': 1000000000,
    'ImageTags': {'Primary': 'tag'},
    'MediaSources': [
      {
        'Id': 'media-$id',
        'Container': 'mp4',
        'Size': 500000000,
        'MediaStreams': [
          {
            'Type': 'Video',
            'Width': height * 16 ~/ 9,
            'Height': height,
            'BitRate': bitrate,
          },
        ],
      },
    ],
  };
  Future<void> waitFor(
    bool Function() condition, [
    String Function()? describe,
  ]) async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) {
        fail('asynchronous event timed out ${describe?.call() ?? ''}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<VideoCacheTask> download([IndexedMedia? item]) async {
    final selected = item ?? film;
    await cache.enqueue(selected, EmbyVideoQuality.source);
    final task = cache.tasks.value[selected.identity]!;
    await waitFor(
      () => [
        VideoCacheTaskState.complete,
        VideoCacheTaskState.failed,
        VideoCacheTaskState.cancelled,
      ].contains(task.state),
    );
    await task.work;
    return task;
  }

  Future<File> cachedFile() async {
    final entry = (await cache.entries()).single;
    return File(
      p.join(
        (await cache.videoRoot()).path,
        'objects',
        entry.bundle,
        entry.filename,
      ),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reelnest-cache-test-');
    stores.clear();
    server = EmbyServerFixture();
    await server.start();
    http = HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http());
    client = EmbyClient(deviceId: 'quality-device', http: http);
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
      'fixture-only',
    );
    server.catalog['movies'] = [movie('film')];
    await EmbySyncRepository(
      sources: sources,
      connections: connections,
    ).synchronize(source.id);
    film = await sources.media((sourceId: source.id, localId: 'film'));
    cache = EmbyCacheRepository(
      sources: sources,
      connections: connections,
      cacheDirectory: () async => directory,
    );
    server.streamHandler = (r) async {
      r.response.headers.contentType = ContentType('video', 'mp4');
      r.response.contentLength = video.length;
      r.response.headers.set('etag', '"video-v1"');
      r.response.add(video);
      await r.response.close();
    };
  });
  tearDown(() async {
    await cache.dispose();
    connections.dispose();
    client.close();
    await sources.close();
    await server.close();
    await directory.delete(recursive: true);
  });

  test('quality planner derives useful tiers, preserves proxy and absolute transcode start', () async {
    final options = EmbyVideoQuality.options(film);
    expect(options.map((q) => q.height), [2160, 2160, 1440, 1080]);
    expect(options.map((q) => q.label), ['原画', '蓝光 4K', '超清 2K', '高清 1080P']);
    expect(
      options
          .skip(1)
          .every((q) => q.width!.isEven && q.bitrate! < 40000000 * .88),
      isTrue,
    );
    final resource = await connections.preparePlayback(
      film,
      quality: options.last,
      start: const Duration(milliseconds: 20250),
      playSessionId: 'quality-session',
    );
    expect(resource.uri.path, '/proxy/emby/Videos/film/stream.mp4');
    expect(
      resource.uri.queryParameters,
      containsPair('StartTimeTicks', '202500000'),
    );
    expect(resource.uri.queryParameters, containsPair('Static', 'false'));
    expect(
      resource.uri.queryParameters,
      containsPair('PlaySessionId', 'quality-session'),
    );
    expect(resource.uri.queryParameters, containsPair('VideoCodec', 'h264'));
    expect(resource.uri.queryParameters, containsPair('MaxHeight', '1080'));
    expect(
      resource.uri.queryParameters['MaxStreamingBitrate'],
      '${options.last.bitrate! + 192000}',
    );
    final direct = await connections.preparePlayback(
      film,
      start: const Duration(seconds: 20),
    );
    expect(direct.uri.queryParameters.containsKey('StartTimeTicks'), isFalse);
    expect(direct.uri.queryParameters['Static'], 'true');
    for (final input in [
      movie('film', height: 720),
      movie('film', height: 1080, bitrate: 5900000),
    ]) {
      server.catalog['movies'] = [input];
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(source.id);
      expect(
        EmbyVideoQuality.options(await sources.media(film.identity)),
        isEmpty,
      );
    }
  });

  test('quality switch retains pause, volume/rate, absolute progress and failed switch keeps old decoder', () async {
    final engines = <FakeVideoEngine>[];
    var failOpen = false;
    final player = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      emby: connections,
      createEngine: () {
        final engine = FakeVideoEngine()..failOpen = failOpen;
        engines.add(engine);
        return engine;
      },
    );
    try {
      await player.open(film.identity);
      engines.last.emit(position: const Duration(seconds: 20));
      await player.toggle();
      await player.volume(63);
      await player.rate(1.5);
      const subtitleStyle = VideoSubtitleStyle(
        bold: true,
        colorPreset: VideoSubtitleColorPreset.cyan,
      );
      await player.setSubtitleStyle(subtitleStyle);
      await player.audioDelay(.2);
      await player.subtitleDelay(-.3);
      await player.subtitleScale(1.25);
      await player.subtitlePosition(84);
      final option = player.qualityOptions.last;
      await player.selectQuality(option);
      expect(player.error, isNull);
      expect(player.clock.playing, isFalse);
      expect(engines.last.openedAt, Duration.zero);
      expect(player.clock.position, const Duration(seconds: 20));
      expect(player.clock.volume, 63);
      expect(player.clock.rate, 1.5);
      expect(engines.last.subtitleStyle, subtitleStyle);
      expect(
        engines.last.timing,
        const VideoTimingSettings(
          audioDelay: .2,
          subtitleDelay: -.3,
          subtitleScale: 1.25,
          subtitlePosition: 84,
        ),
      );
      engines.last.emit(networkBytesPerSecond: 1048576);
      expect(player.clock.networkBytesPerSecond, 1048576);
      expect(player.timeline.value.networkBytesPerSecond, 1048576);
      expect(
        Uri.parse(engines.last.openedPath!).queryParameters['StartTimeTicks'],
        '200000000',
      );
      engines.last.emit(position: const Duration(seconds: 3));
      expect(player.clock.position, const Duration(seconds: 23));
      await player.seek(const Duration(seconds: 5));
      expect(
        Uri.parse(engines.last.openedPath!).queryParameters['StartTimeTicks'],
        '50000000',
      );
      expect(player.clock.position, const Duration(seconds: 5));
      expect(player.clock.networkBytesPerSecond, isNull);
      expect(engines.last.subtitleStyle, subtitleStyle);
      expect(engines.last.timing.subtitleDelay, -.3);
      final old = player.engine;
      failOpen = true;
      await player.selectQuality(player.qualityOptions.first);
      expect(player.engine, same(old));
      expect(player.quality.id, option.id);
      expect(player.transitionMessage, isNotNull);
      await player.save();
      expect(
        (await PlaybackRepository(sources.database).read(film.identity))
            .position,
        const Duration(seconds: 5),
      );
    } finally {
      await player.close();
      player.dispose();
    }
  });

  for (final automatic in [false, true]) {
    test(
      'transcoded marker skip uses absolute ranges and preserves pause (automatic=$automatic)',
      () async {
        final engines = <FakeVideoEngine>[];
        final player = PlaybackSession(
          sources: sources,
          records: PlaybackRepository(sources.database),
          emby: connections,
          createEngine: () {
            final engine = FakeVideoEngine();
            engines.add(engine);
            return engine;
          },
        );
        try {
          await player.open(film.identity);
          engines.last.emit(position: const Duration(seconds: 20));
          await player.toggle();
          await player.setMarkerBoundary(
            PlaybackMarkerKind.intro,
            isStart: true,
            at: const Duration(seconds: 22),
          );
          await player.setMarkerBoundary(
            PlaybackMarkerKind.intro,
            isStart: false,
            at: const Duration(seconds: 30),
          );
          await player.selectQuality(player.qualityOptions.last);
          final transcoded = engines.last;
          expect(
            Uri.parse(transcoded.openedPath!).queryParameters['StartTimeTicks'],
            '200000000',
          );
          expect(player.clock.playing, isFalse);
          await player.setMarkerSkipBehavior(
            automatic
                ? VideoMarkerSkipBehavior.automatic
                : VideoMarkerSkipBehavior.prompt,
          );
          transcoded.emit(position: const Duration(seconds: 3));
          if (automatic) {
            await waitFor(
              () => player.clock.position == const Duration(seconds: 30),
            );
          } else {
            expect(
              player.precision.value.activeSkipMarker!.start,
              const Duration(seconds: 22),
            );
            await player.skipPlaybackMarker(
              player.precision.value.activeSkipMarker!.id,
            );
          }
          expect(transcoded.clock.position, const Duration(seconds: 10));
          expect(player.clock.position, const Duration(seconds: 30));
          expect(player.clock.playing, isFalse);
          expect(player.precision.value.activeSkipMarker, isNull);
          await player.save();
          expect(
            (await PlaybackRepository(sources.database).read(film.identity))
                .position,
            const Duration(seconds: 30),
          );
          await player.selectQuality(player.qualityOptions[1]);
          expect(
            player.precision.value.markers
                .where((m) => m.kind == PlaybackMarkerKind.intro)
                .single
                .end,
            const Duration(seconds: 30),
          );
          expect(
            player.precision.value.skipBehavior,
            automatic
                ? VideoMarkerSkipBehavior.automatic
                : VideoMarkerSkipBehavior.prompt,
          );
          expect(player.clock.position, const Duration(seconds: 30));
        } finally {
          await player.close();
          player.dispose();
        }
      },
    );
  }

  for (final wholeFilm in [false, true]) {
    test(
      'transcoded loop prepares a full timeline and preserves pause (whole=$wholeFilm)',
      () async {
        final engines = <FakeVideoEngine>[];
        final player = PlaybackSession(
          sources: sources,
          records: PlaybackRepository(sources.database),
          emby: connections,
          createEngine: () {
            final engine = FakeVideoEngine();
            engines.add(engine);
            return engine;
          },
        );
        try {
          await player.open(film.identity);
          engines.last.emit(position: const Duration(seconds: 20));
          await player.toggle();
          await player.volume(63);
          await player.rate(1.5);
          await player.selectQuality(player.qualityOptions.last);
          expect(
            Uri.parse(engines.last.openedPath!)
                .queryParameters['StartTimeTicks'],
            '200000000',
          );
          if (wholeFilm) {
            await player.setLoopCurrentItem(true);
          } else {
            await player.cycleABLoop();
          }
          expect(
            Uri.parse(engines.last.openedPath!)
                    .queryParameters['StartTimeTicks'] ??
                '0',
            '0',
          );
          expect(engines.last.openedAt, const Duration(seconds: 20));
          expect(player.clock.position, const Duration(seconds: 20));
          expect(player.clock.playing, isFalse);
          expect(player.clock.volume, 63);
          expect(player.clock.rate, 1.5);
          if (wholeFilm) {
            expect(engines.last.loopCurrentItem, isTrue);
          } else {
            expect(engines.last.abStart, const Duration(seconds: 20));
            await player.seek(const Duration(seconds: 30));
            await player.cycleABLoop();
            expect(engines.last.abEnd, const Duration(seconds: 30));
            await player.selectQuality(player.qualityOptions[1]);
            expect(
              Uri.parse(engines.last.openedPath!)
                      .queryParameters['StartTimeTicks'] ??
                  '0',
              '0',
            );
            expect(engines.last.abStart, const Duration(seconds: 20));
            expect(engines.last.abEnd, const Duration(seconds: 30));
            await player.clearABLoop();
            expect(engines.last.abStart, isNull);
            expect(engines.last.abEnd, isNull);
          }
        } finally {
          await player.close();
          player.dispose();
        }
      },
    );
  }

  test('failed full-timeline preparation preserves old transcoded playback and loops remain off', () async {
    var failOpen = false;
    final player = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      emby: connections,
      createEngine: () => FakeVideoEngine()..failOpen = failOpen,
    );
    try {
      await player.open(film.identity);
      (player.engine as FakeVideoEngine).emit(
        position: const Duration(seconds: 20),
      );
      await player.selectQuality(player.qualityOptions.last);
      final previous = player.engine;
      failOpen = true;
      await player.setLoopCurrentItem(true);
      expect(player.engine, same(previous));
      expect(player.error, isNull);
      expect(player.controlError, isNotNull);
      expect(player.clock.playing, isTrue);
      expect(player.precision.value.loop.loopCurrentItem, isFalse);
    } finally {
      await player.close();
      player.dispose();
    }
  });

  test(
    'transcoded suffix chapter snapshot cannot erase a full chapter list',
    () async {
      final engines = <FakeVideoEngine>[];
      final player = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        emby: connections,
        createEngine: () {
          final engine = FakeVideoEngine()
            ..chapterList = engines.isEmpty
                ? const [
                    VideoChapter(
                      index: 0,
                      title: 'Beginning',
                      time: Duration.zero,
                    ),
                    VideoChapter(
                      index: 1,
                      title: 'Later',
                      time: Duration(seconds: 40),
                    ),
                  ]
                : const [
                    VideoChapter(
                      index: 0,
                      title: 'Partial',
                      time: Duration(seconds: 20),
                    ),
                  ];
          engines.add(engine);
          return engine;
        },
      );
      try {
        await player.open(film.identity);
        engines.last.emit(position: const Duration(seconds: 20));
        await player.selectQuality(player.qualityOptions.last);
        expect(player.precision.value.chapters.map((m) => m.title), [
          'Beginning',
          'Later',
        ]);
        await player.addBookmark(at: const Duration(seconds: 25));
        final saved = await PlaybackMarkerRepository(sources.database)
            .read(film.identity);
        expect(
          saved
              .where((m) => m.kind == PlaybackMarkerKind.chapter)
              .map((m) => m.title),
          ['Beginning', 'Later'],
        );
        expect(
          saved
              .where((m) => m.kind == PlaybackMarkerKind.bookmark)
              .single
              .start,
          const Duration(seconds: 25),
        );
      } finally {
        await player.close();
        player.dispose();
      }
    },
  );

  test(
    'persistent artwork is reused without network and isolated by source',
    () async {
      expect(await cache.artwork(source.id, 'film'), png);
      final requests = server.requests
          .where((r) => r.uri.path.contains('/Images/'))
          .length;
      final second = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async => directory,
      );
      try {
        server.artworkHandler = (r) async {
          r.response.statusCode = 500;
          await r.response.close();
        };
        expect(await second.artwork(source.id, 'film'), png);
        expect(
          server.requests.where((r) => r.uri.path.contains('/Images/')).length,
          requests,
        );
        final other = await connections.connect(
          server.address,
          'tester',
          'fixture-only',
        );
        await expectLater(
          second.artwork(other.id, 'film'),
          throwsA(isA<SourceFailure>()),
        );
        final manifest =
            (await sources.database
                    .customSelect('SELECT * FROM artwork_disk_cache')
                    .get())
                .toString();
        expect(manifest, isNot(contains('api_key')));
        expect(manifest, isNot(contains('token-')));
      } finally {
        await second.dispose();
      }
    },
  );

  for (final detailImage in [false, true]) {
    test(
      'artwork revision refreshes ${detailImage ? 'detail' : 'library'} provider and persists across restart',
      () async {
        final container = ProviderContainer(
          overrides: [embyCacheProvider.overrideWithValue(cache)],
        );
        addTearDown(container.dispose);
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawPaint(ui.Paint()..color = const ui.Color(0xffff0000));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1, 1);
        final changed = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
        Future<List<int>> read(int revision) async => detailImage
            ? container.read(
                embyDetailImageProvider((
                  sourceId: source.id,
                  itemId: 'film',
                  backdrop: false,
                  index: 0,
                  width: 700,
                  revision: revision,
                )).future,
              )
            : container.read(
                embyArtworkProvider((
                  sourceId: source.id,
                  itemId: 'film',
                  backdrop: false,
                  revision: revision,
                )).future,
              );
        expect(await read(1), png);
        server.artworkHandler = (r) async {
          r.response.headers.contentType = ContentType('image', 'png');
          r.response.add(changed);
          await r.response.close();
        };
        // Evicting the Riverpod instance alone must still reuse this generation.
        if (detailImage) {
          container.invalidate(embyDetailImageProvider);
        } else {
          container.invalidate(embyArtworkProvider);
        }
        expect(await read(1), png);
        expect(await read(2), changed);
        expect(
          server.requests.where((r) => r.uri.path.contains('/Images/')),
          hasLength(2),
        );
        final restarted = EmbyCacheRepository(
          sources: sources,
          connections: connections,
          cacheDirectory: () async => directory,
        );
        try {
          server.artworkHandler = (r) async {
            r.response.statusCode = 500;
            await r.response.close();
          };
          expect(
            await restarted.artwork(source.id, 'film', revision: 2),
            changed,
          );
          expect(
            server.requests.where((r) => r.uri.path.contains('/Images/')),
            hasLength(2),
          );
        } finally {
          await restarted.dispose();
        }
      },
    );
  }

  test('resync prewarms the same new artwork generation consumed by the library', () async {
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        embyConnectionProvider.overrideWithValue(connections),
        embyCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    final before = (await sources.source(source.id))
        .lastScan!
        .millisecondsSinceEpoch;
    await cache.prewarm([film], revision: before);
    final imagesBefore = server.requests
        .where((r) => r.uri.path.contains('/Images/'))
        .length;
    await container.read(embySyncProvider).synchronize(source.id);
    final after = (await sources.source(source.id))
        .lastScan!
        .millisecondsSinceEpoch;
    expect(after, greaterThan(before));
    // Coalesce with the unawaited prewarm and then check the stored generation.
    await container.read(
      embyArtworkProvider((
        sourceId: source.id,
        itemId: film.posterPath!,
        backdrop: false,
        revision: after,
      )).future,
    );
    final rows = await sources.database
        .customSelect('SELECT cache_key FROM artwork_disk_cache')
        .get();
    expect(
      rows.map((r) => (jsonDecode(r.read<String>('cache_key')) as List).last),
      contains(after),
    );
    expect(
      server.requests.where((r) => r.uri.path.contains('/Images/')).length,
      imagesBefore + 1,
    );
  });

  test(
    'detail artwork overtakes queued posters and promotes duplicate requests',
    () async {
      final blocked = Completer<void>(), release = Completer<void>();
      final detailArrived = Completer<void>();
      final releaseDetail = Completer<void>();
      final order = <String>[];
      server.artworkHandler = (r) async {
        final id = r.uri.pathSegments[r.uri.pathSegments.indexOf('Images') - 1];
        order.add(id);
        if (order.length <= 4) {
          if (order.length == 4) blocked.complete();
          await release.future;
        }
        if (id == 'actor') {
          detailArrived.complete();
          await releaseDetail.future;
        }
        r.response.headers.contentType = ContentType('image', 'png');
        r.response.add(png);
        await r.response.close();
      };
      final running = [
        for (var i = 0; i < 4; i++) cache.artwork(source.id, 'active$i'),
      ];
      final pending = <Future<dynamic>>[];
      try {
        await blocked.future.timeout(const Duration(seconds: 3));
        pending.addAll([
          for (var i = 0; i < 8; i++) cache.artwork(source.id, 'poster$i'),
        ]);
        pending.add(cache.artwork(source.id, 'actor'));
        // Allow the disk probes to enqueue, then promote the coalesced request.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        pending.add(
          cache.artwork(source.id, 'actor', priority: ArtworkPriority.detail),
        );
        release.complete();
        await detailArrived.future.timeout(const Duration(seconds: 3));
        expect(order[4], 'actor');
        expect(order.where((id) => id == 'actor'), hasLength(1));
      } finally {
        if (!release.isCompleted) release.complete();
        releaseDetail.complete();
        await Future.wait([...running, ...pending]);
      }
    },
  );

  test('one prewarm worker leaves room for visible detail images', () async {
    final started = Completer<void>(), release = Completer<void>();
    server.artworkHandler = (r) async {
      if (r.uri.path.contains('/warm')) {
        if (!started.isCompleted) started.complete();
        await release.future;
      }
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add(png);
      await r.response.close();
    };
    final warming = cache.prewarm([
      for (var i = 0; i < 8; i++)
        IndexedMedia(
          identity: (sourceId: source.id, localId: 'warm$i'),
          title: 'Warm $i',
          type: film.type,
          bytes: film.bytes,
          modified: film.modified,
          posterPath: 'warm$i',
        ),
    ]);
    try {
      await started.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await cache
            .artwork(source.id, 'actor', priority: ArtworkPriority.detail)
            .timeout(const Duration(seconds: 1)),
        png,
      );
      expect(release.isCompleted, isFalse);
    } finally {
      release.complete();
      await warming;
    }
  });

  test('artwork coalesces duplicates, bounds concurrency to four and does not queue playback behind image bytes', () async {
    var active = 0, peak = 0;
    final started = Completer<void>(), release = Completer<void>();
    server.artworkHandler = (r) async {
      active++;
      if (active > peak) peak = active;
      if (active == 4 && !started.isCompleted) started.complete();
      await release.future;
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add(png);
      await r.response.close();
      active--;
    };
    final work = Future.wait([
      for (var i = 0; i < 8; i++) cache.artwork(source.id, '$i'),
      cache.artwork(source.id, '0'),
    ]);
    await started.future.timeout(const Duration(seconds: 4));
    expect(peak, 4);
    // Session validation can finish while all four image responses are held.
    await connections.preparePlayback(film).timeout(const Duration(seconds: 1));
    release.complete();
    await work;
    expect(
      server.requests.where((r) => r.uri.path.contains('/Images/')).length,
      8,
    );
    expect(peak, lessThanOrEqualTo(4));
  });

  test(
    'artwork enforces disk budget and retries corrupt disk copies',
    () async {
      await cache.dispose();
      cache = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async => directory,
        maxImageFiles: 1,
        maxImageBytes: png.length * 2,
      );
      await cache.artwork(source.id, 'one');
      await cache.artwork(source.id, 'two');
      final rows = await sources.database
          .customSelect('SELECT * FROM artwork_disk_cache')
          .get();
      expect(rows, hasLength(1));
      final root = await cache.imageRoot();
      await File(p.join(root.path, rows.single.read<String>('filename')))
          .writeAsString('not an image');
      expect(await cache.artwork(source.id, 'two'), png);
      expect(await root.list().length, 1);
    },
  );

  test('acquiring one cached video does not inspect unrelated cache paths', () async {
    server.catalog['movies'] = [movie('film'), movie('second')];
    await EmbySyncRepository(
      sources: sources,
      connections: connections,
    ).synchronize(source.id);
    await download();
    await sources.database.customStatement(
      '''
      INSERT INTO video_disk_cache
      SELECT source_id,'second','invalid-bundle',root,filename,bytes,
        quality_id,quality_label,created_at,accessed_at
      FROM video_disk_cache WHERE source_id=? AND local_id='film'
    ''',
      [source.id],
    );
    final acquired = await cache.acquire(film.identity);
    expect(acquired, isNotNull);
    try {
      expect(await File(acquired!.path).readAsBytes(), video);
      expect(
        (await cache.entries(identity: film.identity)).single.identity,
        film.identity,
      );
      // Invalid metadata is still rejected when that entry is actually chosen.
      await expectLater(
        cache.acquire((sourceId: source.id, localId: 'second')),
        throwsA(isA<SourceFailure>()),
      );
      expect(
        await cache.acquire((sourceId: source.id, localId: 'missing')),
        isNull,
      );
    } finally {
      if (acquired != null) await cache.release(acquired.lease);
    }
  });

  test('download commits full video and cached playback works without contacting Emby', () async {
    expect((await download()).state, VideoCacheTaskState.complete);
    expect(await (await cachedFile()).readAsBytes(), video);
    final engine = FakeVideoEngine();
    final player = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      emby: connections,
      cache: cache,
      createEngine: () => engine,
    );
    final requestCount = server.requests.length;
    try {
      await player.open(film.identity);
      await player.refreshTracks();
      expect(player.error, isNull);
      expect(player.filePath, isNotNull);
      expect(engine.openedPath, (await cachedFile()).path);
      expect(player.qualityOptions, isEmpty);
      expect(server.requests.length, requestCount);
      await cache.maintenance(clear: true);
      expect(await cache.entries(), hasLength(1));
      await expectLater(
        cache.maintenance(remove: film.identity),
        throwsA(isA<SourceFailure>()),
      );
    } finally {
      await player.close();
      player.dispose();
    }
    await cache.maintenance(clear: true);
    expect(await cache.entries(), isEmpty);
  });

  for (final brokenCustomDirectory in [false, true]) {
    test(
      'unavailable ${brokenCustomDirectory ? 'custom' : 'default'} cache directory falls back online without deleting cached records',
      () async {
        if (brokenCustomDirectory) {
          await cache.setDirectory(p.join(directory.path, 'external'));
        }
        expect((await download()).state, VideoCacheTaskState.complete);
        final originalFile = await cachedFile();
        await cache.dispose();
        if (brokenCustomDirectory) {
          // A path formerly backed by the cache disk can no longer be a directory.
          final external = Directory(p.join(directory.path, 'external'));
          await external.rename(p.join(directory.path, 'detached'));
          await File(external.path).writeAsString('unavailable volume');
        }
        var disconnected = true;
        cache = EmbyCacheRepository(
          sources: sources,
          connections: connections,
          cacheDirectory: () async {
            if (disconnected && !brokenCustomDirectory) {
              throw const FileSystemException('cache disk unavailable');
            }
            return directory;
          },
        );
        final engine = FakeVideoEngine();
        final player = PlaybackSession(
          sources: sources,
          records: PlaybackRepository(sources.database),
          emby: connections,
          cache: cache,
          createEngine: () => engine,
        );
        try {
          await player.open(film.identity);
          expect(player.error, isNull);
          expect(player.clock.playing, isTrue);
          expect(player.filePath, isNull);
          expect(Uri.parse(engine.openedPath!).host, '127.0.0.1');
          expect(player.cacheWarning, contains('缓存读取失败'));
          // Other successful controls must not clear this independent warning.
          await player.volume(60);
          expect(player.cacheWarning, isNotNull);
          expect(
            await sources.database
                .customSelect('SELECT * FROM video_disk_cache')
                .get(),
            hasLength(1),
          );
          expect(
            await sources.database
                .customSelect('SELECT * FROM video_cache_leases')
                .get(),
            isEmpty,
          );
        } finally {
          await player.close();
          player.dispose();
        }
        disconnected = false;
        if (brokenCustomDirectory) {
          final path = p.join(directory.path, 'external');
          await File(path).delete();
          await Directory(p.join(directory.path, 'detached')).rename(path);
        }
        expect((await cache.entries()).single.identity, film.identity);
        expect(await originalFile.readAsBytes(), video);
      },
    );
  }

  test(
    'cache lookup fallback still reports a genuine online decoder failure',
    () async {
      expect((await download()).state, VideoCacheTaskState.complete);
      await cache.dispose();
      cache = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async =>
            throw const FileSystemException('unavailable'),
      );
      final engine = FakeVideoEngine()..failOpen = true;
      final player = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        emby: connections,
        cache: cache,
        createEngine: () => engine,
      );
      try {
        await player.open(film.identity);
        expect(player.error, isNotNull);
        expect(player.engine, isNull);
        expect(Uri.parse(engine.openedPath!).host, '127.0.0.1');
      } finally {
        await player.close();
        player.dispose();
      }
    },
  );

  test(
    'D2: concurrent cleanup during subtitle/save stage cannot remove new video',
    () async {
      final ready = Completer<void>(), release = Completer<void>();
      await cache.dispose();
      cache = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async => directory,
        beforePublish: () async {
          ready.complete();
          await release.future;
        },
      );
      await cache.enqueue(film, EmbyVideoQuality.source);
      await ready.future.timeout(const Duration(seconds: 4));
      final root = await cache.videoRoot();
      final task = cache.tasks.value[film.identity]!;
      final staged = File(
        p.join(root.path, '.staging', task.token, 'video.mp4'),
      );
      final cleaner = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async => directory,
      );
      try {
        await cleaner.maintenance(clear: true);
        expect(await staged.exists(), isTrue);
        release.complete();
        await task.work;
        expect(task.state, VideoCacheTaskState.complete);
        expect(await (await cachedFile()).readAsBytes(), video);
      } finally {
        if (!release.isCompleted) release.complete();
        await cleaner.dispose();
      }
    },
  );

  test('D3: failed redownload keeps previous bundle and bytes', () async {
    await download();
    final old = await cachedFile();
    server.streamHandler = (r) async {
      r.response.statusCode = 500;
      await r.response.close();
    };
    expect((await download()).state, VideoCacheTaskState.failed);
    expect((await cachedFile()).path, old.path);
    expect(await old.readAsBytes(), video);
  });

  test('D3: SQL failure after rename rolls back manifest and removes new orphan only', () async {
    await download();
    final old = await cachedFile();
    await sources.database.customStatement(
      "CREATE TRIGGER reject_cache BEFORE UPDATE ON video_disk_cache BEGIN SELECT RAISE(ABORT,'fixture'); END",
    );
    expect((await download()).state, VideoCacheTaskState.failed);
    expect((await cachedFile()).path, old.path);
    expect(await old.readAsBytes(), video);
    expect(await Directory(p.dirname(p.dirname(old.path))).list().length, 1);
  });

  test('pause/resume uses ETag range and cancellation of redownload preserves previous cache', () async {
    await download();
    final old = await cachedFile();
    final started = Completer<void>(), release = Completer<void>();
    server.streamHandler = (r) async {
      r.response.headers.contentType = ContentType('video', 'mp4');
      r.response.headers.set('etag', '"video-v1"');
      final range = r.headers.value('range');
      if (range == null) {
        r.response.bufferOutput = false;
        r.response.contentLength = video.length;
        r.response.add(video.take(4096).toList());
        await r.response.flush();
        if (!started.isCompleted) started.complete();
        await release.future;
        try {
          r.response.add(video.skip(4096).toList());
          await r.response.close();
        } catch (_) {}
      } else {
        final offset = int.parse(range.substring(6, range.length - 1));
        expect(r.headers.value('if-range'), '"video-v1"');
        r.response.statusCode = 206;
        r.response.headers.set(
          'content-range',
          'bytes $offset-${video.length - 1}/${video.length}',
        );
        r.response.contentLength = video.length - offset;
        r.response.add(video.skip(offset).toList());
        await r.response.close();
      }
    };
    await cache.enqueue(film, EmbyVideoQuality.source);
    final task = cache.tasks.value[film.identity]!;
    await started.future;
    await waitFor(
      () => task.received >= 4096,
      () =>
          'bytes=${task.received}, expected=${task.expected}, state=${task.state}, error=${task.error}',
    );
    cache.pause(task);
    await task.work;
    expect(task.state, VideoCacheTaskState.paused);
    expect(await old.exists(), isTrue);
    release.complete();
    await cache.resume(task);
    await waitFor(
      () =>
          task.state == VideoCacheTaskState.complete ||
          task.state == VideoCacheTaskState.failed,
      () =>
          'resume state=${task.state}, bytes=${task.received}, error=${task.error}',
    );
    await task.work;
    expect(task.state, VideoCacheTaskState.complete);
    expect(await (await cachedFile()).readAsBytes(), video);
    expect(
      server.requests.where((r) => r.uri.path.contains('/Videos/')),
      hasLength(3),
    );
  });

  test(
    'size cap evicts watched older video first and includes subtitle bytes',
    () async {
      server.catalog['movies'] = [movie('film'), movie('second')];
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(source.id);
      final second = await sources.media((
        sourceId: source.id,
        localId: 'second',
      ));
      await download();
      await download(second);
      await PlaybackRepository(sources.database).save(
        film.identity,
        position: const Duration(seconds: 95),
        duration: const Duration(seconds: 100),
        playedAt: DateTime.utc(2025),
        autoMarkWatched: false,
      );
      await cache.setLimit(video.length * 1.5 / (1024 * 1024 * 1024));
      expect((await cache.entries()).single.identity, second.identity);
    },
  );

  test('custom cache root keeps files scoped and missing copies are removed from manifest', () async {
    await download();
    final old = await cachedFile();
    final other = Directory(p.join(directory.path, 'other'));
    await cache.setDirectory(other.path);
    expect(await cache.entries(), isEmpty);
    expect(await old.exists(), isTrue);
    await cache.setDirectory(null);
    expect(await cache.entries(), hasLength(1));
    await old.delete();
    await cache.maintenance();
    expect(
      await sources.database
          .customSelect('SELECT * FROM video_disk_cache')
          .get(),
      isEmpty,
    );
  });

  test('stream resumes only matching ETag/range; a full 200 restarts rather than appends', () async {
    final file = File(p.join(directory.path, 'partial'));
    await file.writeAsBytes(video.take(100).toList());
    final uri = (await connections.preparePlayback(film)).uri;
    final result = await streamEmbyDownload(
      http,
      uri,
      file,
      ScanCancellation(),
      etag: '"old"',
    );
    expect(result.received, video.length);
    expect(await file.readAsBytes(), video);
    await file.writeAsBytes(video.take(100).toList());
    server.streamHandler = (r) async {
      r.response.statusCode = 206;
      r.response.headers.contentType = ContentType('video', 'mp4');
      r.response.headers.set('etag', '"wrong"');
      r.response.headers.set(
        'content-range',
        'bytes 100-${video.length - 1}/${video.length}',
      );
      r.response.contentLength = video.length - 100;
      r.response.add(video.skip(100).toList());
      await r.response.close();
    };
    await expectLater(
      streamEmbyDownload(http, uri, file, ScanCancellation(), etag: '"old"'),
      throwsA(isA<SourceFailure>()),
    );
    expect(await file.length(), 100);
  });

  test(
    'stream rejects cross-origin redirects before sending credentials',
    () async {
      var hits = 0;
      final hostile = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      hostile.listen((r) {
        hits++;
        r.response.close();
      });
      try {
        server.streamHandler = (r) async {
          r.response.statusCode = 302;
          r.response.headers.set(
            'location',
            'http://127.0.0.1:${hostile.port}/video',
          );
          await r.response.close();
        };
        final task = await download();
        expect(task.state, VideoCacheTaskState.failed);
        expect(hits, 0);
        expect(await cache.entries(), isEmpty);
      } finally {
        await hostile.close(force: true);
      }
    },
  );

  test(
    'D3: cancelled redownload removes only its stage and keeps old video',
    () async {
      await download();
      final old = await cachedFile();
      final started = Completer<void>(), release = Completer<void>();
      server.streamHandler = (r) async {
        r.response.bufferOutput = false;
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.contentLength = video.length;
        r.response.add(video.take(4096).toList());
        await r.response.flush();
        started.complete();
        await release.future;
        try {
          await r.response.close();
        } catch (_) {}
      };
      try {
        await cache.enqueue(film, EmbyVideoQuality.source);
        final task = cache.tasks.value[film.identity]!;
        await started.future;
        await cache.cancel(task).timeout(const Duration(seconds: 2));
        expect(task.state, VideoCacheTaskState.cancelled);
        expect((await cachedFile()).path, old.path);
        expect(await old.readAsBytes(), video);
        expect(
          await Directory(p.join((await cache.videoRoot()).path, '.staging'))
              .list()
              .length,
          0,
        );
      } finally {
        release.complete();
      }
    },
  );

  test('subtitle sidecars are saved, counted and remain available when a redownload fails', () async {
    final subtitle = '1\n00:00:01,000 --> 00:00:04,000\n缓存字幕\n';
    server.detailHandler = (r) async {
      r.response.write(
        jsonEncode({
          'MediaSources': [
            {
              'Id': 'media-film',
              'MediaStreams': [
                {
                  'Type': 'Subtitle',
                  'Index': 2,
                  'Codec': 'srt',
                  'Language': 'zho',
                },
                {
                  'Type': 'Subtitle',
                  'Index': 3,
                  'Codec': 'vtt',
                  'Language': 'eng',
                },
              ],
            },
          ],
        }),
      );
      await r.response.close();
    };
    final serveVideo = server.streamHandler!;
    server.streamHandler = (r) async {
      if (!r.uri.path.contains('/Subtitles/')) return serveVideo(r);
      if (r.uri.path.contains('/3/')) {
        r.response.statusCode = 500;
      } else {
        r.response.headers.contentType = ContentType.text;
        r.response.write(subtitle);
      }
      await r.response.close();
    };
    final task = await download();
    expect(task.state, VideoCacheTaskState.complete);
    expect(task.error, contains('部分字幕'));
    final file = await cachedFile();
    final sidecar = File(p.join(file.parent.path, 'video.zho.2.srt'));
    expect(await sidecar.readAsString(), subtitle);
    expect(
      (await cache.summary()).bytes,
      video.length + utf8.encode(subtitle).length,
    );
    server.streamHandler = (r) async {
      r.response.statusCode = 403;
      await r.response.close();
    };
    await download();
    expect(await sidecar.readAsString(), subtitle);
  });

  test('D2: abandoned staging is recognizable and removed after its protection expires', () async {
    final root = await cache.videoRoot();
    final token = newEmbyIdentity();
    final stale = Directory(p.join(root.path, '.staging', token));
    await stale.create(recursive: true);
    await File(p.join(stale.path, 'video.mp4')).writeAsBytes([1, 2, 3]);
    await sources.database.customStatement(
      'INSERT INTO video_cache_staging VALUES(?,?,?)',
      [token, root.path, DateTime.utc(2020).millisecondsSinceEpoch],
    );
    final unknown = File(p.join(root.path, 'my-original-video.mp4'));
    await unknown.writeAsBytes([4, 5]);
    await cache.maintenance(clear: true);
    expect(await stale.exists(), isFalse);
    expect(await unknown.exists(), isTrue);
    expect(
      await sources.database
          .customSelect('SELECT * FROM video_cache_staging')
          .get(),
      isEmpty,
    );
  });

  test('artwork invalid bytes and oversized chunked body never reach disk and retries back off', () async {
    server.artworkHandler = (r) async {
      r.response.headers.contentType = ContentType('image', 'png');
      r.response.add([1, 2, 3]);
      await r.response.close();
    };
    await expectLater(cache.artwork(source.id, 'invalid'), throwsA(anything));
    final count = server.requests.length;
    await expectLater(
      cache.artwork(source.id, 'invalid'),
      throwsA(isA<SourceFailure>()),
    );
    expect(server.requests.length, count);
    expect(
      await sources.database
          .customSelect('SELECT * FROM artwork_disk_cache')
          .get(),
      isEmpty,
    );
    // A small configured protocol budget exercises incremental rejection;
    // actual production artwork budget is 24 MiB, without allocating it here.
    final tiny = EmbyClient(
      deviceId: 'bounded',
      http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
      maxArtworkBytes: 32,
    );
    final release = Completer<void>();
    var completeBody = false;
    try {
      server.artworkHandler = (r) async {
        r.response.bufferOutput = false;
        r.response.headers.contentType = ContentType('image', 'png');
        try {
          r.response.add(List.filled(64, 0));
          await r.response.flush();
          await release.future;
          completeBody = true;
          r.response.add(List.filled(1024, 0));
          await r.response.close();
        } catch (_) {
          /* The client already rejected the oversized prefix. */
        }
      };
      await expectLater(
        tiny.artwork(await connections.session(source.id), 'large'),
        throwsA(isA<EmbyFailure>()),
      );
      expect(completeBody, isFalse);
    } finally {
      release.complete();
      tiny.close();
    }
  });

  test('stream validates declared length, chunked completion and finished partial 416', () async {
    final uri = (await connections.preparePlayback(film)).uri;
    final file = File(p.join(directory.path, 'partial'));
    server.streamHandler = (r) async {
      r.response.headers.contentType = ContentType('video', 'mp4');
      r.response.add(video.take(1000).toList());
      await r.response.flush();
      r.response.add(video.skip(1000).toList());
      await r.response.close();
    };
    expect(
      (await streamEmbyDownload(http, uri, file, ScanCancellation())).received,
      video.length,
    );
    server.streamHandler = (r) async {
      r.response.statusCode = 416;
      r.response.headers.set('etag', '"complete"');
      r.response.headers.set('content-range', 'bytes */${video.length}');
      await r.response.close();
    };
    expect(
      (await streamEmbyDownload(
        http,
        uri,
        file,
        ScanCancellation(),
        etag: '"complete"',
      )).received,
      video.length,
    );
    expect(await file.readAsBytes(), video);
  });
}
