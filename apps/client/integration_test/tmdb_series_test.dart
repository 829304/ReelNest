import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/application/tmdb_providers.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/features/sources/presentation/local_media_detail_page.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/tmdb_fixture.dart';

class _Credential implements CredentialStore {
  @override
  Future<String?> read() async => 'fixture-key';

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native local series match refreshes existing episodes and survives offline reopen',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1150, 800));
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final sandbox = await temporary.createTemp(
        'reelnest-tmdb-series-native-',
      );
      final media = await Directory(p.join(sandbox.path, 'media')).create();
      final library = await Directory(p.join(sandbox.path, 'library')).create();
      for (final path in [
        'Show/Season 1/Show.S01E01.mkv',
        'Show/Season 2/Show.S02E01.mkv',
      ]) {
        final file = File(p.join(media.path, path));
        await file.parent.create(recursive: true);
        await file.writeAsString('fixture');
      }
      final fixture = await TmdbFixture.start();
      final apiClient = fixture.client();
      final dbPath = p.join(library.path, 'fixture.sqlite');
      SourceRepository repository() => SourceRepository(
        database: LibraryDatabase(
          NativeDatabase.createInBackground(File(dbPath)),
        ),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture',
      );
      var sources = repository();
      ProviderContainer containerFor(SourceRepository repository) =>
          ProviderContainer(
            overrides: [
              sourceRepositoryProvider.overrideWithValue(repository),
              tmdbSettingsRepositoryProvider.overrideWithValue(
                TmdbSettingsRepository(
                  repository.database,
                  store: _Credential(),
                ),
              ),
              tmdbClientProvider.overrideWithValue(apiClient),
              tmdbArtworkStoreProvider.overrideWithValue(
                TmdbArtworkStore(library: () async => library),
              ),
            ],
          );
      var container = containerFor(sources);
      var containerDisposed = false;

      Future<void> waitFor(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 12));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native TMDB series UI did not reach expected state');
          }
          await tester.pump(const Duration(milliseconds: 60));
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      Future<void> mount(MediaIdentity identity) => tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: LocalMediaDetailPage(identity: identity)),
          ),
        ),
      );

      try {
        final source = await sources.add(
          kind: MediaSourceKind.localFolder,
          name: 'Fixture Series',
          location: media.path,
          minimumFileSize: 0,
        );
        await sources.scan(source.id);
        final root = (await sources.indexedSource(source.id))
            .singleWhere((item) => item.isSeries);
        final identity = root.identity;
        final episodes = await sources.indexedChildren(identity);
        expect(episodes, hasLength(2));
        debugPrint('TMDB series native: indexed isolated fixture');

        await mount(identity);
        final entry = find.byKey(const ValueKey('tmdb-series-search-entry'));
        await waitFor(() => entry.evaluate().isNotEmpty);
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        final apply = find.byKey(const ValueKey('apply-tmdb-candidate-1'));
        await waitFor(() => apply.evaluate().isNotEmpty);
        await tester.tap(apply);
        await waitFor(
          () => find
              .byKey(const ValueKey('tmdb-series-search-dialog'))
              .evaluate()
              .isEmpty,
        );
        await waitFor(() => find.text('完整剧集 1').evaluate().isNotEmpty);
        expect(find.text('3 季'), findsOneWidget);
        expect(find.text('24 集'), findsOneWidget);

        final seasons = await sources.seasons(identity);
        final firstSeason = seasons.singleWhere((value) => value.number == 1);
        await tester.scrollUntilVisible(
          find.text(firstSeason.title),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text(firstSeason.title));
        await waitFor(
          () => find.textContaining('单集 1-1').evaluate().isNotEmpty,
        );

        final matched = await sources.media(identity);
        expect(matched.posterPath, startsWith(TmdbArtworkStore.prefix));
        final metadata = await container
            .read(tmdbSeriesServiceProvider)
            .metadata(identity);
        expect(metadata!.cast.single.name, '演员甲');
        expect(metadata.numberOfEpisodes, 24);
        for (final episode in episodes) {
          expect(
            (await sources.media(episode.identity)).title,
            startsWith('单集'),
          );
          expect(
            await container
                .read(tmdbSeriesServiceProvider)
                .episodeMetadata(episode.identity),
            isNotNull,
          );
        }
        expect(
          fixture.requests.any((uri) => uri.path.contains('/episode/')),
          isFalse,
        );
        debugPrint('TMDB series native: matching UI committed');

        await container.read(tmdbSeriesServiceProvider).dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        containerDisposed = true;
        await sources.close();
        await fixture.close();

        sources = repository();
        container = containerFor(sources);
        containerDisposed = false;
        await mount(identity);
        await waitFor(() => find.text('完整剧集 1').evaluate().isNotEmpty);
        final reopened = await container
            .read(tmdbSeriesServiceProvider)
            .metadata(identity);
        expect(reopened!.cast.single.name, '演员甲');
        expect(
          await container
              .read(tmdbSeriesServiceProvider)
              .episodeMetadata(episodes.first.identity),
          isNotNull,
        );
        expect(
          await (await container
                  .read(tmdbArtworkStoreProvider)
                  .file(matched.posterPath!))
              .readAsBytes(),
          tmdbFixturePng,
        );
        await waitFor(
          () => find
              .byType(RawImage)
              .evaluate()
              .any(
                (element) =>
                    element.renderObject is RenderImage &&
                    (element.renderObject! as RenderImage).image != null,
              ),
        );
        expect(
          (await sources.database
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM local_series_metadata',
                  )
                  .getSingle())
              .read<int>('n'),
          1,
        );
        expect(
          (await sources.database
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM local_episode_metadata',
                  )
                  .getSingle())
              .read<int>('n'),
          episodes.length,
        );
        for (final table in ['playback_states', 'playback_markers']) {
          expect(
            (await sources.database
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n'),
            0,
          );
        }
        expect(await sources.indexedSource(source.id), hasLength(3));
        debugPrint(
          'TMDB series native: production detail UI -> TV search/detail/seasons/images -> existing episode refresh -> offline SQLite reopen passed',
        );
      } finally {
        if (!containerDisposed) {
          await container.read(tmdbSeriesServiceProvider).dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        if (!containerDisposed) container.dispose();
        await sources.close();
        await fixture.close();
        expect(p.isWithin(temporary.path, sandbox.path), isTrue);
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-tmdb-series-native-'),
        );
        await sandbox.delete(recursive: true);
      }
    },
  );
}
