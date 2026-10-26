import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/application/tmdb_providers.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/tmdb_fixture.dart';

class _Store implements CredentialStore {
  String? value = 'fixture-key';
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> clear() async {
    if (fail) throw StateError('private fixture-key');
    value = null;
  }

  @override
  Future<void> write(String next) async {
    if (fail) throw StateError('private fixture-key');
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox, media, library;
  late SourceRepository sources;
  late TmdbSettingsRepository settings;
  late TmdbVideoService service;
  late TmdbArtworkStore artwork;
  late _Store store;
  late TmdbFixture fixture;
  late MediaSource source;
  late MediaIdentity identity;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-tmdb-');
    media = await Directory(p.join(sandbox.path, 'media')).create();
    library = await Directory(p.join(sandbox.path, 'library')).create();
    await File(p.join(media.path, 'Film.2020.mkv')).writeAsString('fixture');
    sources = SourceRepository(
      database: LibraryDatabase(
        NativeDatabase(File(p.join(library.path, 'fixture.sqlite'))),
      ),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Movies',
      location: media.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    identity = (sourceId: source.id, localId: 'Film.2020.mkv');
    store = _Store();
    settings = TmdbSettingsRepository(sources.database, store: store);
    artwork = TmdbArtworkStore(library: () async => library);
    fixture = await TmdbFixture.start();
    service = TmdbVideoService(
      sources: sources,
      settings: settings,
      client: fixture.client(),
      artwork: artwork,
    );
  });
  tearDown(() async {
    await service.dispose();
    await fixture.close();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-tmdb-'));
    await sandbox.delete(recursive: true);
  });
  Future<TmdbCandidate> selected() async =>
      (await service.search('Film')).first;

