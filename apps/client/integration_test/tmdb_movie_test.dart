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
    'native local movie match, real HTTP/artwork and offline SQLite reopen',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1150, 800));
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final sandbox = await temporary.createTemp('reelnest-tmdb-native-');
      final media = await Directory(p.join(sandbox.path, 'media')).create();
      final library = await Directory(p.join(sandbox.path, 'library')).create();
      await File(p.join(media.path, 'Film.2020.mkv')).writeAsString('fixture');
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
      ProviderContainer containerFor(SourceRepository sources) =>
          ProviderContainer(
            overrides: [
              sourceRepositoryProvider.overrideWithValue(sources),
              tmdbSettingsRepositoryProvider.overrideWithValue(
                TmdbSettingsRepository(sources.database, store: _Credential()),
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
            fail('Native TMDB UI did not reach expected state');
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
          name: 'Fixture Movies',
          location: media.path,
          minimumFileSize: 0,
        );
        await sources.scan(source.id);
        final identity = (sourceId: source.id, localId: 'Film.2020.mkv');
        debugPrint('TMDB native: indexed isolated fixture');
        await mount(identity);
        final entry = find.byKey(const ValueKey('tmdb-movie-search-entry'));
        await waitFor(() => entry.evaluate().isNotEmpty);
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        final apply = find.byKey(const ValueKey('apply-tmdb-candidate-1'));
        await waitFor(() => apply.evaluate().isNotEmpty);
        await tester.tap(apply);
        await waitFor(
          () => find
              .byKey(const ValueKey('tmdb-movie-search-dialog'))
              .evaluate()
              .isEmpty,
        );
        await waitFor(() => find.text('完整电影 1').evaluate().isNotEmpty);
        debugPrint('TMDB native: matching UI committed');
        final item = await sources.media(identity);
        expect(item.posterPath, startsWith(TmdbArtworkStore.prefix));
        expect(
          await (await container
                  .read(tmdbArtworkStoreProvider)
                  .file(item.posterPath!))
              .exists(),
          isTrue,
        );
        expect(
          (await container.read(tmdbMovieServiceProvider).metadata(identity))!
              .cast
              .first
              .name,
          '甲',
        );
        expect(
          fixture.requests.where((u) => u.path.startsWith('/t/p/')),
          isNotEmpty,
        );
        await container.read(tmdbMovieServiceProvider).dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        containerDisposed = true;
        await sources.close();
        await fixture.close();
        sources = repository();
        container = containerFor(sources);
        containerDisposed = false;
        await mount(identity);
        await waitFor(() => find.text('完整电影 1').evaluate().isNotEmpty);
        expect(
          (await container.read(tmdbMovieServiceProvider).metadata(identity))!
              .runtimeMinutes,
          125,
        );
        expect(
          await (await container
                  .read(tmdbArtworkStoreProvider)
                  .file(item.posterPath!))
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
        for (final table in ['playback_states', 'playback_markers']) {
          expect(
            (await sources.database
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n'),
            0,
          );
        }
        expect(await media.list().length, 1);
        debugPrint(
          'TMDB native: production detail UI -> real loopback search/detail/images -> atomic save -> offline SQLite reopen; no media/history writes passed',
        );
      } finally {
        if (!containerDisposed) {
          await container.read(tmdbMovieServiceProvider).dispose();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        if (!containerDisposed) container.dispose();
        await sources.close();
        await fixture.close();
        expect(p.isWithin(temporary.path, sandbox.path), isTrue);
        expect(p.basename(sandbox.path), startsWith('reelnest-tmdb-native-'));
        await sandbox.delete(recursive: true);
      }
    },
  );
}
