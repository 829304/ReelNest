import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/api/emby/emby_detail.dart';
import 'package:reelnest/app/router.dart';
import 'package:reelnest/app/bootstrap.dart';
import 'package:reelnest/features/playback/application/playback_providers.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/application/emby_library_providers.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_connection_repository.dart';
import 'package:reelnest/features/sources/data/emby_detail_repository.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/emby_sync_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';
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

Map<String, dynamic> _movie(String id, String title) => {
  'Id': id,
  'Name': title,
  'Type': 'Movie',
  'Genres': ['剧情'],
  'ProductionYear': 2024,
  'CommunityRating': 8.4,
  'RunTimeTicks': 1000000000,
};

VideoLibraryEntry _entry(
  String title, {
  int year = 2024,
  int progress = 0,
  bool watched = false,
  bool listed = false,
  bool favorite = false,
  double score = 8,
  double rating = 2,
}) {
  final id = (sourceId: 's', localId: title);
  return VideoLibraryEntry(
    item: IndexedMedia(
      identity: id,
      title: title,
      type: 'movie',
      bytes: 0,
      year: year,
      modified: DateTime.utc(year),
      remote: RemoteMediaMetadata(
        externalId: title,
        durationMs: year,
        genres: ['剧情'],
        favorite: favorite,
        rating: score,
      ),
    ),
    record: PlaybackRecord(
      identity: id,
      position: Duration(seconds: progress),
      duration: const Duration(seconds: 100),
      watched: watched,
    ),
    createdAt: DateTime.utc(year),
    watchlist: listed,
    userRating: rating,
    searchTerms: [title, 'Original title', '测试演员'],
  );
}

