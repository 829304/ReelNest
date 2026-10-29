import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/sources/domain/url_video.dart';
import 'package:reelnest/features/sources/data/url_video_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/application/url_video_health_monitor.dart';
import 'package:reelnest/features/sources/application/url_video_cover_service.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/application/external_playback_service.dart';
import 'package:reelnest/features/playback/data/external_player_settings_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/external_player_settings.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/health/domain/video_health_evaluator.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';
import 'package:reelnest/platform/external_player_gateway.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';
import 'support/tmdb_fixture.dart' show tmdbFixturePng;

class _Gateway implements ExternalPlayerGateway {
  final opened = <String>[];
  @override
  Future<void> launch(String location, {String? applicationPath}) async {
    opened.add(location);
  }

  @override
  Future<void> validateApplication(String path) async {}
  @override
  Future<List<ExternalPlayerApplication>> availablePlayers({
    String? customPath,
  }) async => [];
}

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SourceRepository sources;
  late UrlVideoRepository urls;
  setUp(() {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    urls = UrlVideoRepository(sources);
  });
  tearDown(() async {
    await sources.close();
  });
  test(
    'policy preserves signed URLs, original schemes and safe default titles',
    () {
      for (final scheme in UrlVideoPolicy.schemes) {
        expect(
          UrlVideoPolicy.normalize('  $scheme://host/path?a=2&b=%20#f  '),
          '$scheme://host/path?a=2&b=%20#f',
        );
      }
      for (final value in [
        'file:///secret.mp4',
        'javascript://host/a',
        'https:///',
        'https://host:bad/a',
        'http://host/a\u0000',
        'https://host/a b',
      ]) {
        expect(UrlVideoPolicy.normalize(value), isNull);
      }
      expect(
        UrlVideoPolicy.title(
          'https://host/%E7%94%B5%E5%BD%B1.mkv?token=secret',
        ),
        '电影',
      );
      expect(UrlVideoPolicy.title('https://host/'), 'host');
      expect(
        UrlVideoPolicy.addableCount(
          'https://host/a\nhttps://host/a\ninvalid\nrtsp://host/live',
        ),
        2,
      );
      expect(
        UrlVideoPolicy.id('https://host/a?token=secret'),
        isNot(contains('secret')),
      );
    },
  );
  test(
    'bulk add creates one virtual container with original defaults',
    () async {
      final result = await urls.add(
        'https://host/a.mkv\ninvalid\nhttps://host/a.mkv\nrtsp://host/live',
      );
      expect((result.added, result.skipped), (2, 2));
      final source = (await sources.sources()).single;
      expect(source.kind, MediaSourceKind.url);
      expect(source.itemCount, 2);
      expect(source.options.autoScan, isFalse);
      expect(source.options.includeInMetadataFetch, isFalse);
      expect(source.options.includeInHealthCheck, isTrue);
      expect(
        (await sources.inventory()).items.every((i) => i.type == 'homeVideo'),
        isTrue,
      );
      expect(HomeRepository.accepts(source), isTrue);
      expect((await sources.browse(source.id)).total, 2);
      await expectLater(
        urls.add('https://host/a.mkv'),
        throwsA(isA<SourceFailure>()),
      );
      expect((await sources.sources()).length, 1);
      expect(sources.database.schemaVersion, 1);
    },
  );
  test(
    'failed bulk insert rolls back all URLs and the empty container',
    () async {
      await sources.sources();
      await sources.database.customStatement(
        "CREATE TRIGGER reject_url BEFORE INSERT ON url_video_entries WHEN new.url LIKE '%fail%' BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await expectLater(
        urls.add('https://host/good\nhttps://host/fail'),
        throwsA(anything),
      );
      expect(await urls.list(), isEmpty);
      expect(await sources.sources(), isEmpty);
    },
  );
  test('title edit keeps progress, address edit changes identity and removes old progress', () async {
    await urls.add('https://host/a.mkv', title: ' Name ');
    final before = (await urls.list()).single;
    final records = PlaybackRepository(sources.database);
    await records.save(
      before.identity,
      position: const Duration(seconds: 40),
      duration: const Duration(seconds: 200),
    );
    expect(
      await urls.update(before.identity, url: before.url, title: 'Edited'),
      before.identity,
    );
    expect(
      (await records.read(before.identity)).position,
      const Duration(seconds: 40),
    );
    final changed = await urls.update(
      before.identity,
      url: 'https://host/new.mkv',
      title: '',
    );
    expect(changed, isNot(before.identity));
    expect((await urls.list()).single.createdAt, before.createdAt);
    expect((await urls.list()).single.title, 'new');
    expect(
      (await sources.database
          .customSelect('SELECT * FROM playback_states')
          .get()),
      isEmpty,
    );
    await expectLater(
      sources.media(before.identity),
      throwsA(isA<SourceFailure>()),
    );
  });
  test('conflicting edit and invalid removal preserve rows, last removal removes container', () async {
    await urls.add('https://host/a\nhttps://host/b');
    final items = await urls.list();
    await expectLater(
      urls.update(items[0].identity, url: items[1].url, title: 'Bad'),
      throwsA(isA<SourceFailure>()),
    );
    expect((await urls.list()).map((i) => i.title), items.map((i) => i.title));
    await expectLater(
      urls.remove({items[0].identity, (sourceId: 'other', localId: 'not-url')}),
      throwsA(isA<SourceFailure>()),
    );
    expect((await urls.list()).length, 2);
    await urls.remove(items.map((i) => i.identity).toSet());
    expect(await sources.sources(), isEmpty);
  });
  test('saved URL uses built-in and external playback without server authentication', () async {
    const address = 'https://host/film.mkv?signature=a%2Fb&x=2';
    await urls.add(address);
    final id = (await urls.list()).single.identity, engine = FakeVideoEngine();
    final records = PlaybackRepository(sources.database);
    final session = PlaybackSession(
      sources: sources,
      records: records,
      createEngine: () => engine,
    );
    try {
      await session.open(id);
      expect(engine.openedPath, address);
      engine.emit(position: const Duration(seconds: 35));
      await session.close();
      expect((await records.read(id)).position, const Duration(seconds: 35));
      final gateway = _Gateway();
      final external = ExternalPlaybackService(
        sources: sources,
        settings: ExternalPlayerSettingsRepository(sources.database),
        gateway: gateway,
      );
      try {
        await external.openLibrary(id);
        expect(gateway.opened, [address]);
      } finally {
        await external.dispose();
      }
    } finally {
      await session.close(discardProgress: true);
      session.dispose();
    }
  });
  test('URL health never probes disk or reports incomplete server index and honors opt-out', () async {
    await urls.add('https://host/a');
    final item = (await urls.list()).single;
    final evaluator = VideoHealthEvaluator(
      LocalHealthEvaluator(
        paths: p.context,
        exists: (_) async => throw StateError('must not probe disk'),
      ),
    );
    final first = await evaluator.evaluate(
      await sources.inventory(),
      cancellation: ScanCancellation(),
      unhealthyURLs: {item.identity: '无法访问'},
    );
    expect(first.missing, isEmpty);
    expect(first.partialIndex, isFalse);
    expect(first.metadataGaps, isEmpty);
    expect(first.unhealthyURLs, {item.identity: '无法访问'});
    await sources.updateSettings(
      item.identity.sourceId,
      options: SourceOptions(
        includeInHealthCheck: false,
        autoScan: true,
        includeInMetadataFetch: true,
        preferMetadataWriteToSource: true,
      ),
    );
    final source = await sources.source(item.identity.sourceId);
    expect(source.options.includeInMetadataFetch, isFalse);
    expect(source.options.autoScan, isFalse);
    final second = await evaluator.evaluate(
      await sources.inventory(),
      cancellation: ScanCancellation(),
      unhealthyURLs: {item.identity: '无法访问'},
    );
    expect(second.unhealthyURLs, isEmpty);
  });
  test(
    'health skips non HTTP and rejects late results from removed URLs',
    () async {
      await urls.add('https://host/old\nrtsp://host/live');
      final first = await urls.list();
      final gate = Completer<UrlVideoHealth>(), started = Completer<void>();
      var calls = 0;
      Map<MediaIdentity, UrlVideoHealth> state = {};
      final monitor = UrlVideoHealthMonitor(
        onState: (s) => state = s,
        probe: (url, token) {
          calls++;
          started.complete();
          return gate.future;
        },
      );
      try {
        final old = monitor.refresh(first);
        await started.future;
        await monitor.refresh(
          first.where((i) => i.url.startsWith('rtsp')).toList(),
        );
        gate.complete(UrlVideoHealth.unreachable);
        await old;
        expect(
          state.keys,
          isNot(
            contains(
              first.firstWhere((i) => i.url.startsWith('https')).identity,
            ),
          ),
        );
        expect(calls, 1);
        await monitor.refresh(first, enabled: false);
        expect(state, isEmpty);
      } finally {
        await monitor.dispose();
      }
    },
  );
  test(
    'HTTP classification consumes headers rather than oversized bodies',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var heads = 0, gets = 0;
      server.listen((r) async {
        if (r.method == 'HEAD') {
          heads++;
        } else {
          gets++;
        }
        r.response.statusCode = r.uri.path == '/missing' ? 404 : 200;
        r.response.headers.set(
          'Content-Type',
          r.uri.path == '/html' ? 'text/html' : 'video/mp4',
        );
        r.response.contentLength = 50 * 1024 * 1024;
        try {
          await r.response.close();
        } catch (_) {}
      });
      await urls.add(
        [
          'html',
          'missing',
          'ok',
        ].map((s) => 'http://127.0.0.1:${server.port}/$s').join('\n'),
      );
      Map<MediaIdentity, UrlVideoHealth> state = {};
      final monitor = UrlVideoHealthMonitor(
        onState: (s) => state = s,
        createClient: () =>
            HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp()),
      );
      try {
        await monitor.refresh(await urls.list());
        expect(state.values.toSet(), {
          UrlVideoHealth.ok,
          UrlVideoHealth.unparseable,
          UrlVideoHealth.unreachable,
        });
        expect(heads, 3);
        expect(gets, 0);
      } finally {
        await monitor.dispose();
        await server.close(force: true);
      }
    },
  );
  test('HEAD transport failure falls back to a range GET without buffering its body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var heads = 0, gets = 0;
    String? range;
    server.listen((r) async {
      if (r.method == 'HEAD') {
        heads++;
        final socket = await r.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      gets++;
      range = r.headers.value(HttpHeaders.rangeHeader);
      r.response.headers.set('Content-Type', 'video/mp4');
      r.response.contentLength = 64 * 1024 * 1024;
      try {
        r.response.add(List.filled(4096, 0));
        await r.response.flush();
        await r.response.close();
      } catch (_) {}
    });
    await urls.add('http://127.0.0.1:${server.port}/video');
    Map<MediaIdentity, UrlVideoHealth> state = {};
    final monitor = UrlVideoHealthMonitor(
      onState: (s) => state = s,
      createClient: () =>
          HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp()),
    );
    try {
      await monitor
          .refresh(await urls.list())
          .timeout(const Duration(seconds: 3));
      expect(state.values.single, UrlVideoHealth.ok);
      expect(heads, 1);
      expect(gets, 1);
      expect(range, 'bytes=0-1023');
    } finally {
      await monitor.dispose();
      await server.close(force: true);
    }
  });
  test('disposing a stalled real HTTP request aborts promptly without stale publication', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final entered = Completer<void>();
    var updates = 0;
    server.listen((r) {
      if (!entered.isCompleted) entered.complete();
    });
    await urls.add('http://127.0.0.1:${server.port}/stall');
    final monitor = UrlVideoHealthMonitor(
      onState: (_) => updates++,
      createClient: () =>
          HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp()),
    );
    try {
      final work = monitor.refresh(await urls.list());
      await entered.future;
      await monitor.dispose().timeout(const Duration(seconds: 1));
      await work;
      expect(updates, 1);
    } finally {
      await monitor.dispose();
      await server.close(force: true);
    }
  });
  test('automatic cover cannot overwrite a newer custom cover', () async {
    final directory = await Directory.systemTemp.createTemp(
      'reelnest-url-cover-',
    );
    await urls.add('https://host/a.mkv');
    final id = (await urls.list()).single.identity;
    final gate = Completer<void>(), started = Completer<void>();
    final service = UrlVideoCoverService(
      sources: sources,
      artwork: TmdbArtworkStore(library: () async => directory),
      generate: (resource, token) async {
        started.complete();
        await gate.future;
        return tmdbFixturePng;
      },
    );
    try {
      final work = service.capture(id);
      await started.future;
      await sources.database.customStatement('UPDATE media SET poster_path=?', [
        'custom.png',
      ]);
      gate.complete();
      await work;
      expect((await sources.media(id)).posterPath, 'custom.png');
    } finally {
      await service.dispose();
      expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
      expect(p.basename(directory.path), startsWith('reelnest-url-cover-'));
      await directory.delete(recursive: true);
    }
  });
}
