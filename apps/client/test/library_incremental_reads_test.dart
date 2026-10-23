import 'dart:collection';
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/home/application/home_providers.dart';
import 'package:reelnest/features/home/domain/home_snapshot.dart';
import 'package:reelnest/features/sources/application/emby_library_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_detail_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/query_counter.dart';

void main() {
  late SourceRepository sources;
  late LibraryDatabase db;
  late QueryCounter counter;
  setUp(() async {
    counter = QueryCounter();
    db = LibraryDatabase(NativeDatabase.memory().interceptWith(counter));
    sources = SourceRepository(database: db, adapters: {});
    for (final id in ['a', 'b']) {
      await db.customStatement(
        '''INSERT INTO sources
        (id,kind,name,location,location_key,recursive,ignore_hidden,created_at,updated_at)
        VALUES (?, 'emby', ?, ?, ?, 1, 1, 0, 0)''',
        [id, id, 'emby://fixture/$id', id],
      );
    }
  });
  tearDown(() => sources.close());

  Future<void> item(
    String id, {
    String source = 'a',
    String? parent,
    String type = 'movie',
    int year = 2024,
    String library = 'movies',
  }) async {
    await db.customStatement(
      '''INSERT INTO media
      (source_id,local_id,title,type,bytes,modified,is_series,identity_kind,parent_id,year)
      VALUES (?,?,?,?,0,0,?,'fixture',?,?)''',
      [source, id, id, type, type == 'series' ? 1 : 0, parent, year],
    );
    await db.customStatement(
      'INSERT INTO remote_media_metadata VALUES(?,?,?)',
      [
        source,
        id,
        jsonEncode({'externalId': id, 'libraryId': library, 'rating': 8.0}),
      ],
    );
  }

  test(
    '1000 actor episode credits use four reads and retain parent deduplication',
    () async {
      await item('show', type: 'series', library: 'shows');
      await item('film', year: 2025);
      await item('song', type: 'music');
      await db.customStatement('''WITH RECURSIVE n(i) AS
      (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<1000)
      INSERT INTO media(source_id,local_id,title,type,bytes,modified,is_series,identity_kind,parent_id)
      SELECT 'a','ep'||i,'ep'||i,'episode',0,0,0,'fixture','show' FROM n''');
      await db.customStatement('''INSERT INTO remote_media_details
      SELECT source_id,local_id,'{"people":[{"key":"actor"}]}',0 FROM media''');
      await item('film', source: 'b');
      final client = EmbyClient(deviceId: 'query-test');
      final connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: (_) => throw StateError('No network'),
      );
      addTearDown(() {
        connections.dispose();
        client.close();
      });
      final details = EmbyDetailRepository(
        sources: sources,
        connections: connections,
      );
      counter.reads.clear();
      final works = await details.cachedPersonWorks('a', 'actor');
      expect(works.map((e) => e.identity.localId), ['film', 'show']);
      expect(counter.reads, hasLength(4));
      expect(await details.cachedPersonWorks('b', 'actor'), isEmpty);
      expect(await details.cachedPersonWorks('a', 'missing'), isEmpty);
      await db.customStatement('UPDATE sources SET options=? WHERE id=?', [
        jsonEncode({
          'selectedEmbyLibraryIDs': ['shows'],
        }),
        'a',
      ]);
      expect(
        (await details.cachedPersonWorks('a', 'actor')).single.identity.localId,
        'show',
      );
      await db.customStatement("UPDATE sources SET options='{}' WHERE id='a'");
      await db.customStatement(
        "DELETE FROM media WHERE source_id='a' AND parent_id='show'",
      );
      await db.customStatement(
        "DELETE FROM media WHERE source_id='a' AND local_id='show'",
      );
      expect(
        (await details.cachedPersonWorks('a', 'actor')).single.identity.localId,
        'film',
      );
    },
  );

  test('preference changes reuse metadata, update scopes and do not reload another source', () async {
    await item('film');
    await item('other');
    await item('film', source: 'b');
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
    );
    addTearDown(container.dispose);
    for (final id in ['a', 'b']) {
      container.listen(embyVideoSnapshotProvider(id), (_, _) {});
    }
    final before = await container.read(embyVideoSnapshotProvider('a').future);
    final otherSource = await container.read(
      embyVideoSnapshotProvider('b').future,
    );
    final repo = container.read(embyLibraryRepositoryProvider);
    const film = (sourceId: 'a', localId: 'film');
    const watchlist = (
      sourceId: 'a',
      section: EmbyVideoSection.watchlist,
      libraryId: null as String?,
    );
    expect(before.scope(watchlist), isEmpty);
    var events = 0;
    final listener = sources.changes.listen((_) => events++);
    addTearDown(listener.cancel);
    counter.reads.clear();
    await repo.setWatchlist(film, true);
    await container.pump();
    final after = await container.read(embyVideoSnapshotProvider('a').future);
    expect(after.scope(watchlist).single.item.identity, film);
    expect(
      identical(after.entryFor(film)!.item, before.entryFor(film)!.item),
      isTrue,
    );
    expect(
      identical(
        after.entryFor((sourceId: 'a', localId: 'other')),
        before.entryFor((sourceId: 'a', localId: 'other')),
      ),
      isTrue,
    );
    expect(
      identical(
        await container.read(embyVideoSnapshotProvider('b').future),
        otherSource,
      ),
      isTrue,
    );
    expect(
      counter.reads.where((r) => r.sql.contains('remote_media_details')),
      isEmpty,
    );
    expect(
      counter.reads.where(
        (r) => r.sql.startsWith('SELECT * FROM media_library_preferences'),
      ),
      hasLength(1),
    );
    expect(events, 1); // Legacy home/detail/sidebar listeners still notified.
    await repo.setRating([film], 5);
    await container.pump();
    expect(
      (await container.read(embyVideoSnapshotProvider('a').future))
          .entryFor(film)!
          .userRating,
      5,
    );
    await repo.setRating([film], null);
    await repo.setWatchlist(film, false);
    await container.pump();
    final cleared = await container.read(embyVideoSnapshotProvider('a').future);
    expect(cleared.entryFor(film)!.userRating, isNull);
    expect(cleared.scope(watchlist), isEmpty);
    final revision = sources.libraryPreferenceRevision('a');
    await expectLater(
      repo.setWatchlistMany([film, (sourceId: 'a', localId: 'missing')], true),
      throwsA(isA<SourceFailure>()),
    );
    expect(sources.libraryPreferenceRevision('a'), revision);
    // Real content invalidation still re-reads metadata and expires old scopes.
    await db.customStatement(
      "UPDATE media SET title='Changed' WHERE source_id='a' AND local_id='film'",
    );
    sources.traceChanged();
    await container.pump();
    expect(
      (await container.read(embyVideoSnapshotProvider('a').future))
          .entryFor(film)!
          .item
          .title,
      'Changed',
    );
    await sources.remove('a');
    await container.pump();
    await expectLater(
      container.read(embyVideoSnapshotProvider('a').future),
      throwsA(isA<SourceFailure>()),
    );
  });

  test('home and navigation refresh only affected sources; unknown changes remain global', () async {
    await item('film');
    await item('film', source: 'b');
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
    );
    addTearDown(container.dispose);
    const pageA = (
      sourceId: 'a',
      collection: HomeCollection.watchlist,
      offset: 0,
    );
    const pageB = (
      sourceId: 'b',
      collection: HomeCollection.watchlist,
      offset: 0,
    );
    container.listen(sidebarSourcesProvider, (_, _) {});
    container.listen(sourcesProvider, (_, _) {});
    container.listen(homeVideoPageProvider(pageA), (_, _) {});
    container.listen(homeVideoPageProvider(pageB), (_, _) {});
    container.listen(homeSourceStatsProvider('b'), (_, _) {});
    container.listen(homeRecommendationCandidatesProvider('b'), (_, _) {});
    container.listen(embySidebarSectionsProvider('a'), (_, _) {});
    container.listen(embySidebarSectionsProvider('b'), (_, _) {});
    final sidebar = await container.read(sidebarSourcesProvider.future);
    final counted = await container.read(sourcesProvider.future);
    await container.read(homeVideoPageProvider(pageA).future);
    final page = await container.read(homeVideoPageProvider(pageB).future);
    final stats = await container.read(homeSourceStatsProvider('b').future);
    final recommendations = await container.read(
      homeRecommendationCandidatesProvider('b').future,
    );
    final sections = await container.read(
      embySidebarSectionsProvider('b').future,
    );
    await container.read(embySidebarSectionsProvider('a').future);
    counter.reads.clear();
    await EmbyLibraryRepository(sources)
        .setWatchlist((sourceId: 'a', localId: 'film'), true);
    await container.pump();
    expect(
      (await container.read(homeVideoPageProvider(pageA).future)).items,
      hasLength(1),
    );
    expect(
      await container.read(embySidebarSectionsProvider('a').future),
      contains(EmbyVideoSection.watchlist),
    );
    expect(
      identical(await container.read(sidebarSourcesProvider.future), sidebar),
      isTrue,
    );
    expect(
      identical(await container.read(sourcesProvider.future), counted),
      isTrue,
    );
    expect(
      identical(
        await container.read(homeVideoPageProvider(pageB).future),
        page,
      ),
      isTrue,
    );
    expect(
      identical(
        await container.read(homeSourceStatsProvider('b').future),
        stats,
      ),
      isTrue,
    );
    expect(
      identical(
        await container.read(homeRecommendationCandidatesProvider('b').future),
        recommendations,
      ),
      isTrue,
    );
    expect(
      identical(
        await container.read(embySidebarSectionsProvider('b').future),
        sections,
      ),
      isTrue,
    );
    await sources.setRemoteFavorite((sourceId: 'a', localId: 'film'), true);
    await container.pump();
    expect(
      await container.read(embySidebarSectionsProvider('a').future),
      contains(EmbyVideoSection.favorites),
    );
    expect(
      identical(
        await container.read(homeVideoPageProvider(pageB).future),
        page,
      ),
      isTrue,
    );
    expect(
      identical(await container.read(sidebarSourcesProvider.future), sidebar),
      isTrue,
    );
    sources.traceChanged();
    await container.pump();
    expect(
      identical(
        await container.read(homeVideoPageProvider(pageB).future),
        page,
      ),
      isFalse,
    );
    expect(
      identical(await container.read(sidebarSourcesProvider.future), sidebar),
      isFalse,
    );
  });

  test('sparse preference overlays retain children, order and old snapshots across resets', () async {
    await item('show', type: 'series');
    await item('film');
    await item('episode', parent: 'show', type: 'episode');
    await db.customStatement("""WITH RECURSIVE n(i) AS
      (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<10000)
      INSERT INTO media(source_id,local_id,title,type,bytes,modified,is_series,identity_kind,parent_id)
      SELECT 'a','ep'||i,'ep'||i,'episode',0,0,0,'fixture','show' FROM n""");
    final repo = EmbyLibraryRepository(sources);
    const film = (sourceId: 'a', localId: 'film');
    const show = (sourceId: 'a', localId: 'show');
    const episode = (sourceId: 'a', localId: 'episode');
    const watchlist = (
      sourceId: 'a',
      section: EmbyVideoSection.watchlist,
      libraryId: null as String?,
    );
    await repo.setWatchlist(film, true);
    final base = _CountingSnapshot(await repo.snapshot('a'));
    base.observe();
    final children = base.childrenOf(show);
    expect(children, hasLength(10001));
    await repo.setWatchlist(film, false);
    await repo.setWatchlist(show, true);
    await repo.setRating([episode], null);
    final updated = await repo.refreshPreferences(base);
    expect(
      base.observed!.reads,
      0,
      reason: "Preference overlay must not traverse 10,003 content rows",
    );
    expect(updated.scope(watchlist).map((e) => e.item.identity), [show]);
    expect(base.scope(watchlist).map((e) => e.item.identity), [film]);
    expect(
      updated
          .childrenOf(show)
          .firstWhere((e) => e.item.identity == episode)
          .userRating,
      isNull,
    );
    expect(identical(updated.childrenOf(show).first, children.first), isTrue);
    expect(updated.entries.length, base.entries.length);
    expect(() => updated.entries.clear(), throwsUnsupportedError);
    expect(() => updated.childrenOf(show).clear(), throwsUnsupportedError);
    await db.customStatement(
      "DELETE FROM media_library_preferences WHERE source_id='a'",
    );
    final reset = await repo.refreshPreferences(updated);
    expect(reset.scope(watchlist), isEmpty);
    expect(reset.entryFor(episode)!.userRating, 4);
    expect(updated.entryFor(show)!.watchlist, isTrue);
    expect(base.entryFor(film)!.watchlist, isTrue);
    await repo.setWatchlistMany([show, film], true);
    final again = await repo.refreshPreferences(reset);
    expect(again.scope(watchlist).map((e) => e.item.identity), [film, show]);
  });

  test(
    'preference write during the initial content read is not lost',
    () async {
      await item('film');
      final repo = _DelayedLibrary(sources);
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          embyLibraryRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      container.listen(embyVideoSnapshotProvider('a'), (_, _) {});
      await repo.started.future;
      await repo.setWatchlist((sourceId: 'a', localId: 'film'), true);
      repo.release.complete();
      await container.pump();
      final result = await container.read(
        embyVideoSnapshotProvider('a').future,
      );
      expect(result.entries.single.watchlist, isTrue);
      expect(repo.reads, 1);
    },
  );
}