void main() {
  group('local browser rules', () {
    test('substring, full pinyin, initials and English initials match original examples', () {
      for (final query in ['', '北京', 'beijing', 'bj', 'BEI']) {
        expect(LibrarySearchMatcher.matches(query, [null, '北京故事']), isTrue);
      }
      expect(LibrarySearchMatcher.matches('bb', ['Breaking Bad']), isTrue);
      expect(LibrarySearchMatcher.matches('missing', [null, '']), isFalse);
      expect(LibrarySearchMatcher.matches('测试', ['测试演员']), isTrue);
      expect(LibrarySearchMatcher.matches('q', ['北京']), isFalse);
    });
    test('title is natural ascending, reverse toggles and numeric ties retain title order', () {
      final items = [_entry('Movie 10'), _entry('Movie 2'), _entry('Movie 1')];
      List<String> sorted(VideoLibrarySettings settings) => filterVideoLibrary(
        items,
        settings,
        .9,
      ).map((e) => e.item.title).toList();
      expect(sorted(const VideoLibrarySettings(sort: VideoLibrarySort.title)), [
        'Movie 1',
        'Movie 2',
        'Movie 10',
      ]);
      expect(
        sorted(
          const VideoLibrarySettings(
            sort: VideoLibrarySort.title,
            reverse: true,
          ),
        ),
        ['Movie 10', 'Movie 2', 'Movie 1'],
      );
      expect(
        sorted(
          const VideoLibrarySettings(
            sort: VideoLibrarySort.year,
            reverse: true,
          ),
        ),
        ['Movie 1', 'Movie 2', 'Movie 10'],
      );
    });
    for (final sort in VideoLibrarySort.values.where(
      (s) => s != VideoLibrarySort.title,
    )) {
      test('${sort.name} defaults to higher/recent first', () {
        final low = _entry(
          'Low',
          year: 2020,
          progress: 20,
          score: 4,
          rating: 1,
        );
        final high = _entry(
          'High',
          year: 2025,
          progress: 60,
          score: 9,
          rating: 5,
        );
        expect(
          filterVideoLibrary(
            [low, high],
            VideoLibrarySettings(sort: sort),
            .9,
          ).first,
          high,
        );
        expect(
          filterVideoLibrary(
            [low, high],
            VideoLibrarySettings(sort: sort, reverse: true),
            .9,
          ).first,
          low,
        );
      });
    }
    test(
      'watch threshold, local watchlist, favorites, search and genre intersect',
      () {
        final items = [
          _entry('Fresh'),
          _entry('Partial', progress: 50, listed: true),
          _entry('Nearly', progress: 95),
          _entry('Flagged', watched: true, favorite: true),
        ];
        List<String> filtered(
          LibraryWatchFilter filter, {
          double threshold = .9,
        }) => filterVideoLibrary(
          items,
          VideoLibrarySettings(filter: filter),
          threshold,
        ).map((e) => e.item.title).toList();
        expect(filtered(LibraryWatchFilter.watching), ['Partial']);
        expect(filtered(LibraryWatchFilter.unwatched), ['Fresh', 'Partial']);
        expect(filtered(LibraryWatchFilter.watched), ['Flagged', 'Nearly']);
        expect(filtered(LibraryWatchFilter.watched, threshold: .4), [
          'Flagged',
          'Nearly',
          'Partial',
        ]);
        expect(filtered(LibraryWatchFilter.watchlist), ['Partial']);
        expect(filtered(LibraryWatchFilter.favorites), ['Flagged']);
        expect(
          filterVideoLibrary(
            items,
            const VideoLibrarySettings(
              filter: LibraryWatchFilter.watchlist,
              search: 'cs yy',
              genre: '剧情',
            ),
            .9,
          ),
          isEmpty,
        );
        expect(
          filterVideoLibrary(
            items,
            const VideoLibrarySettings(
              filter: LibraryWatchFilter.watchlist,
              search: 'csyy',
              genre: '剧情',
            ),
            .9,
          ).single.item.title,
          'Partial',
        );
      },
    );
    test(
      'destination safely encodes source and Unicode/reserved library IDs',
      () {
        final id = (
          sourceId: 'source/a',
          section: EmbyVideoSection.videos,
          libraryId: '电影 & /?#',
        );
        final uri = Uri.parse(embyVideoLocation(id));
        expect(uri.pathSegments.last, 'source/a');
        expect(uri.queryParameters['library'], '电影 & /?#');
        final watch = Uri.parse(
          embyVideoLocation((
            sourceId: 's',
            section: EmbyVideoSection.watchlist,
            libraryId: null,
          )),
        );
        expect(watch.queryParameters['section'], 'watchlist');
      },
    );
  });

  group('cached navigation and sync', () {
    late EmbyServerFixture server;
    late EmbyClient client;
    late SourceRepository sources;
    late EmbyConnectionRepository connections;
    late EmbySyncRepository sync;
    late EmbyLibraryRepository library;
    late MediaSource source;
    setUp(() async {
      server = EmbyServerFixture();
      await server.start();
      client = EmbyClient(
        deviceId: 'navigation-test',
        http: HttpOverrides.runWithHttpOverrides(() => HttpClient(), _Http()),
      );
      sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      final stores = <String, _Store>{};
      connections = EmbyConnectionRepository(
        sources: sources,
        client: Future.value(client),
        stores: (id) => stores.putIfAbsent(id, _Store.new),
      );
      sync = EmbySyncRepository(sources: sources, connections: connections);
      library = EmbyLibraryRepository(sources);
      source = await connections.connect(server.address, 'tester', 'pw');
    });
    tearDown(() async {
      connections.dispose();
      client.close();
      await sources.close();
      await server.close();
    });
    EmbyVideoDestination dest({
      String? view,
      EmbyVideoSection section = EmbyVideoSection.videos,
    }) => (sourceId: source.id, section: section, libraryId: view);

    test('cache keeps named empty views, excludes music views and filters selected libraries', () async {
      server.views = {
        'Items': [
          {'Id': 'movies', 'Name': '电影', 'CollectionType': 'movies'},
          {'Id': 'empty', 'Name': '空库', 'CollectionType': 'movies'},
          {'Id': 'music', 'Name': '音乐', 'CollectionType': 'music'},
        ],
      };
      server.catalog['movies'] = [_movie('m', '电影')];
      server.catalog['music'] = [
        {'Id': 'audio', 'Name': 'Song', 'Type': 'Audio'},
      ];
      await sync.synchronize(source.id);
      final requests = server.requests.length;
      final snapshot = await library.snapshot(source.id);
      expect(
        snapshot.libraries.map((v) => v.id),
        containsAll(['movies', 'empty']),
      );
      expect(snapshot.libraries.map((v) => v.id), isNot(contains('music')));
      expect(snapshot.entries.any((e) => e.item.type == 'music'), isTrue);
      expect(snapshot.scope(dest()).single.item.title, '电影');
      expect(snapshot.scope(dest(view: 'empty')), isEmpty);
      expect(server.requests.length, requests);
      await connections.selectLibraries(
        source.id,
        all: false,
        selected: ['empty'],
      );
      expect((await library.snapshot(source.id)).libraries.single.id, 'empty');
    });
    test('late catalog failure and view SQL failure both retain old directory plus index', () async {
      server.catalog['movies'] = [_movie('old', 'Old')];
      await sync.synchronize(source.id);
      server.views = {
        'Items': [
          {'Id': 'new-view', 'Name': 'New', 'CollectionType': 'movies'},
        ],
      };
      server.catalog['new-view'] = [_movie('new', 'New')];
      server.itemsHandler = (r) async {
        r.response.statusCode = 500;
        await r.response.close();
      };
      await expectLater(sync.synchronize(source.id), throwsA(anything));
      expect(
        (await library.snapshot(source.id)).libraries.map((v) => v.id),
        contains('movies'),
      );
      server.itemsHandler = null;
      await sources.database.customStatement(
        "CREATE TRIGGER fail_view BEFORE INSERT ON remote_library_views WHEN NEW.library_id = 'new-view' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      await expectLater(sync.synchronize(source.id), throwsA(anything));
      final retained = await library.snapshot(source.id);
      expect(retained.entries.single.item.identity.localId, 'old');
      expect(retained.libraries.map((v) => v.id), contains('movies'));
    });
    test('local watchlist and first import/rating survive resync, then cascade on deletion', () async {
      server.catalog['movies'] = [_movie('m', 'Original')];
      await sync.synchronize(source.id);
      final before = (await library.snapshot(source.id)).entries.single;
      final requests = server.requests.length;
      await library.setWatchlist(before.item.identity, true);
      expect(server.requests.length, requests);
      expect(
        (await library.snapshot(source.id))
            .scope(dest(section: EmbyVideoSection.watchlist))
            .length,
        1,
      );
      server.catalog['movies'] = [
        {..._movie('m', 'Updated'), 'CommunityRating': 5},
      ];
      await sync.synchronize(source.id);
      final after = (await library.snapshot(source.id)).entries.single;
      expect(after.watchlist, isTrue);
      expect(after.createdAt, before.createdAt);
      expect(after.userRating, 8.4);
      expect(after.item.remote!.rating, 5);
      server.catalog['movies'] = [];
      await sync.synchronize(source.id);
      expect(
        await sources.database
            .customSelect('SELECT * FROM media_library_preferences')
            .get(),
        isEmpty,
      );
    });
    test('two accounts with identical library and media IDs keep separate watchlists/views', () async {
      server.catalog['movies'] = [_movie('same', 'First')];
      await sync.synchronize(source.id);
      final other = await connections.connect(server.address, 'tester', 'pw');
      server.catalog['movies'] = [_movie('same', 'Second')];
      await sync.synchronize(other.id);
      await library.setWatchlist((sourceId: source.id, localId: 'same'), true);
      expect(
        (await library.snapshot(source.id)).entries.single.item.title,
        'First',
      );
      expect(
        (await library.snapshot(other.id)).entries.single.watchlist,
        isFalse,
      );
      await connections.remove(source.id);
      expect((await library.snapshot(other.id)).libraries, hasLength(2));
    });
    test('player notification refreshes watch filters and progress sorting only for affected sources', () async {
      server.catalog['movies'] = [_movie('a', 'A'), _movie('b', 'B')];
      await sync.synchronize(source.id);
      final other = await connections.connect(server.address, 'tester', 'pw');
      await sync.synchronize(other.id);
      final records = PlaybackRepository(sources.database);
      final a = (sourceId: source.id, localId: 'a');
      final b = (sourceId: source.id, localId: 'b');
      await records.save(
        b,
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 100),
      );
      final container = ProviderContainer(
        overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
      );
      addTearDown(container.dispose);
      final watching = (
        destination: dest(),
        settings: const VideoLibrarySettings(
          filter: LibraryWatchFilter.watching,
        ),
      );
      final watched = (
        destination: dest(),
        settings: const VideoLibrarySettings(
          filter: LibraryWatchFilter.watched,
        ),
      );
      final sorted = (
        destination: dest(),
        settings: const VideoLibrarySettings(sort: VideoLibrarySort.progress),
      );
      for (final query in [watching, watched, sorted]) {
        final subscription = container.listen(
          embyVideoResultsProvider(query),
          (_, _) {},
        );
        addTearDown(subscription.close);
      }
      final otherSubscription = container.listen(
        embyVideoSnapshotProvider(other.id),
        (_, _) {},
      );
      addTearDown(otherSubscription.close);
      final recordSubscription = container.listen(
        playbackRecordProvider(a),
        (_, _) {},
      );
      addTearDown(recordSubscription.close);
      final otherSnapshot = await container.read(
        embyVideoSnapshotProvider(other.id).future,
      );
      Future<List<String>> ids(VideoLibraryQuery query) async =>
          (await container.read(embyVideoResultsProvider(query).future))
              .map((e) => e.item.identity.localId)
              .toList();
      expect(await ids(watching), ['b']);
      expect(await ids(watched), isEmpty);
      expect(await ids(sorted), ['b', 'a']);
      expect(
        (await container.read(playbackRecordProvider(a).future)).position,
        Duration.zero,
      );
      final requests = server.requests.length;
      await records.save(
        a,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 100),
      );
      refreshPlaybackViews(container, [source.id]);
      expect(await ids(watching), containsAll(['a', 'b']));
      expect(await ids(sorted), ['a', 'b']);
      expect(
        (await container.read(playbackRecordProvider(a).future)).position,
        const Duration(seconds: 50),
      );
      await records.save(
        a,
        position: const Duration(seconds: 100),
        duration: const Duration(seconds: 100),
      );
      refreshPlaybackViews(container, [source.id]);
      expect(await ids(watched), ['a']);
      expect(await ids(watching), ['b']);
      expect(
        await container.read(embyVideoSnapshotProvider(other.id).future),
        same(otherSnapshot),
      );
      expect(server.requests.length, requests);
    });

    test('view state persists independently; search and genre are intentionally transient', () async {
      final settings = const VideoLibrarySettings(
        sort: VideoLibrarySort.title,
        reverse: true,
        filter: LibraryWatchFilter.watchlist,
        search: 'query',
        genre: 'Drama',
      );
      await library.saveSettings(dest(view: 'movies'), settings);
      final restored = await EmbyLibraryRepository(sources)
          .settings(dest(view: 'movies'));
      expect(restored.sort, VideoLibrarySort.title);
      expect(restored.filter, LibraryWatchFilter.watchlist);
      expect(restored.reverse, isTrue);
      expect(restored.search, isEmpty);
      expect(restored.genre, isEmpty);
      expect(
        (await library.settings(dest(view: 'shows'))).filter,
        LibraryWatchFilter.all,
      );
    });
    test('series search includes child title/season label without listing episodes at root', () async {
      server.catalog['shows'] = [
        {'Id': 'show', 'Name': 'A show', 'Type': 'Series'},
        {
          ..._movie('ep', '北京故事'),
          'Type': 'Episode',
          'SeriesId': 'show',
          'SeriesName': 'A show',
          'ParentIndexNumber': 2,
          'IndexNumber': 3,
        },
      ];
      await sync.synchronize(source.id);
      final scoped = (await library.snapshot(source.id))
          .scope(dest(view: 'shows'));
      expect(scoped, hasLength(1));
      for (final query in ['beijing', 'bjgs', 'S02E03']) {
        expect(
          filterVideoLibrary(scoped, VideoLibrarySettings(search: query), .9),
          hasLength(1),
        );
      }
    });
    test(
      'large snapshot isolate filters beyond old page boundaries without HTTP',
      () async {
        server.itemPageSize = 300;
        server.catalog['movies'] = List.generate(
          205,
          (i) => _movie('m$i', i == 204 ? '北京终章' : 'Movie $i'),
        );
        await sync.synchronize(source.id);
        final count = server.requests.length;
        final container = ProviderContainer(
          overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
        );
        addTearDown(container.dispose);
        final query = (
          destination: dest(),
          settings: const VideoLibrarySettings(search: 'bjzz'),
        );
        final subscription = container.listen(
          embyVideoResultsProvider(query),
          (_, _) {},
        );
        addTearDown(subscription.close);
        expect(
          (await container.read(embyVideoResultsProvider(query).future))
              .single
              .item
              .identity
              .localId,
          'm204',
        );
        expect(server.requests.length, count);
      },
    );
    for (final brightness in Brightness.values) {
      testWidgets(
        'sidebar navigation/search/filter/collapse at desktop minimum $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(1088, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(() async {
            server.catalog['movies'] = [
              _movie('m1', '北京故事'),
              _movie('m2', '上海故事'),
            ];
            await sync.synchronize(source.id);
          });
          final router = createRouter(
            initialLocation: embyVideoLocation(dest(view: 'movies')),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                sourceRepositoryProvider.overrideWithValue(sources),
                embyDetailProvider.overrideWith(
                  (ref, key) => Stream.value(
                    EmbyDetailSnapshot(
                      EmbyDetail.fromServer({
                        'Id': key.identity.localId,
                      }, key.identity.localId),
                      DateTime.now(),
                    ),
                  ),
                ),
              ],
              child: MaterialApp.router(
                routerConfig: router,
                theme: ThemeData(brightness: brightness),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('北京故事'), findsWidgets);
          expect(find.text('共 2 项'), findsOneWidget);
          expect(find.text('音乐'), findsNothing);
          await tester.enterText(find.byType(TextField), 'bjgs');
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pumpAndSettle();
          expect(find.text('共 1 项'), findsOneWidget);
          expect(find.text('上海故事'), findsNothing);
          final requests = server.requests.length;
          await tester.tap(find.byType(LocalMediaCard));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('加入想看'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('移出想看'), findsOneWidget);
          expect(server.requests.length, requests);
          await tester.tap(find.text('返回'));
          await tester.pumpAndSettle();
          expect(
            router
                .routerDelegate
                .currentConfiguration
                .uri
                .queryParameters['library'],
            'movies',
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'bjgs',
          );
          expect(find.text('共 1 项'), findsOneWidget);
          await tester.tap(find.byTooltip('清除搜索'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('最近更新 · 正序'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('标题').last);
          await tester.pumpAndSettle();
          expect(
            (await library.settings(dest(view: 'movies'))).sort,
            VideoLibrarySort.title,
          );
          await tester.tap(find.byTooltip('全部类型'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('剧情').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('想看').last);
          await tester.pumpAndSettle();
          expect(find.text('共 1 项'), findsOneWidget);
          await tester.tap(find.text('全部').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('电视剧').first);
          await tester.pumpAndSettle();
          expect(
            router
                .routerDelegate
                .currentConfiguration
                .uri
                .queryParameters['library'],
            'shows',
          );
          expect(find.text('共 0 项'), findsOneWidget);
          await tester.tap(find.text('Emby 媒体库').first, buttons: 2);
          await tester.pumpAndSettle();
          await tester.tap(find.text('重命名'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            ),
            '我的 Emby',
          );
          await tester.tap(find.text('保存'));
          await tester.pumpAndSettle();
          expect((await sources.source(source.id)).name, '我的 Emby');
          await tester.tap(find.text('我的 Emby').first);
          await tester.pumpAndSettle();
          expect(find.text('全部视频'), findsNothing);
          expect(
            jsonDecode(
              (await library.preference('library.collapsedEmbySources'))!,
            ),
            [source.id],
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant({
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        }),
      );
    }
  });
}
