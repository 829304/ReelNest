import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_detail.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/home/application/home_search_providers.dart';
import 'package:reelnest/features/home/data/home_repository.dart';
import 'package:reelnest/features/home/data/home_search_worker.dart';
import 'package:reelnest/features/home/domain/home_search.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/query_counter.dart';

class _DelayedSearch extends HomeRepository {
  _DelayedSearch(super.sources);
  final waiting = <String, Completer<List<HomeVideo>>>{};
  final cancelled = <String>{};
  @override
  Future<List<HomeVideo>> search(
    String id,
    String query, {
    required String scope,
    required ScanCancellation cancellation,
  }) {
    if (id != 'slow') {
      return super.search(id, query, scope: scope, cancellation: cancellation);
    }
    cancellation.listen(() => cancelled.add(query));
    return (waiting[query] ??= Completer<List<HomeVideo>>()).future;
  }
}

Never _waitForCancellation(SendPort ready) {
  ready.send(true);
  while (true) {
    /* The cancellation must kill the worker, not just drop data. */
  }
}

int Function() _cancellationWork(SendPort ready) =>
    () => _waitForCancellation(ready);

void main() {
  late SourceRepository sources;
  late HomeRepository home;
  late QueryCounter counter;
  late MediaSource local, remote;
  Future<MediaSource> add(
    String id, {
    String kind = 'localFolder',
    String mediaType = 'auto',
    bool scanned = true,
  }) async {
    await sources.add(
      sourceId: id,
      kind: MediaSourceKind.emby,
      name: id,
      location: 'emby://fixture/$id',
    );
    await sources.database.customStatement(
      'UPDATE sources SET kind=?,media_type=?,last_scan=? WHERE id=?',
      [kind, mediaType, scanned ? 1 : null, id],
    );
    return sources.source(id, includeCounts: false);
  }

  Future<void> seed(
    MediaSource source,
    String id, {
    String? title,
    String type = 'movie',
    String? parent,
    String? library,
    String? original,
    String? overview,
    int? year,
    int? season,
    int? episode,
    Map<String, dynamic>? detail,
  }) async {
    await sources.database.customStatement(
      '''INSERT INTO media(
      source_id,local_id,title,type,bytes,modified,identity_kind,parent_id,
      is_series,original_title,overview,year,season_number,episode_number)
      VALUES (?,?,?,?,0,1,'video',?,?,?,?,?,?,?)''',
      [
        source.id,
        id,
        title ?? id,
        type,
        parent,
        type == 'tvShow' ? 1 : 0,
        original,
        overview,
        year,
        season,
        episode,
      ],
    );
    if (source.kind == MediaSourceKind.emby) {
      await sources.database.customStatement(
        'INSERT INTO remote_media_metadata VALUES (?,?,?)',
        [
          source.id,
          id,
          jsonEncode({
            'externalId': id,
            'libraryId': library,
            'genres': ['冒险'],
            'videoCodec': 'hevc',
            'audioCodec': 'aac',
            'resolution': '3840x2160',
          }),
        ],
      );
    }
    if (detail != null) {
      await sources.database.customStatement(
        'INSERT INTO remote_media_details VALUES (?,?,?,1)',
        [source.id, id, jsonEncode(EmbyDetail.fromServer(detail, id).toJson())],
      );
    }
  }

  Future<List<HomeVideo>> search(MediaSource source, String query) =>
      home.search(
        source.id,
        query,
        scope: homeSearchScope(source),
        cancellation: ScanCancellation(),
      );
  HomeSearchKey key(String query, List<MediaSource> values) => (
    query: query,
    scope: values.where(HomeRepository.accepts).map(homeSearchScope).join('\n'),
  );

  setUp(() async {
    counter = QueryCounter();
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory().interceptWith(counter)),
      adapters: {},
    );
    home = HomeRepository(sources);
    local = await add('local');
    remote = await add('remote', kind: 'emby', scanned: false);
  });
  tearDown(() => sources.close());

  test(
    'queries reuse decoded documents, writes and deletion invalidate them',
    () async {
      await seed(
        local,
        'film',
        title: '北京故事',
        detail: {
          'Id': 'film',
          'People': [
            {'Name': 'Actor Original', 'Type': 'Actor'},
          ],
        },
      );
      counter.reads.clear();
      final first = await search(local, '北京');
      expect(await search(local, 'bjgs'), hasLength(1));
      final actor = await search(local, 'Actor Original');
      expect(identical(first.single, actor.single), isTrue);
      expect(
        counter.reads.where((r) => r.sql.contains('d.value AS details')),
        hasLength(1),
      );
      await sources.database.customStatement(
        'UPDATE remote_media_details SET value=?',
        [
          jsonEncode(
            EmbyDetail.fromServer({
              'Id': 'film',
              'People': [
                {'Name': 'New Actor', 'Type': 'Actor'},
              ],
            }, 'film').toJson(),
          ),
        ],
      );
      expect(await search(local, 'Actor Original'), isEmpty);
      expect(await search(local, 'New Actor'), hasLength(1));
      expect(
        counter.reads.where((r) => r.sql.contains('d.value AS details')),
        hasLength(2),
      );
      await sources.database.customStatement(
        "DELETE FROM media WHERE local_id='film'",
      );
      expect(await search(local, '北京'), isEmpty);
    },
  );

  test(
    'search cache evicts least recently used source after four sources',
    () async {
      final values = [
        local,
        remote,
        await add('third'),
        await add('fourth'),
        await add('fifth'),
      ];
      for (final source in values) {
        await seed(source, 'film', title: 'Story');
      }
      counter.reads.clear();
      for (final source in values) {
        expect(await search(source, 'Story'), hasLength(1));
      }
      await search(values.last, 'story');
      expect(
        counter.reads.where((r) => r.sql.contains('d.value AS details')),
        hasLength(5),
      );
      await search(local, 'Story');
      expect(
        counter.reads.where((r) => r.sql.contains('d.value AS details')),
        hasLength(6),
      );
    },
  );

  test(
    'commits from another SQLite connection invalidate cached search documents',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'reelnest-search-',
      );
      final file = File('${directory.path}/library.sqlite');
      final firstDb = LibraryDatabase(NativeDatabase(file));
      final otherDb = LibraryDatabase(NativeDatabase(file));
      final repo = SourceRepository(database: firstDb, adapters: {});
      addTearDown(() async {
        await otherDb.close();
        await repo.close();
        await directory.delete(recursive: true);
      });
      await repo.add(
        sourceId: 'external',
        kind: MediaSourceKind.emby,
        name: 'External',
        location: 'emby://fixture/external',
      );
      await firstDb.customStatement(
        "INSERT INTO media(source_id,local_id,title,type,bytes,modified,identity_kind) VALUES('external','film','Before','movie',0,0,'fixture')",
      );
      await otherDb.customSelect('SELECT 1').get();
      final source = await repo.source('external', includeCounts: false);
      final repository = HomeRepository(repo);
      Future<List<HomeVideo>> query(String q) => repository.search(
        source.id,
        q,
        scope: homeSearchScope(source),
        cancellation: ScanCancellation(),
      );
      expect(await query('Before'), hasLength(1));
      await otherDb.customStatement(
        "UPDATE media SET title='After' WHERE local_id='film'",
      );
      expect(await query('Before'), isEmpty);
      expect(await query('After'), hasLength(1));
    },
  );

  test('large decoded index is reused across query workers', () async {
    await sources.database.customStatement('''WITH RECURSIVE n(i) AS
      (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<2000)
      INSERT INTO media(source_id,local_id,title,type,bytes,modified,identity_kind)
      SELECT 'local','film'||i,'Movie '||i,'movie',0,1,'fixture' FROM n''');
    counter.reads.clear();
    expect(await search(local, 'Movie'), hasLength(2000));
    expect(await search(local, 'Movie 2000'), hasLength(1));
    expect(await search(local, 'no match'), isEmpty);
    final reads = counter.reads.where(
      (r) => r.sql.contains('d.value AS details'),
    );
    expect(reads, hasLength(1));
    expect(reads.single.rows, 2000);
  });

  test('oversized search documents are searchable but not retained', () async {
    await seed(
      local,
      'large',
      title: 'Large',
      overview: 'x' * (8 * 1024 * 1024 + 1),
    );
    counter.reads.clear();
    expect(await search(local, 'Large'), hasLength(1));
    expect(await search(local, 'Large'), hasLength(1));
    expect(
      counter.reads.where((r) => r.sql.contains('d.value AS details')),
      hasLength(2),
    );
  });

  test(
    'Chinese, original title, English initials, pinyin, year and overview',
    () async {
      await seed(
        local,
        'film',
        title: '贝加尔湖',
        original: 'Breaking Bad',
        overview: '湖畔的一段旅程',
        year: 2024,
      );
      for (final query in [
        '贝加尔',
        'beijiaer',
        'bje',
        'BREAKING',
        'bb',
        '2024',
        '旅程',
      ]) {
        expect(
          (await search(local, query)).single.item.identity.localId,
          'film',
          reason: query,
        );
      }
      expect(await search(local, '不存在'), isEmpty);
      expect(await search(local, '  '), isEmpty);
    },
  );

  test(
    'cached cast, roles, crew, networks, companies and technical fields',
    () async {
      await seed(
        remote,
        'film',
        title: '测试影片',
        detail: {
          'Id': 'film',
          'People': [
            {'Id': 'actor', 'Name': '李连杰', 'Role': '黄飞鸿', 'Type': 'Actor'},
            {'Name': '徐克', 'Type': 'Director'},
          ],
          'Studios': [
            {'Name': '电影工作室'},
          ],
          'Networks': [
            {'Name': '测试电视网'},
          ],
          'ProductionLocations': ['中国'],
          'Genres': ['武侠'],
          'Status': 'Ended',
          'OfficialRating': 'PG-13',
          'PremiereDate': '1991-08-15',
          'OriginalLanguage': 'zh',
          'ProviderIds': {'Tmdb': '1234', 'Imdb': 'tt4567'},
        },
      );
      for (final query in [
        'lianjie',
        'llj',
        '黄飞鸿',
        '徐克',
        'Director',
        '电影工作室',
        '测试电视网',
        '中国',
        '武侠',
        'Ended',
        'PG-13',
        '1991',
        'zh',
        '1234',
        'tt4567',
        'hevc',
        'aac',
        '3840',
        '冒险',
      ]) {
        expect(await search(remote, query), hasLength(1), reason: query);
      }
      await sources.database.customStatement(
        'DELETE FROM remote_media_details',
      );
      expect(await search(remote, '黄飞鸿'), isEmpty);
    },
  );

  test('episode title and season/episode label return its parent, never episode rows', () async {
    await seed(local, 'series', title: '电视剧', type: 'tvShow');
    await seed(
      local,
      'episode',
      title: '重返故乡',
      type: 'episode',
      parent: 'series',
      season: 2,
      episode: 3,
    );
    for (final query in ['重返故乡', 'guxiang', 'S02E03', '第 2 季', '第 3 集']) {
      expect(
        (await search(local, query)).single.item.identity.localId,
        'series',
        reason: query,
      );
    }
  });

  test('scope excludes private descendants, photos, music and unselected libraries', () async {
    await seed(remote, 'allowed', title: '同名', library: 'a');
    await seed(remote, 'excluded', title: '同名', library: 'b');
    await seed(
      remote,
      'vault',
      title: '同名',
      type: 'privateCollection',
      library: 'a',
    );
    await seed(remote, 'secret', title: '同名', parent: 'vault', library: 'a');
    await seed(remote, 'photo', title: '同名', type: 'photo', library: 'a');
    await seed(remote, 'music', title: '同名', type: 'music', library: 'a');
    await sources.database.customStatement(
      'UPDATE sources SET options=? WHERE id=?',
      [
        jsonEncode({
          'selectedEmbyLibraryIDs': ['a'],
        }),
        remote.id,
      ],
    );
    expect(
      await search(remote, '同名'),
      isEmpty,
      reason: 'old source configuration rejected',
    );
    final selected = await sources.source(remote.id, includeCounts: false);
    expect(
      (await search(selected, '同名')).single.item.identity.localId,
      'allowed',
    );
    final private = await add('private', mediaType: 'privateCollection');
    await seed(private, 'public-looking', title: '同名');
    expect(await search(private, '同名'), isEmpty);
  });

  test(
    'background matching groups, natural title order and cross-source IDs',
    () async {
      for (var n = 0; n < 190; n++) {
        await seed(local, 'film$n', title: '影片$n');
      }
      await seed(remote, 'film2', title: '影片2');
      await seed(remote, 'series', title: '影片系列', type: 'tvShow');
      final results = [
        ...await search(local, '影片'),
        ...await search(remote, '影片'),
      ];
      final state = HomeSearchState.merge(
        results,
        loading: false,
        partial: true,
        errors: {},
      );
      expect(state.count, 192);
      expect(state.groups.keys, [
        HomeSearchGroup.movie,
        HomeSearchGroup.tvShow,
      ]);
      expect(
        state.groups[HomeSearchGroup.movie]!.take(5).map((v) => v.item.title),
        ['影片0', '影片1', '影片2', '影片2', '影片3'],
      );
      expect(state.partial, isTrue);
    },
  );

  test('cancelled search never returns results', () async {
    final token = ScanCancellation()..cancel();
    await expectLater(
      home.search(
        local.id,
        'any',
        scope: homeSearchScope(local),
        cancellation: token,
      ),
      throwsA(isA<ScanCancelled>()),
    );
  });

  test(
    'cancelling an active search terminates its worker and settles the future',
    () async {
      final ready = ReceivePort();
      final send = ready.sendPort;
      final token = ScanCancellation();
      addTearDown(() {
        token.cancel();
        ready.close();
      });
      final future = runHomeSearchWorker<int>(_cancellationWork(send), token);
      final checked = expectLater(future, throwsA(isA<ScanCancelled>()));
      await ready.first.timeout(const Duration(seconds: 5));
      token.cancel();
      await checked.timeout(const Duration(seconds: 5));
    },
  );

  test(
    'background worker exceptions propagate instead of hanging search',
    () async {
      await expectLater(
        runHomeSearchWorker<int>(
          () => throw StateError('fixture'),
          ScanCancellation(),
        ),
        throwsA(isA<RemoteError>()),
      );
    },
  );

  test(
    'large provider result assembly also runs outside the UI isolate',
    () async {
      for (var n = 0; n < 185; n++) {
        await seed(local, '影片$n');
      }
      final container = ProviderContainer.test(
        overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
      );
      final provider = homeSearchProvider(key('影片', [local, remote]));
      container.listen(provider, (_, _) {});
      for (var n = 0; n < 100; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await container.pump();
        final state = container.read(provider);
        if (state.value?.count == 185 && state.value?.loading == false) break;
      }
      expect(container.read(provider).hasError, isFalse);
      expect(container.read(provider).value?.count, 185);
      container.dispose();
    },
  );

  test('independent sources publish hits before slow source; retired query is discarded', () async {
    final slow = await add('slow', kind: 'emby', scanned: false);
    await seed(local, 'first', title: 'first');
    await seed(local, 'second', title: 'second');
    final delayed = _DelayedSearch(sources);
    final container = ProviderContainer.test(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        homeRepositoryProvider.overrideWithValue(delayed),
      ],
    );
    final all = [local, remote, slow];
    final old = homeSearchProvider(key('first', all));
    final subscription = container.listen(old, (_, _) {});
    await container.pump();
    for (var n = 0; n < 15 && container.read(old).value?.count != 1; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await container.pump();
    }
    expect(container.read(old).value?.count, 1);
    expect(container.read(old).value?.loading, isTrue);
    expect(container.read(old).value?.partial, isTrue);
    subscription.close();
    final next = homeSearchProvider(key('second', all));
    container.listen(next, (_, _) {});
    await container.pump();
    for (var n = 0; n < 15 && container.read(next).value?.count != 1; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await container.pump();
    }
    expect(delayed.cancelled, contains('first'));
    delayed.waiting['first']!.complete(await search(local, 'first'));
    delayed.waiting['second']!.completeError(const SourceFailure('离线'));
    await container.pump();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await container.pump();
    final state = container.read(next).value!;
    expect(state.groups.values.single.single.item.title, 'second');
    expect(state.loading, isFalse);
    expect(state.errors['slow'], contains('离线'));
    container.dispose();
  });
}
