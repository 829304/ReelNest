import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/application/emby_library_providers.dart';
import 'package:reelnest/features/sources/application/emby_providers.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/emby_library_repository.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/domain/emby_library.dart';
import 'package:reelnest/features/sources/presentation/emby_sidebar.dart';
import 'package:reelnest/storage/library_database.dart';

class _SlowPreferences extends EmbyLibraryRepository {
  _SlowPreferences(super.sources);
  final saves = <String>[];
  final release = Completer<void>();
  bool fail = false;
  @override
  Future<void> savePreference(String key, String value) async {
    saves.add(value);
    await release.future;
    if (fail) throw StateError('fixture persistence failure');
    await super.savePreference(key, value);
  }
}

void main() {
  late SourceRepository sources;
  late MediaSource source;
  late EmbyLibraryRepository library;
  setUp(() async {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    source = await sources.add(
      kind: MediaSourceKind.emby,
      name: '客厅 Emby',
      location: 'emby://fixture/user',
    );
    library = EmbyLibraryRepository(sources);
    await library.replaceViews(source.id, [
      const EmbyLibrary(id: 'movies', name: '电影', collectionType: 'movies'),
      const EmbyLibrary(id: 'empty', name: '空库', collectionType: 'movies'),
      const EmbyLibrary(id: 'music', name: '音乐', collectionType: 'music'),
    ]);
  });
  tearDown(() => sources.close());

  Future<void> seed(
    String id, {
    String type = 'movie',
    String? parent,
    bool watchlist = false,
    bool favorite = false,
    String collection = 'movies',
  }) async {
    await sources.database.customStatement(
      '''
      INSERT INTO media(source_id,local_id,title,type,bytes,modified,parent_id,identity_kind)
      VALUES (?,?,?,?,0,0,?,'remote')
    ''',
      [source.id, id, id, type, parent],
    );
    await sources.database.customStatement(
      'INSERT INTO remote_media_metadata VALUES (?,?,?)',
      [
        source.id,
        id,
        jsonEncode({
          'externalId': id,
          'libraryId': 'movies',
          'collectionType': collection,
          'favorite': favorite,
        }),
      ],
    );
    if (watchlist) {
      await sources.database.customStatement(
        'INSERT INTO media_library_preferences VALUES (?,?,1,NULL,0)',
        [source.id, id],
      );
    }
  }

  test('section probes match snapshot rules and skip episodes/music', () async {
    await seed('parent');
    await seed(
      'episode',
      type: 'episode',
      parent: 'parent',
      favorite: true,
      watchlist: true,
    );
    await seed('audio', type: 'music', favorite: true, watchlist: true);
    // Exercise a full probe page of classification-filtered candidates.
    await sources.database.transaction(() async {
      for (var n = 0; n < 70; n++) {
        await seed('a$n', collection: 'music', watchlist: true, favorite: true);
      }
    });
    expect(await library.sidebarSections(source.id), {EmbyVideoSection.videos});
    await seed('z-video', watchlist: true, favorite: true);
    final snapshot = await library.snapshot(source.id);
    final expected = EmbyVideoSection.values
        .where(
          (section) => snapshot.scope((
            sourceId: source.id,
            section: section,
            libraryId: null,
          )).isNotEmpty,
        )
        .toSet();
    expect(await library.sidebarSections(source.id), expected);
    expect(expected, EmbyVideoSection.values.toSet());
    // Sidebar must never decode full details, even when those are broken.
    await sources.database.customStatement(
      'INSERT INTO remote_media_details VALUES (?,?,?,0)',
      [source.id, 'z-video', 'invalid details JSON'],
    );
    expect(await library.sidebarSections(source.id), expected);
    expect((await sources.sources()).single.itemCount, 74);
    expect((await sources.sources(includeCounts: false)).single.itemCount, 0);
  });

  testWidgets(
    'cached directory opens without full snapshot or counted sources',
    (tester) async {
      final client = EmbyClient(deviceId: 'sidebar-test');
      addTearDown(client.close);
      var snapshotReads = 0, countedReads = 0, credentialReads = 0;
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          embyClientProvider.overrideWith((ref) async => client),
          embyCredentialStoresProvider.overrideWithValue((_) {
            credentialReads++;
            throw StateError('cached navigation must not request credentials');
          }),
          sourcesProvider.overrideWith((ref) {
            countedReads++;
            return Completer<List<MediaSource>>().future;
          }),
          embyVideoSnapshotProvider.overrideWith((ref, id) {
            snapshotReads++;
            return Completer<EmbyVideoSnapshot>().future;
          }),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: EmbySidebar()),
          ),
          GoRoute(path: '/sources/:id', builder: (_, _) => const Text('已打开库')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('电影'), findsOneWidget);
      expect(find.text('空库'), findsOneWidget);
      expect(find.text('音乐'), findsNothing);
      expect(find.text('全部视频'), findsOneWidget);
      // A later sync replaces the directory without loading a media snapshot.
      await library.replaceViews(source.id, [
        const EmbyLibrary(id: 'movies', name: '新电影库'),
      ]);
      sources.traceChanged();
      await tester.pumpAndSettle();
      expect(find.text('空库'), findsNothing);
      expect(find.text('新电影库'), findsOneWidget);
      await tester.tap(find.text('新电影库'));
      await tester.pumpAndSettle();
      expect(
        router
            .routerDelegate
            .currentConfiguration
            .uri
            .queryParameters['library'],
        'movies',
      );
      expect(snapshotReads, 0);
      expect(countedReads, 0);
      expect(credentialReads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('loading catalog never shows a false zero badge', (tester) async {
    await library.savePreference(
      'library.collapsedEmbySources',
      jsonEncode([source.id]),
    );
    final catalog = Completer<List<EmbyLibrary>>();
    final sections = Completer<Set<EmbyVideoSection>>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: EmbySidebar()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          embyBrowseCatalogProvider.overrideWith((ref, id) => catalog.future),
          embySidebarSectionsProvider.overrideWith(
            (ref, id) => sections.future,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
    await tester.tap(find.text(source.name));
    await tester.pumpAndSettle();
    catalog.complete([const EmbyLibrary(id: 'movies', name: '电影')]);
    await tester.pumpAndSettle();
    // Directory is usable even while section visibility is still pending.
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('全部视频'), findsOneWidget);
    await tester.tap(find.text(source.name));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsNothing);
    expect(find.text('2'), findsNothing);
    sections.complete({});
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final fail in [false, true]) {
    testWidgets(
      'rapid toggles respond before slow saves; persistence fails=$fail',
      (tester) async {
        final slow = _SlowPreferences(sources)..fail = fail;
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: EmbySidebar()),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sourceRepositoryProvider.overrideWithValue(sources),
              embyLibraryRepositoryProvider.overrideWithValue(slow),
              embyBrowseCatalogProvider.overrideWith(
                (ref, id) async => [
                  const EmbyLibrary(id: 'movies', name: '电影'),
                ],
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(source.name));
        await tester.pumpAndSettle();
        expect(find.text('电影'), findsNothing);
        expect(slow.saves, hasLength(1));
        await tester.tap(find.text(source.name));
        await tester.pumpAndSettle();
        expect(find.text('电影'), findsOneWidget);
        expect(slow.saves, hasLength(1));
        slow.release.complete();
        await tester.pumpAndSettle();
        expect(slow.saves.map(jsonDecode).toList(), [
          [source.id],
          [],
        ]);
        final saved = await library.preference('library.collapsedEmbySources');
        if (fail) {
          expect(saved, isNull);
          expect(find.text('侧栏状态保存失败，请重试。'), findsWidgets);
        } else {
          expect(jsonDecode(saved!), []);
        }
        expect(find.text('电影'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
