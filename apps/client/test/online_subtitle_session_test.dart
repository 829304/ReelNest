import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/online_subtitle_payload.dart';
import 'package:reelnest/features/playback/data/online_subtitle_service.dart';
import 'package:reelnest/features/playback/data/online_subtitle_settings_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/online_subtitle.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import 'support/emby_server_fixture.dart';
import 'support/fake_video_engine.dart';

class _Credentials implements CredentialStore {
  bool failRead = false;
  String? value;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('private credential failure');
    return value;
  }

  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class _Service extends OnlineSubtitleService {
  static const result = OnlineSubtitleResult(
    id: 'pod-7',
    provider: OnlineSubtitleProvider.podnapisi,
    fileId: 7,
    displayName: '../../evil.srt',
    language: 'zh-CN',
  );
  OnlineSubtitleQuery? query;
  OnlineSubtitleSettings? settings;
  ScanCancellation? searchToken, downloadToken;
  Completer<OnlineSubtitleSearch>? pendingSearch;
  Completer<OnlineSubtitlePayload>? pendingDownload;
  int downloads = 0;
  bool failDownload = false;
  OnlineSubtitlePayload get payload => OnlineSubtitlePayload(
    Uint8List.fromList(utf8.encode('1\n00:00:00,000 --> 00:00:05,000\n下载字幕\n')),
    'srt',
  );
  @override
  Future<OnlineSubtitleSearch> search(
    OnlineSubtitleQuery query,
    OnlineSubtitleSettings settings,
    ScanCancellation cancellation,
  ) async {
    this.query = query;
    this.settings = settings;
    searchToken = cancellation;
    return pendingSearch == null
        ? const OnlineSubtitleSearch([result], [])
        : pendingSearch!.future;
  }

  @override
  Future<OnlineSubtitlePayload> download(
    OnlineSubtitleResult result,
    OnlineSubtitleSettings settings,
    ScanCancellation token,
  ) async {
    downloads++;
    downloadToken = token;
    if (failDownload) throw const OnlineSubtitleFailure('下载失败，请重试。');
    return pendingDownload == null ? payload : pendingDownload!.future;
  }
}