class _DelayedLibrary extends EmbyLibraryRepository {
  _DelayedLibrary(super.sources);
  final started = Completer<void>(), release = Completer<void>();
  int reads = 0;
  @override
  Future<EmbyVideoSnapshot> snapshot(String id) async {
    reads++;
    final value = await super.snapshot(id);
    started.complete();
    await release.future;
    return value;
  }
}

// Instrument list access, rather than asserting a machine-dependent timing.
class _CountingSnapshot extends EmbyVideoSnapshot {
  _CountingSnapshot(EmbyVideoSnapshot base)
    : super(
        source: base.source,
        libraries: base.libraries,
        entries: base.entries,
      );
  _CountingEntries? observed;
  void observe() => observed = _CountingEntries(super.entries);
  @override
  List<VideoLibraryEntry> get entries => observed ?? super.entries;
}

class _CountingEntries extends ListBase<VideoLibraryEntry> {
  _CountingEntries(this.base);
  final List<VideoLibraryEntry> base;
  int reads = 0;
  @override
  int get length => base.length;
  @override
  set length(int value) => throw UnsupportedError('immutable');
  @override
  VideoLibraryEntry operator [](int index) {
    reads++;
    return base[index];
  }

  @override
  void operator []=(int index, VideoLibraryEntry value) =>
      throw UnsupportedError('immutable');
}
