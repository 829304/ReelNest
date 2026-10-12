import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/data/emby_browse_repository.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_detail_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/secure_credential_store.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

/// Credentials stay in process memory. Refreshes never overwrite the saved login.
class _TransientCredential implements CredentialStore {
  _TransientCredential(this.value);
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('REELNEST_EMBY_LIVE');
  testWidgets(
    'saved Emby: cold first page, actor works and series on an isolated index',
    (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('Emby 连接验证'))),
        ),
      );
      final existing = SourceRepository(
        database: LibraryDatabase.open(),
        adapters: {},
      );
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-live-browse-',
      );
      final sources = SourceRepository(
        database: LibraryDatabase(
          NativeDatabase.createInBackground(
            File('${sandbox.path}/library.sqlite'),
          ),
        ),
        adapters: {},
      );
      EmbyClient? client;
      EmbyConnectionRepository? connections;
      try {
        final configured = (await existing.sources())
            .where((s) => s.kind == MediaSourceKind.emby)
            .toList();
        expect(configured, isNotEmpty, reason: '请先在正式应用中登录 Emby；测试不会创建或清除登录。');
        final keys = (await const FlutterSecureStorage().readAll()).keys;
        final embyKeys = keys.where(
          (key) => key.startsWith('io.github.user829304.reelnest.emby.source.'),
        );
        debugPrint(
          'LIVE_STORAGE platform=${defaultTargetPlatform.name} keys=${keys.length} embyKeys=${embyKeys.length}',
        );
        final available = <({MediaSource source, String raw})>[];
        for (final candidate in configured) {
          final stored = await SecureCredentialStore(
            key: 'io.github.user829304.reelnest.emby.source.${candidate.id}',
          ).read();
          if (stored != null) available.add((source: candidate, raw: stored));
        }
        debugPrint(
          'LIVE_EMBY_CONFIGURED sources=${configured.length} saved=${available.length}',
        );
        expect(available, isNotEmpty, reason: '已配置来源均没有可读取的登录凭据。');
        final saved = available.first.source;
        final raw = available.first.raw;
        final credential = _TransientCredential(raw);
        client = EmbyClient(
          deviceId: await embyDeviceIdentity(existing.database),
        );
        final source = await sources.add(
          sourceId: saved.id,
          kind: MediaSourceKind.emby,
          name: saved.name,
          location: saved.location,
          minimumFileSize: 0,
          options: saved.options,
        );
        connections = EmbyConnectionRepository(
          sources: sources,
          client: Future.value(client),
          stores: (_) => credential,
        );
        final browse = EmbyBrowseRepository(sources, connections);
        final watch = Stopwatch()..start();
        final views = await browse.catalog(source.id, ScanCancellation());
        debugPrint(
          'LIVE_EMBY_VIEWS count=${views.length} ms=${watch.elapsedMilliseconds}',
        );
        watch.reset();
        final cursor = await browse.open(
          source.id,
          cancellation: ScanCancellation(),
        );
        final items = await cursor.next();
        debugPrint(
          'LIVE_EMBY_FIRST_PAGE count=${items.length} ms=${watch.elapsedMilliseconds}',
        );
        expect(items, isNotEmpty);
        expect(items.length, lessThanOrEqualTo(60));
        expect((await sources.source(source.id)).lastScan, isNull);
        final details = EmbyDetailRepository(
          sources: sources,
          connections: connections,
        );
        var checkedPerson = false;
        for (final item in items.take(5)) {
          final detail = await details.load(item.identity);
          if (detail.detail.people.isEmpty) continue;
          watch.reset();
          final works = await details.personWorks(
            source.id,
            detail.detail.people.first.key,
          );
          debugPrint(
            'LIVE_EMBY_PERSON_WORKS count=${works.length} ms=${watch.elapsedMilliseconds}',
          );
          expect(works, isNotEmpty);
          checkedPerson = true;
          break;
        }
        expect(checkedPerson, isTrue, reason: '首屏前五项没有人物资料，需另选带演员信息的内容验证。');
        final series = items.where((i) => i.isSeries).firstOrNull;
        if (series != null) {
          watch.reset();
          await browse.loadEpisodes(series.identity, ScanCancellation());
          final seasons = await sources.seasons(series.identity);
          debugPrint(
            'LIVE_EMBY_SERIES episodes=${seasons.fold<int>(0, (n, s) => n + s.episodeCount)} ms=${watch.elapsedMilliseconds}',
          );
        }
      } finally {
        connections?.dispose();
        client?.close();
        await sources.close();
        await existing.close();
        await sandbox.delete(recursive: true);
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
