import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/application/tmdb_providers.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/tmdb_fixture.dart';

class _Credential implements CredentialStore {
  @override
  Future<String?> read() async => 'fixture-key';

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory media;
  late Directory library;
  late SourceRepository sources;
  late TmdbFixture fixture;
  late TmdbVideoService service;
  late MediaSource source;
  late MediaIdentity identity;
  late List<IndexedMedia> episodes;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-tmdb-series-ui-');
    media = await Directory(p.join(sandbox.path, 'media')).create();
    library = await Directory(p.join(sandbox.path, 'library')).create();
    for (final path in [
      'Show/Season 1/Show.S01E01.mkv',
      'Show/Season 1/Show.S01E02.mkv',
      'Show/Season 2/Show.S02E01.mkv',
    ]) {
      final file = File(p.join(media.path, path));
      await file.parent.create(recursive: true);
      await file.writeAsString('fixture');
    }
    sources = SourceRepository(
      database: LibraryDatabase(
        NativeDatabase(File(p.join(library.path, 'fixture.sqlite'))),
      ),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Series',
      location: media.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    identity = (await sources.indexedSource(source.id))
        .singleWhere((item) => item.isSeries)
        .identity;
    episodes = await sources.indexedChildren(identity);
    fixture = await TmdbFixture.start();
    service = TmdbVideoService(
      sources: sources,
      settings: TmdbSettingsRepository(sources.database, store: _Credential()),
      artwork: TmdbArtworkStore(library: () async => library),
      client: fixture.client(),
      kind: TmdbMediaKind.tv,
    );
  });

  tearDown(() async {
    await service.dispose();
    await fixture.close();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    await sandbox.delete(recursive: true);
  });

  Widget app(MediaIdentity target) => ProviderScope(
    overrides: [
      sourceRepositoryProvider.overrideWithValue(sources),
      tmdbSeriesServiceProvider.overrideWithValue(service),
    ],
    child: MaterialApp(
      home: Scaffold(body: LocalMediaDetailPage(identity: target)),
    ),
  );

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int attempts = 300,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (condition()) {
        await tester.pump(const Duration(milliseconds: 150));
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    throw TimeoutException('TMDB series UI did not reach the expected state');
  }

  testWidgets(
    'local series searches TV and refreshes hero, people and existing episodes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1088, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(app(identity));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('tmdb-series-search-entry'))
            .evaluate()
            .isNotEmpty,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('tmdb-series-search-entry')),
      );
      await tester.tap(find.byKey(const ValueKey('tmdb-series-search-entry')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('apply-tmdb-candidate-1'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('tmdb-series-search-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('tmdb-movie-search-dialog')),
        findsNothing,
      );
      expect(find.text('2021-02-03'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('apply-tmdb-candidate-1')));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('tmdb-series-search-dialog'))
            .evaluate()
            .isEmpty,
      );
      await pumpUntil(tester, () => find.text('完整剧集 1').evaluate().isNotEmpty);
      expect(find.text('Ended'), findsOneWidget);
      expect(find.text('TV-14'), findsOneWidget);
      expect(find.text('3 季'), findsOneWidget);
      expect(find.text('24 集'), findsOneWidget);
      expect(find.text('45 分钟'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tmdb-movie-detail-extras')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('演员甲'), findsOneWidget);
      expect(find.text('角色甲'), findsOneWidget);
      expect(find.text('主创甲'), findsOneWidget);

      final season = (await tester.runAsync(() => sources.seasons(identity)))!
          .singleWhere((value) => value.number == 1);
      await tester.scrollUntilVisible(
        find.text(season.title),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(season.title));
      await pumpUntil(
        tester,
        () => find.textContaining('单集 1-1').evaluate().isNotEmpty,
      );
      expect(find.textContaining('单集 1-1'), findsWidgets);
      expect(fixture.requests.any((uri) => uri.path == '/3/search/tv'), isTrue);
      expect(
        fixture.requests.any((uri) => uri.path == '/3/search/movie'),
        isFalse,
      );
      expect(
        fixture.requests.any((uri) => uri.path.contains('/episode/')),
        isFalse,
      );
      final persisted = (await tester.runAsync(
        () => sources.indexedChildren(identity),
      ))!;
      expect(persisted, hasLength(episodes.length));
      expect(
        persisted.map((item) => item.title),
        containsAll(<String>['单集 1-1', '单集 1-2', '单集 2-1']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('individual local episode never exposes whole-series matching', (
    tester,
  ) async {
    await tester.pumpWidget(app(episodes.first.identity));
    await pumpUntil(
      tester,
      () =>
          find.byKey(const ValueKey('media-detail-hero')).evaluate().isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('tmdb-series-search-entry')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('tmdb-movie-search-entry')), findsNothing);
  });

  testWidgets('series cast collapse survives repository refresh', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await service.apply(identity, (await service.search('Show')).first);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1088, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app(identity));
    await pumpUntil(tester, () => find.text('演员甲').evaluate().isNotEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('toggle-tmdb-details')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('toggle-tmdb-details')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('演员甲'), findsNothing);

    sources.traceChanged(sourceIds: [source.id]);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('演员甲'), findsNothing);
    expect(
      find.byKey(const ValueKey('tmdb-series-search-entry')),
      findsOneWidget,
    );
  });
}