  test('match saves title, offline artwork, cast and detail atomically, with scoped refresh', () async {
    final original = await sources.media(identity),
        revision = sources.sourceContentRevision(source.id);
    final result = await service.apply(identity, await selected());
    expect(result.warnings, isEmpty);
    final item = await sources.media(identity),
        detail = await service.metadata(identity);
    expect(item.title, '完整电影 1');
    expect(item.overview, 'Detailed overview');
    expect(item.originalTitle, 'Film 1');
    expect(item.year, 2020);
    expect(item.identity, original.identity);
    expect(item.remote, isNull);
    expect(item.bytes, original.bytes);
    expect(item.modified, original.modified);
    expect(item.posterPath, startsWith(TmdbArtworkStore.prefix));
    expect(
      await (await artwork.file(item.posterPath!)).readAsBytes(),
      tmdbFixturePng,
    );
    expect(detail!.runtimeMinutes, 125);
    expect(detail.cast.first.name, '甲');
    expect(sources.sourceContentRevision(source.id), isNot(revision));
    final stored = await sources.database
        .customSelect('SELECT value FROM local_movie_metadata')
        .getSingle();
    expect(stored.read<String>('value'), isNot(contains('fixture-key')));
    expect(
      await File(p.join(media.path, 'Film.2020.mkv')).readAsString(),
      'fixture',
    );
    expect(await media.list().length, 1);
    for (final table in ['playback_states', 'playback_markers']) {
      expect(
        (await sources.database
                .customSelect('SELECT COUNT(*) AS n FROM $table')
                .getSingle())
            .read<int>('n'),
        0,
      );
    }
    final card = (await HomeRepository(
      sources,
    ).recommendationCandidates(source.id)).single;
    expect(card.score, 8.2);
  });
  test('rescan retains confirmed matching over sidecar changes and cascades on removal', () async {
    await service.apply(identity, await selected());
    await File(
      p.join(media.path, 'Film.2020.nfo'),
    ).writeAsString('<title>Another NFO title</title><plot>Other plot</plot>');
    await sources.scan(source.id);
    expect((await sources.media(identity)).title, '完整电影 1');
    expect((await sources.media(identity)).overview, 'Detailed overview');
    expect((await service.metadata(identity))!.candidate.id, 1);
    await sources.remove(source.id);
    expect(await service.metadata(identity), isNull);
  });
  test(
    'saved detail and portable artwork references survive reopening database',
    () async {
      await service.apply(identity, await selected());
      final json =
          (await sources.database
                  .customSelect('SELECT value FROM local_movie_metadata')
                  .getSingle())
              .read<String>('value');
      final restored = TmdbMetadata.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      expect(restored.cast.first.name, '甲');
      expect(restored.candidate.title, '完整电影 1');
      final reference = (await sources.media(identity)).posterPath!;
      await service.dispose();
      await sources.close();
      sources = SourceRepository(
        database: LibraryDatabase(
          NativeDatabase(File(p.join(library.path, 'fixture.sqlite'))),
        ),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      settings = TmdbSettingsRepository(sources.database, store: store);
      service = TmdbVideoService(
        sources: sources,
        settings: settings,
        client: fixture.client(),
        artwork: artwork,
      );
      expect((await service.metadata(identity))!.cast.first.name, '甲');
      expect((await sources.media(identity)).posterPath, reference);
      expect(await (await artwork.file(reference)).exists(), isTrue);
      expect(
        (await sources.database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        1,
      );
    },
  );
  test(
    'detail failure uses selected search data and clearly reports fallback',
    () async {
      final choice = await selected();
      fixture.failDetail = true;
      final result = await service.apply(identity, choice);
      expect(result.warnings.single, contains('搜索资料'));
      expect((await sources.media(identity)).title, choice.title);
      expect((await service.metadata(identity))!.cast, isEmpty);
    },
  );
  test('artwork failure preserves existing image and does not store remote URL as file', () async {
    await sources.database.customStatement(
      'UPDATE media SET poster_path=?,backdrop_path=?',
      ['cover.jpg', 'fanart.jpg'],
    );
    final choice = await selected();
    fixture.failImages = true;
    final result = await service.apply(identity, choice);
    expect(result.warnings, hasLength(2));
    expect((await sources.media(identity)).posterPath, 'cover.jpg');
    expect((await sources.media(identity)).backdropPath, 'fanart.jpg');
  });
  test('database failure rolls back all metadata and permits retry', () async {
    final before = await sources.media(identity), choice = await selected();
    await sources.database.customStatement(
      '''CREATE TRIGGER fail_tmdb BEFORE INSERT ON local_movie_metadata
      BEGIN SELECT RAISE(FAIL,'private fixture-key'); END''',
    );
    await expectLater(
      service.apply(identity, choice),
      throwsA(
        isA<SourceFailure>().having(
          (e) => e.message,
          'safe',
          isNot(contains('fixture-key')),
        ),
      ),
    );
    expect((await sources.media(identity)).title, before.title);
    expect((await sources.media(identity)).posterPath, before.posterPath);
    expect(await service.metadata(identity), isNull);
    await sources.database.customStatement('DROP TRIGGER fail_tmdb');
    await service.apply(identity, choice);
    expect((await sources.media(identity)).title, '完整电影 1');
    final directory = Directory(p.join(library.path, 'metadata-artwork'));
    expect(
      await directory.list().any((e) => e.path.contains('.part-')),
      isFalse,
    );
  });
  test('duplicate apply is rejected and file replacement during fetch cannot commit', () async {
    final choice = await selected(), gate = Completer<void>();
    fixture.detailGate = gate.future;
    final pending = service.apply(identity, choice);
    await fixture.detailStarted.future;
    await expectLater(
      service.apply(identity, choice),
      throwsA(isA<SourceFailure>()),
    );
    await sources.database.customStatement('UPDATE media SET bytes=bytes+1');
    gate.complete();
    await expectLater(
      pending,
      throwsA(
        isA<SourceFailure>().having(
          (e) => e.message,
          'changed',
          contains('已更改'),
        ),
      ),
    );
    expect(await service.metadata(identity), isNull);
  });
  test(
    'removing source during request never recreates source or media',
    () async {
      final choice = await selected(), gate = Completer<void>();
      fixture.detailGate = gate.future;
      final pending = service.apply(identity, choice);
      await fixture.detailStarted.future;
      await sources.remove(source.id);
      gate.complete();
      await expectLater(pending, throwsA(isA<SourceFailure>()));
      expect(await sources.sources(), isEmpty);
    },
  );
  test(
    'shutdown cancels pending search and apply before database close',
    () async {
      final choice = await selected(), gate = Completer<void>();
      fixture.detailGate = gate.future;
      final pending = expectLater(
        service.apply(identity, choice),
        throwsA(isA<SourceFailure>()),
      );
      await fixture.detailStarted.future;
      await service.dispose().timeout(const Duration(seconds: 1));
      await pending;
      gate.complete();
      expect(await service.metadata(identity), isNull);
      await expectLater(service.search('Film'), throwsA(isA<SourceFailure>()));
    },
  );
  test(
    'unconfigured credential blocks application and leaves original metadata',
    () async {
      final choice = await selected();
      await settings.saveCredential('');
      await expectLater(
        service.apply(identity, choice),
        throwsA(isA<SourceFailure>()),
      );
      expect(await service.metadata(identity), isNull);
    },
  );
  test('Emby is rejected before fetching public metadata', () async {
    final choice = await selected();
    final count = fixture.requests.length;
    await sources.database.customStatement("UPDATE sources SET kind='emby'");
    await expectLater(
      service.apply(identity, choice),
      throwsA(isA<SourceFailure>()),
    );
    expect(fixture.requests.length, count);
  });
  test('series cannot be matched through the local movie service', () async {
    final choice = await selected();
    final count = fixture.requests.length;
    await sources.database.customStatement('UPDATE media SET is_series=1');
    await expectLater(
      service.apply(identity, choice),
      throwsA(isA<SourceFailure>()),
    );
    expect(fixture.requests.length, count);
    expect(await service.metadata(identity), isNull);
  });
  test('artwork rejects invalid bytes and escaping references without publishing files', () async {
    await expectLater(
      artwork.save(tmdbFixturePng.sublist(0, 8)),
      throwsA(anything),
    );
    await expectLater(
      artwork.file('metadata-artwork:../../escape.png'),
      throwsA(isA<SourceFailure>()),
    );
    expect(
      await Directory(p.join(library.path, 'metadata-artwork')).exists(),
      isFalse,
    );
  });
  test('settings serialize edits, keep credentials out of SQLite, and retain old state on failure', () async {
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        tmdbSettingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
    await container.read(tmdbSettingsProvider.future);
    final controller = container.read(tmdbSettingsProvider.notifier);
    await Future.wait([
      controller.setLanguage('en-US'),
      controller.saveCredential('new.fixture.token'),
    ]);
    expect((await settings.read()).language, 'en-US');
    expect(store.value, 'new.fixture.token');
    final rows = await sources.database
        .customSelect('SELECT value FROM player_preferences')
        .get();
    expect(
      rows.map((r) => r.read<String>('value')).join(),
      isNot(contains('new.fixture.token')),
    );
    store.fail = true;
    await expectLater(
      controller.saveCredential('bad'),
      throwsA(isA<SourceFailure>()),
    );
    expect(store.value, 'new.fixture.token');
    expect(
      container.read(tmdbSettingsProvider).requireValue.hasCredential,
      isTrue,
    );
    store.fail = false;
    await controller.saveCredential('');
    expect(
      container.read(tmdbSettingsProvider).requireValue.hasCredential,
      isFalse,
    );
    await controller.setLanguage(' ');
    expect((await settings.read()).language, 'zh-CN');
  });
}
