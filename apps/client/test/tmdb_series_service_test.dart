import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/tmdb_fixture.dart';

class _Store implements CredentialStore {
  @override
  Future<String?> read() async => 'fixture-key';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox, media, library;
  late SourceRepository sources;
  late TmdbVideoService service;
  late TmdbFixture fixture;
  late MediaSource source;
  late MediaIdentity identity;
  late List<IndexedMedia> children;
  Future<void> file(String name) async {
    final f = File(p.join(media.path, name));
    await f.parent.create(recursive: true);
    await f.writeAsString('video fixture');
  }

  SourceRepository repository() => SourceRepository(
    database: LibraryDatabase(
      NativeDatabase(File(p.join(library.path, 'fixture.sqlite'))),
    ),
    adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
    identityLookup: (_) async => 'fixture-volume',
  );
  TmdbVideoService makeService() => TmdbVideoService(
    sources: sources,
    settings: TmdbSettingsRepository(sources.database, store: _Store()),
    artwork: TmdbArtworkStore(library: () async => library),
    client: fixture.client(),
    kind: TmdbMediaKind.tv,
  );
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-tmdb-series-');
    media = await Directory(p.join(sandbox.path, 'media')).create();
    library = await Directory(p.join(sandbox.path, 'library')).create();
    await file('Show/Season 0/Show.S00E01.mkv');
    await file('Show/Season 1/Show.S01E01.mkv');
    await file('Show/Season 1/Show.S01E02.mkv');
    await file('Show/Season 2/Show.S02E01.mkv');
    sources = repository();
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'TV',
      location: media.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    final all = await sources.indexedSource(source.id);
    identity = all.singleWhere((i) => i.isSeries).identity;
    children = await sources.indexedChildren(identity);
    fixture = await TmdbFixture.start();
    service = makeService();
  });
  tearDown(() async {
    await service.dispose();
    await fixture.close();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-tmdb-series-'));
    await sandbox.delete(recursive: true);
  });
  Future<TmdbCandidate> selected() async =>
      (await service.search('Show')).first;

  test('series match associates only real local episodes including specials and preserves history', () async {
    final child = children.first;
    await sources.database.customStatement(
      '''INSERT INTO playback_states
      (source_id,local_id,position_ms,duration_ms,watched,last_played_at) VALUES(?,?,1234,9000,0,12345)''',
      [child.identity.sourceId, child.identity.localId],
    );
    final oldHistory =
        (await sources.database
                .customSelect('SELECT * FROM playback_states')
                .getSingle())
            .data;
    final result = await service.apply(identity, await selected());
    expect(result.warnings, isEmpty);
    final parent = await sources.media(identity);
    expect(parent.title, '完整剧集 1');
    expect(parent.posterPath, startsWith(TmdbArtworkStore.prefix));
    final detail = (await service.metadata(identity))!;
    expect(detail.candidate.externalId, 'tmdb:tv:1');
    expect(detail.cast.single.role, '角色甲');
    expect(detail.crew.map((c) => c.role), ['主创', '制片']);
    expect(detail.contentRating, 'TV-14');
    expect(
      detail.seasons.singleWhere((s) => s.number == 0).episodes,
      hasLength(3),
    );
    for (final old in children) {
      final item = await sources.media(old.identity);
      expect(item.title, '单集 ${old.seasonNumber}-${old.episodeNumber}');
      expect(
        item.overview,
        'Episode ${old.seasonNumber}-${old.episodeNumber} overview',
      );
      expect(item.identity, old.identity);
      expect(item.parentId, old.parentId);
      expect(item.seasonNumber, old.seasonNumber);
      expect(item.episodeNumber, old.episodeNumber);
      expect(item.bytes, old.bytes);
      expect(item.modified, old.modified);
      expect((await service.episodeMetadata(old.identity))!.runtimeMinutes, 46);
      expect(
        await File(p.join(media.path, old.identity.localId)).readAsString(),
        'video fixture',
      );
    }
    expect(
      await sources.indexedSource(source.id),
      hasLength(children.length + 1),
    );
    expect(
      (await sources.database
              .customSelect('SELECT * FROM playback_states')
              .getSingle())
          .data,
      oldHistory,
    );
    expect(
      (await HomeRepository(sources).recommendationCandidates(source.id))
          .singleWhere((v) => v.item.isSeries)
          .score,
      8.6,
    );
    expect(
      fixture.requests
          .where((u) => u.path.contains('/season/'))
          .map((u) => u.path)
          .toSet(),
      {'/3/tv/1/season/0', '/3/tv/1/season/1', '/3/tv/1/season/2'},
    );
  });
  test('season requests are bounded to two concurrent requests without episode fanout', () async {
    final choice = await selected();
    var active = 0, peak = 0, calls = 0;
    fixture.intercept = (request) async {
      if (request.uri.path == '/3/tv/1') {
        await fixture.json(request, fixture.series(1));
      } else if (request.uri.path.contains('/season/')) {
        active++;
        calls++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await fixture.json(
          request,
          fixture.season(1, int.parse(request.uri.pathSegments.last)),
        );
        active--;
      } else {
        request.response.add(tmdbFixturePng);
        await request.response.close();
      }
    };
    await service.apply(identity, choice);
    expect(calls, 3);
    expect(peak, 2);
    expect(fixture.requests.any((r) => r.path.contains('/episode/')), isFalse);
  });
  test('rescan preserves confirmed series and episode metadata; source removal cascades', () async {
    await service.apply(identity, await selected());
    await sources.scan(source.id);
    expect((await sources.media(identity)).title, '完整剧集 1');
    for (final child in children) {
      expect((await sources.media(child.identity)).title, startsWith('单集'));
      expect(await service.episodeMetadata(child.identity), isNotNull);
    }
    await sources.remove(source.id);
    expect(await service.metadata(identity), isNull);
    expect(await service.episodeMetadata(children.first.identity), isNull);
  });
  test('series/episode metadata and artwork survive database reopening without network', () async {
    await service.apply(identity, await selected());
    final reference = (await sources.media(identity)).posterPath!;
    final client = fixture.client();
    await service.dispose();
    await sources.close();
    await fixture.close();
    sources = repository();
    service = TmdbVideoService(
      sources: sources,
      settings: TmdbSettingsRepository(sources.database, store: _Store()),
      artwork: TmdbArtworkStore(library: () async => library),
      client: client,
      kind: TmdbMediaKind.tv,
    );
    expect((await service.metadata(identity))!.cast.single.name, '演员甲');
    expect(
      (await service.episodeMetadata(children.first.identity))!.seriesId,
      1,
    );
    expect(await (await service.artwork.file(reference)).exists(), isTrue);
    expect(
      (await sources.database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      1,
    );
  });
  test('missing or unknown local season/episode numbers are preserved and reported', () async {
    final child = children.first;
    await sources.database.customStatement(
      'UPDATE media SET season_number=NULL WHERE source_id=? AND local_id=?',
      [child.identity.sourceId, child.identity.localId],
    );
    final result = await service.apply(identity, await selected());
    expect(result.warnings.single, contains('1 个本地单集'));
    expect((await sources.media(child.identity)).title, child.title);
    expect(await service.episodeMetadata(child.identity), isNull);
  });
  test('season failure retains previously matched season and children with warning', () async {
    final choice = await selected();
    await service.apply(identity, choice);
    fixture.intercept = (request) async {
      if (request.uri.path == '/3/tv/1') {
        await fixture.json(request, fixture.series(1));
      } else if (request.uri.path == '/3/tv/1/season/1') {
        request.response.statusCode = 404;
        await request.response.close();
      } else if (request.uri.path.contains('/season/')) {
        await fixture.json(
          request,
          fixture.season(1, int.parse(request.uri.pathSegments.last)),
        );
      } else {
        request.response.add(tmdbFixturePng);
        await request.response.close();
      }
    };
    final result = await service.apply(identity, choice);
    expect(result.warnings, contains(contains('第 1 季')));
    expect(
      (await service.metadata(identity))!.seasons
          .singleWhere((s) => s.number == 1)
          .episodes,
      hasLength(3),
    );
    expect(
      (await sources.media(
        children.firstWhere((c) => c.seasonNumber == 1).identity,
      )).title,
      '单集 1-1',
    );
  });
  test(
    'episode write failure rolls back the entire series match and allows retry',
    () async {
      final old = await sources.media(identity), choice = await selected();
      await sources.database.customStatement(
        '''CREATE TRIGGER fail_series BEFORE INSERT ON local_episode_metadata
      BEGIN SELECT RAISE(FAIL,'secret fixture-key'); END''',
      );
      await expectLater(
        service.apply(identity, choice),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'redacted',
            isNot(contains('fixture-key')),
          ),
        ),
      );
      expect((await sources.media(identity)).title, old.title);
      expect(await service.metadata(identity), isNull);
      expect(await service.episodeMetadata(children.first.identity), isNull);
      await sources.database.customStatement('DROP TRIGGER fail_series');
      await service.apply(identity, choice);
      expect(await service.metadata(identity), isNotNull);
    },
  );
  test('concurrent season numbering change rejects the pending complete transaction', () async {
    final choice = await selected(), gate = Completer<void>();
    fixture.detailGate = gate.future;
    final work = service.apply(identity, choice);
    await fixture.detailStarted.future;
    await sources.database.customStatement(
      'UPDATE media SET episode_number=99 WHERE source_id=? AND local_id=?',
      [children.first.identity.sourceId, children.first.identity.localId],
    );
    gate.complete();
    await expectLater(
      work,
      throwsA(
        isA<SourceFailure>().having((e) => e.message, 'stale', contains('已更改')),
      ),
    );
    expect(await service.metadata(identity), isNull);
  });
  test(
    'adding an episode during matching rejects stale series snapshot',
    () async {
      final choice = await selected(), gate = Completer<void>();
      fixture.detailGate = gate.future;
      final work = service.apply(identity, choice);
      await fixture.detailStarted.future;
      await file('Show/Season 1/Show.S01E03.mkv');
      await sources.scan(source.id);
      gate.complete();
      await expectLater(work, throwsA(isA<SourceFailure>()));
      expect(await service.metadata(identity), isNull);
    },
  );
  test(
    'rescan drops episode association when season numbering changes',
    () async {
      final child = children.firstWhere(
        (c) => c.seasonNumber == 1 && c.episodeNumber == 1,
      );
      await service.apply(identity, await selected());
      await sources.database.customStatement(
        'UPDATE media SET episode_number=99 WHERE source_id=? AND local_id=?',
        [child.identity.sourceId, child.identity.localId],
      );
      await sources.scan(source.id);
      expect(await service.episodeMetadata(child.identity), isNull);
      expect(
        (await sources.media(child.identity)).title,
        isNot(startsWith('单集')),
      );
      expect((await sources.media(child.identity)).overview, isNull);
    },
  );
  test('series reclassification clears cascaded episode descriptions without losing local images', () async {
    final child = children.first;
    await sources.database.customStatement(
      'UPDATE media SET poster_path=? WHERE source_id=? AND local_id=?',
      ['local-cover.jpg', child.identity.sourceId, child.identity.localId],
    );
    await service.apply(identity, await selected());
    await sources.updateSettings(source.id, mediaType: SourceMediaType.anime);
    await sources.scan(source.id);
    expect(await service.metadata(identity), isNull);
    for (final old in children) {
      expect(await service.episodeMetadata(old.identity), isNull);
      final item = await sources.media(old.identity);
      expect(item.overview, isNull);
      expect(item.year, isNull);
      expect(item.title, isNot(startsWith('单集')));
    }
    expect((await sources.media(child.identity)).posterPath, 'local-cover.jpg');
  });
  test('wrong candidate kind, individual episode and Emby are rejected before HTTP', () async {
    final choice = await selected(), count = fixture.requests.length;
    await expectLater(
      service.apply(identity, const TmdbCandidate(id: 1, title: 'movie')),
      throwsA(isA<SourceFailure>()),
    );
    await expectLater(
      service.apply(children.first.identity, choice),
      throwsA(isA<SourceFailure>()),
    );
    await sources.database.customStatement("UPDATE sources SET kind='emby'");
    await expectLater(
      service.apply(identity, choice),
      throwsA(isA<SourceFailure>()),
    );
    expect(fixture.requests, hasLength(count));
  });
  test(
    'shutdown cancels series work without persisting partial associations',
    () async {
      final choice = await selected(), gate = Completer<void>();
      fixture.detailGate = gate.future;
      final work = expectLater(
        service.apply(identity, choice),
        throwsA(isA<SourceFailure>()),
      );
      await fixture.detailStarted.future;
      await service.dispose().timeout(const Duration(seconds: 1));
      gate.complete();
      await work;
      expect(await service.metadata(identity), isNull);
      expect(await service.episodeMetadata(children.first.identity), isNull);
    },
  );
  test(
    'stored episode DTO is token free and round trips season identity',
    () async {
      await service.apply(identity, await selected());
      final rows = await sources.database
          .customSelect('SELECT value FROM local_episode_metadata')
          .get();
      expect(rows, hasLength(4));
      for (final row in rows) {
        final value = row.read<String>('value');
        expect(value, isNot(contains('fixture-key')));
        final dto = TmdbEpisodeMetadata.fromJson(
          jsonDecode(value) as Map<String, dynamic>,
        );
        expect(dto.seriesId, 1);
        expect(dto.episodeNumber, greaterThan(0));
      }
    },
  );
}
