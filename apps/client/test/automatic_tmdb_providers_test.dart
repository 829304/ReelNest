import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/application/automatic_tmdb_providers.dart';
import 'package:reelnest/features/metadata/application/tmdb_batch_providers.dart';
import 'package:reelnest/features/metadata/application/tmdb_batch_service.dart';
import 'package:reelnest/features/metadata/application/tmdb_providers.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_client.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/preference_store.dart';

class _Store implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> write(String value) async {}
}

class _Batch extends TmdbBatchService {
  _Batch(
    SourceRepository sources,
    TmdbSettingsRepository settings,
    TmdbVideoService series,
  ) : super(
        sources: sources,
        settings: settings,
        series: series,
        isScanning: () => false,
      );
  int runs = 0;
  @override
  Future<void> startAutomatic(ScanCancellation token) async {
    token.check();
    runs++;
  }
}

void main() {
  for (final restore in [false, true]) {
    testWidgets('startup restores interval=$restore without an immediate run', (
      tester,
    ) async {
      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      final settings = TmdbSettingsRepository(
        repository.database,
        store: _Store(),
      );
      final series = TmdbVideoService(
        sources: repository,
        settings: settings,
        client: TmdbClient(),
        artwork: TmdbArtworkStore(),
      );
      final batch = _Batch(repository, settings, series);
      if (restore) {
        await settings.setAutomaticMatchInterval(AutomaticScanInterval.hourly);
      }
      var constructions = 0;
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(repository),
          tmdbSettingsRepositoryProvider.overrideWithValue(settings),
          tmdbBatchServiceProvider.overrideWith((ref) {
            constructions++;
            return batch;
          }),
        ],
      );
      final matcher = container.read(automaticTmdbMatcherProvider);
      try {
        await container.read(tmdbSettingsProvider.future);
        expect(batch.runs, 0);
        expect(constructions, 0);
        expect(container.exists(sourceScansProvider), isFalse);
        if (restore) {
          await tester.pump(const Duration(minutes: 30));
          // Unrelated settings changes keep the original hourly deadline.
          await container
              .read(tmdbSettingsProvider.notifier)
              .setLanguage('en-US');
          await tester.pump(const Duration(minutes: 30));
          expect(batch.runs, 1);
          expect(constructions, 1);
          await container
              .read(tmdbSettingsProvider.notifier)
              .setAutomaticMatchInterval(AutomaticScanInterval.disabled);
          await tester.pump(const Duration(days: 2));
          expect(batch.runs, 1);
        } else {
          await tester.pump(const Duration(days: 2));
          expect(batch.runs, 0);
          expect(constructions, 0);
        }
        expect(
          await repository.database.preferenceValue('automaticScanInterval'),
          isNull,
        );
      } finally {
        await matcher.dispose();
        container.dispose();
        await batch.dispose();
        await series.dispose();
        await repository.close();
      }
    });
  }
}
