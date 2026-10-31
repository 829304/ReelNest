import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/application/external_playback_service.dart';
import 'package:reelnest/features/playback/data/external_player_settings_repository.dart';
import 'package:reelnest/features/playback/domain/external_player_settings.dart';
import 'package:reelnest/platform/external_player_gateway.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/data/url_video_repository.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/player/video_load_monitor.dart';

import 'support/fake_video_engine.dart';
import 'support/track_video_fixture.dart';

class _Http extends HttpOverrides {}

class _Gateway implements ExternalPlayerGateway {
  String? opened;
  @override
  Future<void> launch(String location, {String? applicationPath}) async {
    opened = location;
  }

  @override
  Future<void> validateApplication(String path) async {}
  @override
  Future<List<ExternalPlayerApplication>> availablePlayers({
    String? customPath,
  }) async => [];
}

void main() {
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  TestWidgetsFlutterBinding.ensureInitialized();
  late SourceRepository sources;
  late UrlVideoRepository urls;
  late EmbyCacheRepository cache;
  late EmbyConnectionRepository connections;
  late EmbyClient client;
  late Directory root;
  late HttpServer server;
  HttpOverrides? previousHttp;
  late Future<void> Function(HttpRequest) handler;
  Future<void> Function()? beforePublish;
  final video = List<int>.generate(32768, (i) => i % 251);
  String address([String path = '/film.mp4?signature=a%2Fb&x=2&x=1']) =>
      'http://127.0.0.1:${server.port}$path';

  Future<void> respond(HttpRequest r, List<int> bytes) async {
    r.response.headers.contentType = ContentType('video', 'mp4');
    r.response.headers.set('etag', '"version-1"');
    r.response.contentLength = bytes.length;
    r.response.add(bytes);
    await r.response.close();
  }

  Future<void> waitFor(
    bool Function() condition, [
    String Function()? describe,
  ]) async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!condition()) {
      if (DateTime.now().isAfter(end)) {
        fail('URL cache task timed out ${describe?.call() ?? ''}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<IndexedMedia> item([String? url]) async {
    await urls.add(url ?? address());
    return sources.media((await urls.list()).first.identity);
  }

  Future<VideoCacheTask> download(IndexedMedia media) async {
    await cache.enqueue(media, EmbyVideoQuality.source);
    final task = cache.tasks.value[media.identity]!;
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

  Future<List<int>> bytes(MediaIdentity id) async {
    final lease = (await cache.acquire(id))!;
    try {
      return await File(lease.path).readAsBytes();
    } finally {
      await cache.release(lease.lease);
    }
  }

  setUp(() async {
    previousHttp = HttpOverrides.current;
    HttpOverrides.global = _Http();
    root = await Directory.systemTemp.createTemp('reelnest-url-cache-');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    urls = UrlVideoRepository(sources);
    client = EmbyClient(deviceId: 'url-cache-test');
    connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (_) => throw StateError('URL must not authenticate'),
    );
    beforePublish = null;
    cache = EmbyCacheRepository(
      sources: sources,
      connections: connections,
      cacheDirectory: () async => root,
      beforePublish: () async {
        await beforePublish?.call();
      },
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handler = (r) => respond(r, video);
    server.listen((r) async {
      try {
        await handler(r);
      } catch (_) {
        r.response.close().catchError((_) {});
      }
    });
  });
  tearDown(() async {
    await cache.dispose();
    connections.dispose();
    client.close();
    await server.close(force: true);
    await sources.close();
    await root.delete(recursive: true);
    HttpOverrides.global = previousHttp;
  });

  test('URL downloads exact signed query without server auth; cache survives repository reopen', () async {
    String? query;
    handler = (r) async {
      query = r.uri.query;
      await respond(r, video);
    };
    final media = await item();
    final task = await download(media);
    expect(task.state, VideoCacheTaskState.complete, reason: task.error);
    expect(query, 'signature=a%2Fb&x=2&x=1');
    expect(task.received, video.length);
    expect(task.expected, video.length);
    expect(await bytes(media.identity), video);
    await cache.dispose();
    cache = EmbyCacheRepository(
      sources: sources,
      connections: connections,
      cacheDirectory: () async => root,
    );
    expect(await bytes(media.identity), video);
  });

  test(
    'URL cached playback uses lease and protects against cleaning',
    () async {
      final media = await item();
      expect((await download(media)).state, VideoCacheTaskState.complete);
      final engine = FakeVideoEngine();
      final session = PlaybackSession(
        sources: sources,
        cache: cache,
        records: PlaybackRepository(sources.database),
        createEngine: () => engine,
      );
      try {
        await session.open(media.identity);
        expect(session.error, isNull);
        expect(p.isWithin(root.path, engine.openedPath!), isTrue);
        await cache.maintenance(clear: true);
        expect(await File(engine.openedPath!).exists(), isTrue);
        expect(await cache.entries(), hasLength(1));
      } finally {
        await session.close();
        session.dispose();
      }
      await cache.maintenance(clear: true);
      expect(await cache.entries(), isEmpty);
    },
  );

  test(
    'unavailable cache root falls back online and preserves manifest',
    () async {
      final media = await item();
      await download(media);
      await cache.dispose();
      cache = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async =>
            throw const FileSystemException('unavailable'),
      );
      final engine = FakeVideoEngine();
      final session = PlaybackSession(
        sources: sources,
        cache: cache,
        records: PlaybackRepository(sources.database),
        createEngine: () => engine,
      );
      try {
        await session.open(media.identity);
        expect(session.error, isNull);
        expect(engine.openedPath, address());
        expect(session.cacheWarning, contains('缓存读取失败'));
        expect(
          await sources.database
              .customSelect('SELECT * FROM video_disk_cache')
              .get(),
          hasLength(1),
        );
      } finally {
        await session.close();
        session.dispose();
      }
    },
  );

  test(
    'damaged cache falls back online with warning without deleting manifest',
    () async {
      final media = await item();
      await download(media);
      final lease = (await cache.acquire(media.identity))!;
      await cache.release(lease.lease);
      await File(lease.path).writeAsBytes([1, 2]);
      final engine = FakeVideoEngine();
      final session = PlaybackSession(
        sources: sources,
        cache: cache,
        records: PlaybackRepository(sources.database),
        createEngine: () => engine,
      );
      try {
        await session.open(media.identity);
        expect(session.error, isNull);
        expect(engine.openedPath, address());
        expect(session.cacheWarning, contains('缓存文件缺失或不完整'));
        expect(await cache.hasRecord(media.identity), isTrue);
      } finally {
        await session.close();
        session.dispose();
      }
    },
  );

  test(
    'external URL playback prefers cached file and retains its lease',
    () async {
      final media = await item();
      await download(media);
      final gateway = _Gateway();
      final external = ExternalPlaybackService(
        sources: sources,
        settings: ExternalPlayerSettingsRepository(sources.database),
        gateway: gateway,
        acquireCache: cache.acquire,
        releaseCache: cache.release,
        renewCache: cache.renew,
      );
      try {
        await external.openLibrary(media.identity);
        expect(p.isWithin(root.path, gateway.opened!), isTrue);
        await cache.maintenance(clear: true);
        expect(await File(gateway.opened!).exists(), isTrue);
      } finally {
        await external.dispose();
      }
      await cache.maintenance(clear: true);
      expect(await cache.entries(), isEmpty);
    },
  );

  for (final status in [401, 403, 500]) {
    test('HTTP $status redownload preserves old cache and can retry', () async {
      final media = await item();
      await download(media);
      handler = (r) async {
        r.response.statusCode = status;
        await r.response.close();
      };
      final failed = await download(media);
      expect(failed.state, VideoCacheTaskState.failed);
      expect(failed.error, contains('HTTP $status'));
      expect(failed.error, isNot(contains('signature')));
      expect(await bytes(media.identity), video);
      handler = (r) => respond(r, video.reversed.toList());
      expect((await download(media)).state, VideoCacheTaskState.complete);
      expect(await bytes(media.identity), video.reversed.toList());
    });
  }

  test(
    'cancel stalled body preserves previous cache and removes staging',
    () async {
      final media = await item();
      await download(media);
      final started = Completer<void>();
      handler = (r) async {
        r.response.bufferOutput = false;
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.contentLength = video.length;
        r.response.add(video.take(1024).toList());
        await r.response.flush();
        started.complete();
      };
      await cache.enqueue(media, EmbyVideoQuality.source);
      await started.future;
      final task = cache.tasks.value[media.identity]!;
      final watch = Stopwatch()..start();
      await cache.cancel(task).timeout(const Duration(seconds: 2));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(task.state, VideoCacheTaskState.cancelled);
      expect(await bytes(media.identity), video);
      expect(
        await sources.database
            .customSelect('SELECT * FROM video_cache_staging')
            .get(),
        isEmpty,
      );
    },
  );

  test('maintenance cannot delete staged replacement; cancellation preserves old video', () async {
    final media = await item();
    await download(media);
    final entered = Completer<void>(), release = Completer<void>();
    beforePublish = () async {
      entered.complete();
      await release.future;
    };
    await cache.enqueue(media, EmbyVideoQuality.source);
    await entered.future;
    final task = cache.tasks.value[media.identity]!;
    await cache.maintenance();
    expect(await bytes(media.identity), video);
    expect(
      Directory(p.join(root.path, 'VideoCache', '.staging', task.token))
          .existsSync(),
      isTrue,
    );
    final cancel = cache.cancel(task);
    release.complete();
    await cancel;
    expect(await bytes(media.identity), video);
  });

  test(
    'clear-all during URL save protects the uncommitted staging bundle',
    () async {
      final media = await item();
      beforePublish = () => cache.maintenance(clear: true);
      final task = await download(media);
      expect(task.state, VideoCacheTaskState.complete, reason: task.error);
      expect(await bytes(media.identity), video);
    },
  );

  test('database publish failure preserves old cache', () async {
    final media = await item();
    await download(media);
    await sources.database.customStatement(
      '''CREATE TRIGGER reject_url_cache BEFORE UPDATE ON video_disk_cache
      BEGIN SELECT RAISE(ABORT, 'fixture'); END''',
    );
    final task = await download(media);
    expect(task.state, VideoCacheTaskState.failed);
    await sources.database.customStatement('DROP TRIGGER reject_url_cache');
    expect(await bytes(media.identity), video);
  });

  test('removed URL cannot be resurrected by a delayed publish', () async {
    final media = await item();
    beforePublish = () => urls.remove({media.identity});
    expect((await download(media)).state, VideoCacheTaskState.failed);
    expect(await cache.entries(), isEmpty);
    expect(await urls.list(), isEmpty);
  });

  test('HTML, disguised HLS and DASH are not published', () async {
    final media = await item();
    for (final payload in [
      '#EXTM3U\n#EXTINF:5,\na.ts',
      '<?xml version="1.0"?><MPD/>',
      '<!doctype html><html>login</html>',
    ]) {
      handler = (r) async {
        r.response.headers.contentType = ContentType.binary;
        r.response.write(payload.substring(0, 3));
        await r.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        r.response.write(payload.substring(3));
        await r.response.close();
      };
      expect((await download(media)).state, VideoCacheTaskState.failed);
      expect(await cache.entries(), isEmpty);
    }
  });

  test(
    'unsupported schemes and playlist addresses reject before starting a task',
    () async {
      for (final url in [
        'rtsp://host/a',
        address('/a.m3u8'),
        address('/a.mpd'),
      ]) {
        final media = await item(url);
        await expectLater(
          cache.enqueue(media, EmbyVideoQuality.source),
          throwsA(isA<SourceFailure>()),
        );
        expect(cache.tasks.value, isEmpty);
      }
    },
  );

  test(
    'chunked extensionless response is streamed and cached with safe filename',
    () async {
      handler = (r) async {
        r.response.headers.contentType = ContentType.binary;
        r.response.add(video);
        await r.response.close();
      };
      final media = await item(address('/signed'));
      expect((await download(media)).state, VideoCacheTaskState.complete);
      expect((await cache.entries()).single.filename, 'video.bin');
      expect(await bytes(media.identity), video);
    },
  );

  test('public cross-origin redirect uses exact target query without copying credentials', () async {
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? query, authorization;
    other.listen((r) async {
      query = r.uri.query;
      authorization = r.headers.value('authorization');
      await respond(r, video);
    });
    handler = (r) async {
      r.response.statusCode = 302;
      r.response.headers.set(
        'location',
        'http://127.0.0.1:${other.port}/cdn?sig=z%2Fx&k=2&k=1',
      );
      await r.response.close();
    };
    try {
      final media = await item();
      expect((await download(media)).state, VideoCacheTaskState.complete);
      expect(query, 'sig=z%2Fx&k=2&k=1');
      expect(authorization, isNull);
    } finally {
      await other.close(force: true);
    }
  });

  test(
    'native mpv decodes URL cache with online endpoint unavailable',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final fixture = await createTrackVideoFixture(
        p.join(root.path, 'fixture.mkv'),
      );
      handler = (r) async {
        r.response.headers.contentType = ContentType('video', 'x-matroska');
        r.response.contentLength = await fixture.length();
        await r.response.addStream(fixture.openRead());
        await r.response.close();
      };
      final media = await item(address('/fixture.mkv'));
      expect((await download(media)).state, VideoCacheTaskState.complete);
      var onlineRequests = 0;
      handler = (r) async {
        onlineRequests++;
        r.response.statusCode = 503;
        await r.response.close();
      };
      final lease = (await cache.acquire(media.identity))!;
      final player = Player(
        configuration: const PlayerConfiguration(muted: true),
      );
      try {
        final native = player.platform as NativePlayer;
        await native.setProperty('vid', 'auto');
        await player.open(Media(lease.path), play: false);
        await VideoLoadMonitor(timeout: const Duration(seconds: 5)).wait(
          read: () => readVideoLoadSnapshot(
            property: native.getProperty,
            duration: () => player.state.duration,
            checkAlive: () {},
          ),
          backendIssue: () => null,
        );
        expect(player.state.duration, greaterThan(Duration.zero));
        expect(onlineRequests, 0);
        await cache.maintenance(clear: true);
        expect(await File(lease.path).exists(), isTrue);
      } finally {
        await player.dispose();
        await cache.release(lease.lease);
      }
    },
    skip: library.isEmpty ? 'Set REELNEST_MPV_PATH for native check' : false,
  );

  for (final ignoresRange in [false, true]) {
    test('pause resume validates range; server ignores Range=$ignoresRange', () async {
      final media = await item();
      final payload = [...video]..setRange(8192, 8197, '<html'.codeUnits);
      var requests = 0;
      handler = (r) async {
        requests++;
        if (requests == 1) {
          r.response.bufferOutput = false;
          r.response.headers.contentType = ContentType('video', 'mp4');
          r.response.headers.set('etag', '"version-1"');
          r.response.contentLength = video.length;
          r.response.add(payload.take(8192).toList());
          await r.response.flush();
          return;
        }
        expect(r.headers.value('range'), 'bytes=8192-');
        expect(r.headers.value('if-range'), '"version-1"');
        if (ignoresRange) {
          await respond(r, payload);
        } else {
          r.response.statusCode = 206;
          r.response.headers.contentType = ContentType('video', 'mp4');
          r.response.headers.set('etag', '"version-1"');
          r.response.headers.set(
            'content-range',
            'bytes 8192-${video.length - 1}/${video.length}',
          );
          r.response.contentLength = video.length - 8192;
          r.response.add(payload.skip(8192).toList());
          await r.response.close();
        }
      };
      await cache.enqueue(media, EmbyVideoQuality.source);
      final task = cache.tasks.value[media.identity]!;
      await waitFor(
        () => task.received == 8192,
        () =>
            'initial state=${task.state} bytes=${task.received} error=${task.error} requests=$requests',
      );
      cache.pause(task);
      await task.work;
      expect(task.state, VideoCacheTaskState.paused);
      await cache.resume(task);
      await waitFor(
        () => [
          VideoCacheTaskState.complete,
          VideoCacheTaskState.failed,
        ].contains(task.state),
      );
      await task.work;
      expect(task.state, VideoCacheTaskState.complete, reason: task.error);
      expect(requests, 2);
      expect(await bytes(media.identity), payload);
    });
  }

  test('disk write failure cannot replace the previous cache', () async {
    final media = await item();
    await download(media);
    handler = (r) async {
      final token = cache.tasks.value[media.identity]!.token;
      await Directory(
        p.join(root.path, 'VideoCache', '.staging', token, 'video.mp4'),
      ).create();
      await respond(r, video);
    };
    expect((await download(media)).state, VideoCacheTaskState.failed);
    expect(await bytes(media.identity), video);
  });

  test('dropped response cannot publish an incomplete video', () async {
    final media = await item();
    await download(media);
    handler = (r) async {
      r.response.headers.contentType = ContentType('video', 'mp4');
      r.response.contentLength = video.length;
      r.response.add(video.take(1024).toList());
      await r.response.flush();
      (await r.response.detachSocket()).destroy();
    };
    expect((await download(media)).state, VideoCacheTaskState.failed);
    expect(await bytes(media.identity), video);
  });

  test(
    'shutdown cancels stalled URL work without waiting for network timeout',
    () async {
      final media = await item();
      final started = Completer<void>();
      handler = (r) async {
        r.response.bufferOutput = false;
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.contentLength = video.length;
        r.response.add([1, 2]);
        await r.response.flush();
        started.complete();
      };
      await cache.enqueue(media, EmbyVideoQuality.source);
      await started.future;
      await cache.dispose().timeout(const Duration(seconds: 2));
      expect(
        await sources.database
            .customSelect('SELECT * FROM video_disk_cache')
            .get(),
        isEmpty,
      );
    },
  );
}