Future<void> _until(bool Function() condition) async {
  for (var n = 0; n < 200 && !condition(); n++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  late Directory root;
  late SourceRepository sources;
  late PlaybackSession session;
  late _Service service;
  late _Credentials credentials;
  late MediaIdentity first, second;
  final engines = <FakeVideoEngine>[];
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'reelnest-online-session-test-',
    );
    await File(p.join(root.path, 'Film.mkv')).writeAsString('video');
    await File(p.join(root.path, 'Other.mkv')).writeAsString('video');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    final source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: root.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    first = (sourceId: source.id, localId: 'Film.mkv');
    second = (sourceId: source.id, localId: 'Other.mkv');
    service = _Service();
    credentials = _Credentials();
    engines.clear();
    final preferences = PlayerPreferencesRepository(sources.database);
    session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      onlineSubtitleService: service,
      onlineSubtitleSettings: OnlineSubtitleSettingsRepository(
        preferences,
        store: credentials,
      ),
      createEngine: () {
        final engine = FakeVideoEngine();
        engines.add(engine);
        return engine;
      },
    );
    await session.open(first);
    expect(session.error, isNull);
  });
  tearDown(() async {
    await session.close(discardProgress: true);
    session.dispose();
    await sources.close();
    expect(p.basename(root.path), startsWith('reelnest-online-session-test-'));
    await root.delete(recursive: true);
  });
  test('local download uses video stem, immediately loads without changing playback; retry uses saved file', () async {
    engines.single.emit(
      position: const Duration(seconds: 12),
      playing: false,
      rate: 1.5,
    );
    await session.searchOnlineSubtitles();
    await session.downloadOnlineSubtitle(_Service.result);
    final saved = session.downloadedOnlineSubtitlePaths[_Service.result.id]!;
    expect(saved, p.join(root.path, 'Film.srt'));
    expect(await File(saved).readAsBytes(), service.payload.bytes);
    expect(engines.single.addedSubtitles, [saved]);
    expect(session.clock.position, const Duration(seconds: 12));
    expect(session.clock.playing, isFalse);
    expect(session.clock.rate, 1.5);
    await session.downloadOnlineSubtitle(_Service.result);
    expect(service.downloads, 1);
    expect(session.sidecarSubtitles.map((s) => s.path), contains(saved));
    await session.close();
    expect(await File(saved).exists(), isTrue);
  });
  test(
    'failed download preserves sidecar and does not poison playback',
    () async {
      final original = File(p.join(root.path, 'Film.srt'));
      await original.writeAsString('original');
      await session.searchOnlineSubtitles();
      service.failDownload = true;
      await session.downloadOnlineSubtitle(_Service.result);
      expect(await original.readAsString(), 'original');
      expect(session.onlineSubtitleError, contains('下载失败'));
      expect(session.error, isNull);
      expect(engines.single.disposals, 0);
      service.failDownload = false;
      await session.downloadOnlineSubtitle(_Service.result);
      expect(session.onlineSubtitleError, isNull);
    },
  );
  test('failed decoder load retries saved data without consuming another provider download', () async {
    await session.searchOnlineSubtitles();
    engines.single.failControl = true;
    await session.downloadOnlineSubtitle(_Service.result);
    expect(session.onlineSubtitleError, contains('加载失败'));
    expect(session.downloadedOnlineSubtitlePaths, isNotEmpty);
    engines.single.failControl = false;
    await session.downloadOnlineSubtitle(_Service.result);
    expect(service.downloads, 1);
    expect(session.onlineSubtitleError, isNull);
  });
  test('late search cannot publish into the next film; optional key failure leaves keyless search available', () async {
    service.pendingSearch = Completer();
    final pending = session.searchOnlineSubtitles();
    await _until(() => service.searchToken != null);
    await session.open(second);
    expect(() => service.searchToken!.check(), throwsA(isA<ScanCancelled>()));
    service.pendingSearch!.complete(
      const OnlineSubtitleSearch([_Service.result], []),
    );
    await pending;
    expect(session.onlineSubtitleResults, isEmpty);
    service.pendingSearch = null;
    credentials.failRead = true;
    await session.searchOnlineSubtitles();
    expect(service.settings!.apiKey, isEmpty);
    expect(session.onlineSubtitleResults, isNotEmpty);
    expect(session.onlineSubtitleError, contains('设置读取失败'));
  });
  test('switch cancels download, ignores stale result and never attaches to replacement decoder', () async {
    await session.searchOnlineSubtitles();
    service.pendingDownload = Completer();
    final pending = session.downloadOnlineSubtitle(_Service.result);
    await _until(() => service.downloadToken != null);
    await session.open(second);
    expect(() => service.downloadToken!.check(), throwsA(isA<ScanCancelled>()));
    service.pendingDownload!.complete(service.payload);
    await pending;
    expect(engines.last.addedSubtitles, isEmpty);
    expect(await File(p.join(root.path, 'Other.srt')).exists(), isFalse);
    expect(await File(p.join(root.path, 'Film.srt')).exists(), isFalse);
  });
  test(
    'close does not wait for subtitle network and ignores its late completion',
    () async {
      await session.searchOnlineSubtitles();
      service.pendingDownload = Completer();
      final pending = session.downloadOnlineSubtitle(_Service.result);
      await _until(() => service.downloadToken != null);
      await session.close().timeout(const Duration(seconds: 1));
      service.pendingDownload!.complete(service.payload);
      await pending;
      expect(engines.single.disposals, 1);
      expect(engines.single.addedSubtitles, isEmpty);
    },
  );
  test('Emby download stays in owned temporary directory and is removed after decoder release', () async {
    final server = EmbyServerFixture();
    await server.start();
    final client = EmbyClient(deviceId: 'online-subtitle-test');
    final embyCredentials = <String, _Credentials>{};
    final connections = EmbyConnectionRepository(
      sources: sources,
      client: Future.value(client),
      stores: (key) => embyCredentials.putIfAbsent(key, _Credentials.new),
    );
    try {
      final source = await connections.connect(
        server.address,
        'tester',
        'fixture',
      );
      server.catalog['movies'] = [
        {
          'Id': 'film',
          'Name': 'Remote Film',
          'Type': 'Movie',
          'RunTimeTicks': 1000000000,
          'MediaSources': [
            {'Id': 'resource', 'Container': 'mkv'},
          ],
        },
      ];
      await EmbySyncRepository(
        sources: sources,
        connections: connections,
      ).synchronize(source.id);
      await session.close();
      session.dispose();
      final preferences = PlayerPreferencesRepository(sources.database);
      session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        emby: connections,
        onlineSubtitleService: service,
        onlineSubtitleSettings: OnlineSubtitleSettingsRepository(
          preferences,
          store: credentials,
        ),
        createEngine: () {
          final engine = FakeVideoEngine();
          engines.add(engine);
          return engine;
        },
      );
      await runZoned(
        () async {
          await session.open((sourceId: source.id, localId: 'film'));
          expect(session.error, isNull);
          await session.searchOnlineSubtitles();
          await session.downloadOnlineSubtitle(_Service.result);
          final path =
              session.downloadedOnlineSubtitlePaths[_Service.result.id]!;
          expect(p.isWithin(p.join(root.path, 'temp'), path), isTrue);
          expect(await File(path).exists(), isTrue);
          expect(engines.last.addedSubtitles, contains(path));
          await session.close();
          expect(engines.last.disposals, 1);
          expect(await File(path).exists(), isFalse);
        },
        zoneValues: {
          RuntimeStoragePaths.zoneKey: RuntimeStoragePaths(
            root: root,
            portable: true,
          ),
        },
      );
      expect(
        server.requests.any(
          (r) => r.method == 'POST' && r.uri.path.contains('Subtitle'),
        ),
        isFalse,
      );
    } finally {
      connections.dispose();
      client.close();
      await server.close();
    }
  });
}
