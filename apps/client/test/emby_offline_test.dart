import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_quality.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/data/emby_cache_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_offline_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/sources/domain/emby_offline_subscription.dart';
import 'package:reelnest/platform/network_status.dart';
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

VideoLibraryEntry episode(
  int n, {
  int season = 1,
  String source = 's',
  int progress = 0,
  bool watched = false,
}) {
  final id = (sourceId: source, localId: 'e$n');
  return VideoLibraryEntry(
    item: IndexedMedia(
      identity: id,
      title: 'Episode $n',
      type: 'episode',
      parentId: 'series',
      seasonNumber: season,
      episodeNumber: n,
      bytes: 0,
      modified: DateTime.utc(2026),
      remote: RemoteMediaMetadata(externalId: 'e$n'),
    ),
    record: PlaybackRecord(
      identity: id,
      position: Duration(seconds: progress),
      duration: const Duration(seconds: 100),
      watched: watched,
    ),
    createdAt: DateTime.utc(2026),
  );
}

OfflineSubscription rule({
  OfflineMode mode = OfflineMode.nextUnwatched,
  int count = 3,
  int? season,
  OfflineNetwork network = OfflineNetwork.allowRemote,
}) => OfflineSubscription(
  id: 'rule',
  series: (sourceId: 's', localId: 'series'),
  title: 'Series',
  mode: mode,
  episodeLimit: count,
  season: season,
  network: network,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
List<String> plan(
  OfflineSubscription r,
  List<VideoLibraryEntry> items, {
  Set<MediaIdentity> cached = const {},
  Set<MediaIdentity> queued = const {},
  bool wifi = true,
  String host = '127.0.0.1',
  double threshold = .9,
}) => offlineCandidates(
  r,
  items,
  cached: cached,
  queued: queued,
  wifi: wifi,
  host: host,
  threshold: threshold,
).map((e) => e.item.identity.localId).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('original offline policy', () {
    test('cached and queued copies occupy the first N unwatched places', () {
      final items = [for (var n = 5; n >= 1; n--) episode(n)];
      expect(
        plan(
          rule(),
          items,
          cached: {items.last.item.identity},
          queued: {items[3].item.identity},
        ),
        ['e3'],
      );
      expect(
        plan(
          rule(mode: OfflineMode.nextEpisode),
          items,
          cached: {items.last.item.identity},
        ),
        isEmpty,
      );
    });
    test(
      'watched flag and threshold exclude episodes before selecting window',
      () {
        final items = [
          episode(1, watched: true),
          episode(2, progress: 90),
          episode(3, progress: 89),
          episode(4),
        ];
        expect(plan(rule(count: 1), items), ['e3']);
        for (final threshold in [double.nan, double.infinity, 0.0, 2.0]) {
          expect(plan(rule(count: 1), items, threshold: threshold), ['e3']);
        }
      },
    );
    test('whole season and full series include watched episodes and isolate sources', () {
      final items = [
        episode(5, season: 2),
        episode(2, watched: true),
        episode(1),
        episode(4, season: 2),
        episode(3, source: 'other'),
      ];
      expect(plan(rule(mode: OfflineMode.fullSeries), items), [
        'e1',
        'e2',
        'e4',
        'e5',
      ]);
      expect(plan(rule(mode: OfflineMode.season, season: 1), items), [
        'e1',
        'e2',
      ]);
    });
    test('Wi-Fi and LAN policies gate enqueue decisions', () {
      expect(
        plan(rule(network: OfflineNetwork.wifiOnly), [episode(1)], wifi: false),
        isEmpty,
      );
      expect(plan(rule(network: OfflineNetwork.wifiOnly), [episode(1)]), [
        'e1',
      ]);
      expect(
        plan(rule(network: OfflineNetwork.localNetworkOnly), [
          episode(1),
        ], host: 'example.com'),
        isEmpty,
      );
      expect(
        plan(rule(network: OfflineNetwork.localNetworkOnly), [
          episode(1),
        ], host: 'nas.local'),
        ['e1'],
      );
    });
    test(
      'private address matching does not allow lookalikes or malformed IPv4',
      () {
        for (final host in [
          'localhost',
          '127.0.0.1',
          '10.1.2.3',
          '192.168.1.1',
          '172.16.0.1',
          '172.31.255.255',
          '::1',
          '[::1]',
          'fe80::abcd',
          'fd01::1',
          'NAS.local',
        ]) {
          expect(isLocalNetworkHost(host), isTrue, reason: host);
        }
        for (final host in [
          'localhost.evil',
          'nas.local.evil',
          '172.15.1.1',
          '172.32.1.1',
          '8.8.8.8',
          '10.1.2.999',
          '192.168.1',
          '10.a.1.2',
          '2001:4860::8888',
        ]) {
          expect(isLocalNetworkHost(host), isFalse, reason: host);
        }
      },
    );
    test(
      'bounds and exact expiry/pause boundaries match original defaults',
      () {
        final time = DateTime.utc(2026);
        final r = OfflineSubscription(
          id: 'r',
          series: (sourceId: 's', localId: 'series'),
          title: '  ',
          mode: OfflineMode.nextUnwatched,
          episodeLimit: 999,
          season: 9999,
          qualityId: 'original',
          createdAt: time,
          updatedAt: time,
          pausedUntil: time,
          expiresAt: time,
        );
        expect(r.episodeLimit, 99);
        expect(r.season, 999);
        expect(r.title, '未命名系列');
        expect(r.qualityId, isNull);
        expect(r.paused(time), isFalse);
        expect(r.expired(time), isTrue);
        expect(r.runnable(time), isFalse);
        expect(rule(count: 0).episodeLimit, 1);
      },
    );
    test(
      'Linux default route parser respects flags, metrics and interface paths',
      () {
        const table =
            'Iface Destination Gateway Flags RefCnt Use Metric Mask\n'
            'eth0 00000000 0100000A 0003 0 0 100 00000000\n'
            'wlan0 00000000 0100000A 0003 0 0 20 00000000\n'
            'down0 00000000 0100000A 0002 0 0 1 00000000\n'
            '../bad 00000000 0100000A 0003 0 0 0 00000000\n'
            'eth1 0001000A 0100000A 0003 0 0 0 00FFFFFF';
        expect(linuxDefaultRoutes(table), ['wlan0', 'eth0']);
      },
    );
    test(
      'Windows network route probe completes without external requests',
      () async {
        if (!Platform.isWindows) return;
        expect(
          await desktopWifiAvailable().timeout(const Duration(seconds: 8)),
          isA<bool>(),
        );
      },
    );
  });

  group('SQLite subscriptions and streamed local HTTP downloads', () {
    late EmbyServerFixture server;
    late EmbyClient client;
    late SourceRepository sources;
    late EmbyConnectionRepository connections;
    late EmbyCacheRepository cache;
    late EmbyOfflineRepository offline;
    late Directory directory;
    late MediaSource source;
    late IndexedMedia series;
    late DateTime clock;
    var wifi = true, wifiProbes = 0, pathProbes = 0;
    final stores = <String, _Store>{};
    final bytes = List<int>.generate(32768, (i) => i % 251);
    Map<String, dynamic> remoteEpisode(int n) => {
      'Id': 'e$n',
      'Name': 'Episode $n',
      'Type': 'Episode',
      'SeriesId': 'series',
      'ParentIndexNumber': n <= 3 ? 1 : 2,
      'IndexNumber': n <= 3 ? n : n - 3,
      'RunTimeTicks': 1000000000,
      'MediaSources': [
        {
          'Id': 'media-e$n',
          'Container': 'mp4',
          'Size': bytes.length,
          'MediaStreams': [
            {
              'Type': 'Video',
              'Width': 3840,
              'Height': 2160,
              'BitRate': 40000000,
            },
          ],
        },
      ],
    };
    Future<void> sync() => EmbySyncRepository(
      sources: sources,
      connections: connections,
    ).synchronize(source.id);
    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('offline task timed out');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    Future<void> drained() async {
      await waitFor(
        () => cache.tasks.value.values.every(
          (t) => [
            VideoCacheTaskState.complete,
            VideoCacheTaskState.failed,
            VideoCacheTaskState.cancelled,
          ].contains(t.state),
        ),
      );
      for (final task in cache.tasks.value.values) {
        await task.work;
      }
    }

    Future<Set<String>> cachedIds() async =>
        (await cache.entries()).map((e) => e.identity.localId).toSet();
    setUp(() async {
      clock = DateTime.utc(2026, 10, 10);
      wifi = true;
      wifiProbes = 0;
      pathProbes = 0;
      stores.clear();
      directory = await Directory.systemTemp.createTemp('reelnest-offline-');
      server = EmbyServerFixture();
      await server.start();
      client = EmbyClient(
        deviceId: 'offline-device',
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
        'fixture-only',
      );
      server.catalog['shows'] = [
        {'Id': 'series', 'Name': '测试系列', 'Type': 'Series'},
        for (var n = 1; n <= 5; n++) remoteEpisode(n),
      ];
      await sync();
      series = await sources.media((sourceId: source.id, localId: 'series'));
      cache = EmbyCacheRepository(
        sources: sources,
        connections: connections,
        cacheDirectory: () async {
          pathProbes++;
          return directory;
        },
      );
      offline = EmbyOfflineRepository(
        sources: sources,
        cache: cache,
        now: () => clock,
        wifiAvailable: () async {
          wifiProbes++;
          return wifi;
        },
      );
      server.streamHandler = (r) async {
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.contentLength = bytes.length;
        r.response.add(bytes);
        await r.response.close();
      };
    });
    tearDown(() async {
      await offline.dispose();
      await cache.dispose();
      connections.dispose();
      client.close();
      await sources.close();
      await server.close();
      final root = directory.absolute.path;
      if (!p.isWithin(Directory.systemTemp.absolute.path, root) ||
          !p.basename(root).startsWith('reelnest-offline-')) {
        throw StateError('unexpected fixture directory');
      }
      await directory.delete(recursive: true);
    });
    test(
      'no subscriptions means no filesystem, Wi-Fi or server probes',
      () async {
        final count = server.requests.length;
        await offline.start();
        await offline.maintain();
        expect(offline.state.value.rules, isEmpty);
        expect(offline.state.value.error, isNull);
        expect(wifiProbes, 0);
        expect(pathProbes, 0);
        expect(server.requests.length, count);
      },
    );
    test(
      'window downloads only N, watching one automatically adds the next',
      () async {
        await offline.start();
        await offline.save(series, OfflineMode.nextUnwatched, episodeLimit: 3);
        await offline.maintain();
        await drained();
        expect(await cachedIds(), {'e1', 'e2', 'e3'});
        final first = await sources.media((sourceId: source.id, localId: 'e1'));
        final file = (await cache.entries()).firstWhere(
          (e) => e.identity == first.identity,
        );
        expect(
          await File(
            p.join(
              (await cache.videoRoot()).path,
              'objects',
              file.bundle,
              file.filename,
            ),
          ).readAsBytes(),
          bytes,
        );
        await PlaybackRepository(sources.database)
            .markWatched([first.identity], true);
        sources.traceChanged();
        await waitFor(
          () => cache.tasks.value.keys.any((id) => id.localId == 'e4'),
        );
        await drained();
        expect(await cachedIds(), {'e1', 'e2', 'e3', 'e4'});
        final requests = server.requests
            .where((r) => r.uri.path.contains('/Videos/'))
            .length;
        await offline.maintain();
        await drained();
        expect(
          server.requests.where((r) => r.uri.path.contains('/Videos/')).length,
          requests,
        );
        expect(wifiProbes, 0);
      },
    );
    test(
      'save persists one rule, keeps identity/network/expiry and resets pause',
      () async {
        final original = await offline.save(
          series,
          OfflineMode.nextUnwatched,
          episodeLimit: 5,
        );
        await offline.update(
          series.identity,
          network: OfflineNetwork.wifiOnly,
          expirationDays: 30,
          pause: true,
        );
        clock = clock.add(const Duration(days: 1));
        final current = await offline.save(
          series,
          OfflineMode.nextUnwatched,
          episodeLimit: 10,
          qualityId: '1080p',
        );
        expect(current.id, original.id);
        expect(current.createdAt, original.createdAt);
        expect(current.network, OfflineNetwork.wifiOnly);
        expect(current.pausedUntil, isNull);
        expect(
          current.expiresAt,
          original.createdAt.add(const Duration(days: 30)),
        );
        final reader = EmbyOfflineRepository(sources: sources, cache: cache);
        expect((await reader.rules()).single.episodeLimit, 10);
        await reader.dispose();
        expect((await offline.rules()).length, 1);
      },
    );
    test('pause waits seven days and expiry deletes only the rule', () async {
      await offline.save(series, OfflineMode.nextEpisode);
      await offline.update(series.identity, pause: true, expirationDays: 30);
      await offline.maintain();
      expect(cache.tasks.value, isEmpty);
      clock = clock.add(const Duration(days: 7));
      await offline.maintain();
      await drained();
      expect(await cachedIds(), {'e1'});
      clock = clock.add(const Duration(days: 23));
      await offline.maintain();
      expect(await offline.rules(), isEmpty);
      expect(await cachedIds(), {'e1'});
    });
    test(
      'Wi-Fi-only subscription wakes when Wi-Fi becomes available',
      () async {
        wifi = false;
        await offline.save(series, OfflineMode.nextEpisode);
        await offline.update(series.identity, network: OfflineNetwork.wifiOnly);
        await offline.maintain();
        expect(cache.tasks.value, isEmpty);
        wifi = true;
        await offline.maintain();
        await drained();
        expect(await cachedIds(), {'e1'});
        expect(wifiProbes, greaterThanOrEqualTo(2));
      },
    );
    test('selected season and quality apply to each episode stream', () async {
      final episode = await sources.media((sourceId: source.id, localId: 'e4'));
      final quality = EmbyVideoQuality.options(episode).last;
      final r = await offline.save(
        episode,
        OfflineMode.season,
        qualityId: quality.id,
      );
      expect(r.season, 2);
      await offline.maintain();
      await drained();
      expect(await cachedIds(), {'e4', 'e5'});
      expect(
        cache.tasks.value.values.every((t) => t.quality.id == quality.id),
        isTrue,
      );
      final streams = server.requests
          .where((r) => r.uri.path.contains('/Videos/'))
          .toList();
      expect(streams.length, 2);
      expect(
        streams.every((r) => r.uri.queryParameters['Static'] == 'false'),
        isTrue,
      );
    });
    test('stop and pause do not cancel an already running download', () async {
      final entered = Completer<void>(), release = Completer<void>();
      server.streamHandler = (r) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.contentLength = bytes.length;
        r.response.add(bytes);
        await r.response.close();
      };
      try {
        await offline.save(series, OfflineMode.nextEpisode);
        await offline.maintain();
        await entered.future.timeout(const Duration(seconds: 8));
        await offline.update(series.identity, pause: true);
        await offline.stop(series.identity);
        expect(await offline.rules(), isEmpty);
        expect(
          cache.tasks.value.values.single.state,
          VideoCacheTaskState.downloading,
        );
      } finally {
        release.complete();
      }
      await drained();
      expect(await cachedIds(), {'e1'});
      cache.clearFinished();
      expect(cache.tasks.value, isEmpty);
      expect(await cachedIds(), {'e1'});
    });
    test('failed downloads do not form a source-change retry loop', () async {
      server.streamHandler = (r) async {
        r.response.statusCode = 503;
        await r.response.close();
      };
      await offline.start();
      await offline.save(series, OfflineMode.nextEpisode);
      await offline.maintain();
      await drained();
      expect(cache.tasks.value.values.single.state, VideoCacheTaskState.failed);
      final count = server.requests.length;
      sources.traceChanged();
      await offline.maintain();
      await drained();
      expect(server.requests.length, count);
      server.streamHandler = (r) async {
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.contentLength = bytes.length;
        r.response.add(bytes);
        await r.response.close();
      };
      final task = cache.tasks.value.values.single;
      await cache.enqueue(task.item, task.quality);
      await drained();
      expect(await cachedIds(), {'e1'});
    });
    test(
      'full-series subscription notices newly synchronized episodes',
      () async {
        await offline.save(series, OfflineMode.fullSeries);
        await offline.maintain();
        await drained();
        expect((await cachedIds()).length, 5);
        server.catalog['shows']!.add(remoteEpisode(6));
        await sync();
        await offline.maintain();
        await drained();
        expect(await cachedIds(), {'e1', 'e2', 'e3', 'e4', 'e5', 'e6'});
      },
    );
    test('source deletion cascades subscription rules', () async {
      await offline.save(series, OfflineMode.nextEpisode);
      await offline.update(series.identity, pause: true);
      await sources.remove(source.id);
      await offline.maintain();
      expect(await offline.rules(), isEmpty);
      expect(offline.state.value.error, isNull);
    });
    test('disposal prevents pending maintenance from enqueueing', () async {
      await offline.save(series, OfflineMode.nextEpisode);
      await offline.update(series.identity, network: OfflineNetwork.wifiOnly);
      await offline.dispose();
      final entered = Completer<void>(), release = Completer<bool>();
      offline = EmbyOfflineRepository(
        sources: sources,
        cache: cache,
        now: () => clock,
        wifiAvailable: () {
          if (!entered.isCompleted) entered.complete();
          return release.future;
        },
      );
      final first = offline.maintain(), second = offline.maintain();
      await entered.future;
      final closing = offline.dispose();
      release.complete(true);
      await Future.wait([first, second, closing]);
      expect(cache.tasks.value, isEmpty);
    });
  });
}
