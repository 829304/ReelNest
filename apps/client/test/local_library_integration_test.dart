import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/health/application/health_providers.dart';
import 'package:reelnest/features/health/data/health_repository.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late Directory sandbox;
  late SourceRepository repository;
  SourceRepository make(LibraryDatabase db) => SourceRepository(
    database: db,
    adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
  );
  Future<File> write(String path, String content) async {
    final file = File(p.join(sandbox.path, path));
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  Future<MediaSource> add() => repository.add(
    kind: MediaSourceKind.localFolder,
    name: 'Test',
    location: sandbox.path,
    minimumFileSize: 0,
  );
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp(
      'reelnest-health-regression-',
    );
    repository = make(LibraryDatabase(NativeDatabase.memory()));
  });
  tearDown(() async {
    await repository.close();
    // The only recursive target is the unique temporary directory created here.
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, sandbox.absolute.path),
      isTrue,
    );
    expect(p.basename(sandbox.path), startsWith('reelnest-health-regression-'));
    await sandbox.delete(recursive: true);
  });

  test('series NFO, artwork, seasons, reopen and complete-scan pruning stay source scoped', () async {
    await repository.close();
    final dbFile = File(p.join(sandbox.path, 'library.sqlite'));
    repository = make(LibraryDatabase(NativeDatabase(dbFile)));
    await write(
      'Show/tvshow.nfo',
      '<tvshow><title>NFO Show</title><year>2021</year><plot>Series plot</plot></tvshow>',
    );
    await write('Show/poster.jpg', 'artwork fixture');
    await write('Show/Season 1/Show.S01E01.mkv', 'video fixture');
    final second = await write(
      'Show/Season 2/Show.S02E03.mkv',
      'video fixture',
    );
    final source = await add();
    final scan = await repository.scan(source.id);
    expect(scan.errors, isEmpty);
    expect(scan.importedItems, 2);
    final series = (await repository.browse(
      source.id,
      topLevelOnly: true,
    )).items.single;
    expect(series.isSeries, isTrue);
    expect(series.title, 'NFO Show');
    expect(series.year, 2021);
    expect(series.overview, 'Series plot');
    expect(series.posterPath, 'Show/poster.jpg');
    expect((await repository.seasons(series.identity)).map((s) => s.number), [
      1,
      2,
    ]);
    final episodes = await repository.episodes(
      series.identity,
      seasonNumber: 2,
    );
    expect(episodes.items.single.episodeNumber, 3);
    await repository.close();
    repository = make(LibraryDatabase(NativeDatabase(dbFile)));
    expect(
      (await repository.media(series.identity)).posterPath,
      'Show/poster.jpg',
    );
    await second.delete();
    await repository.scan(source.id);
    expect((await repository.seasons(series.identity)).map((s) => s.number), [
      1,
    ]);
    expect((await repository.browse(source.id)).total, 1);
  });

  test('health detects a removed file without deleting the index; ignored issues survive reopen', () async {
    await repository.close();
    final dbFile = File(p.join(sandbox.path, 'library.sqlite'));
    repository = make(LibraryDatabase(NativeDatabase(dbFile)));
    final file = await write('Film.2020.mkv', 'video fixture');
    final source = await add();
    await repository.scan(source.id);
    final indexed = (await repository.browse(source.id)).items.single;
    await file.delete();
    final health = await LocalHealthEvaluator(
      paths: p.context,
      exists: (path) async =>
          await FileSystemEntity.type(path) != FileSystemEntityType.notFound,
    ).evaluate(await repository.inventory(), cancellation: ScanCancellation());
    expect(health.missing, {indexed.identity});
    expect(health.safeMissing, {indexed.identity});
    expect((await repository.browse(source.id)).total, 1);
    var preferences = HealthRepository(repository.database);
    final key = (
      kind: HealthIssueKind.missingFile,
      sourceId: source.id,
      localId: indexed.identity.localId,
    );
    await preferences.ignore(key);
    await preferences.ignore(key);
    expect((await preferences.ignored()).length, 1);
    await preferences.close();
    await repository.close();
    repository = make(LibraryDatabase(NativeDatabase(dbFile)));
    preferences = HealthRepository(repository.database);
    expect(await preferences.ignored(), {key});
    expect(health.excluding(await preferences.ignored()).missing, isEmpty);
    await preferences.restore();
    expect(await preferences.ignored(), isEmpty);
    await preferences.close();
  });

  test('saving an excluded source invalidates an in-flight health probe and rejects late results', () async {
    final source = await add();
    final entered = Completer<void>(), gate = Completer<bool>();
    var probes = 0;
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(repository),
        localHealthEvaluatorProvider.overrideWithValue(
          LocalHealthEvaluator(
            paths: p.context,
            exists: (_) {
              probes++;
              if (!entered.isCompleted) entered.complete();
              return gate.future;
            },
          ),
        ),
      ],
    );
    final subscription = container.listen(rawLibraryHealthProvider, (_, _) {});
    try {
      await entered.future;
      await repository.updateSettings(
        source.id,
        options: SourceOptions(includeInHealthCheck: false),
      );
      await container.pump();
      final fresh = await container.read(rawLibraryHealthProvider.future);
      expect(fresh.offline, isEmpty);
      expect(
        fresh.inventory.sources.single.options.includeInHealthCheck,
        isFalse,
      );
      gate.complete(false);
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      expect(
        container.read(rawLibraryHealthProvider).requireValue.offline,
        isEmpty,
      );
      expect(probes, 1);
    } finally {
      if (!gate.isCompleted) gate.complete(true);
      subscription.close();
      container.dispose();
    }
  });

  test(
    'ignore and restore recompute visible results without filesystem probes',
    () async {
      await write('Film.mkv', 'video');
      final source = await add();
      await repository.scan(source.id);
      var probes = 0;
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(repository),
          localHealthEvaluatorProvider.overrideWithValue(
            LocalHealthEvaluator(
              paths: p.context,
              exists: (path) async {
                probes++;
                return path == source.location;
              },
            ),
          ),
        ],
      );
      final subscription = container.listen(libraryHealthProvider, (_, _) {});
      try {
        final first = await container.read(libraryHealthProvider.future);
        final id = first.missing.single;
        final count = probes;
        await container.read(healthRepositoryProvider).ignore((
          kind: HealthIssueKind.missingFile,
          sourceId: id.sourceId,
          localId: id.localId,
        ));
        await container.pump();
        expect(
          (await container.read(libraryHealthProvider.future)).missing,
          isEmpty,
        );
        await container.read(healthRepositoryProvider).restore();
        await container.pump();
        expect((await container.read(libraryHealthProvider.future)).missing, {
          id,
        });
        expect(probes, count);
      } finally {
        subscription.close();
        container.dispose();
      }
    },
  );
}
