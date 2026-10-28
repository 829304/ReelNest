import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/features/sources/application/automatic_source_scanner.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late Directory root;
  late SourceRepository repository;
  late MediaSource source;
  var identity = 'stable-volume';
  Future<File> file(String name, [String content = 'fixture']) async {
    final f = File(p.join(root.path, name));
    await f.parent.create(recursive: true);
    return f.writeAsString(content);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reelnest-incremental-');
    identity = 'stable-volume';
    repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => identity,
    );
    source = await repository.add(
      kind: MediaSourceKind.localFolder,
      name: 'fixtures',
      location: root.path,
      minimumFileSize: 0,
    );
  });
  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });
  Future<Set<String>> ids() async =>
      (await repository.browse(source.id)).items
          .map((i) => i.identity.localId)
          .toSet();

  test(
    'real file events update the repository through the shared scan queue',
    () async {
      final container = ProviderContainer(
        overrides: [sourceRepositoryProvider.overrideWithValue(repository)],
      );
      final queue = container.read(sourceScansProvider.notifier);
      final scanner = AutomaticSourceScanner(
        sources: () => repository.sources(includeCounts: false),
        isReachable: repository.isReachable,
        schedule: queue.scanChanges,
        isBusy: () => queue.isBusy,
        changes: repository.changes,
        configurationRevision: () => repository.configurationRevision,
        onError: (error, stack) => fail('$error'),
        debounce: const Duration(milliseconds: 25),
      );
      Future<void> until(bool Function(Set<String>) predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (!predicate(await ids())) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Automatic index update timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }

      try {
        await scanner.setInterval(AutomaticScanInterval.hourly);
        final original = await file('Original.mkv');
        await until((items) => items.contains('Original.mkv'));
        final renamed = await original.rename(p.join(root.path, 'Renamed.mkv'));
        await until(
          (items) => items.length == 1 && items.contains('Renamed.mkv'),
        );
        await renamed.delete();
        await until((items) => items.isEmpty);
        expect((await repository.source(source.id)).lastScan, isNull);
      } finally {
        await scanner.dispose();
        container.dispose();
      }
    },
  );

  test('add/change/delete only touches selected files and never advances full scan time', () async {
    final a = await file('A.2020.mkv');
    await file('B.2021.mkv');
    await repository.scan(source.id);
    final lastScan = (await repository.source(source.id)).lastScan;
    await a.delete();
    final c = await file('C.2022.mkv');
    final result = await repository.scan(
      source.id,
      changedPaths: {a.path, c.path, p.join(root.parent.path, 'outside.mkv')},
    );
    expect(result.errors, isEmpty);
    expect(result.importedItems, 1);
    expect(await ids(), {'B.2021.mkv', 'C.2022.mkv'});
    expect((await repository.source(source.id)).lastScan, lastScan);
  });

  test('metadata sidecar refresh reuses the local metadata parser', () async {
    await file('Film.mkv');
    await repository.scan(source.id);
    final nfo = await file(
      'Film.nfo',
      '<movie><title>New title</title><year>2024</year></movie>',
    );
    final result = await repository.scan(source.id, changedPaths: {nfo.path});
    expect(result.errors, isEmpty);
    final media = (await repository.browse(source.id)).items.single;
    expect(media.title, 'New title');
    expect(media.year, 2024);
  });

  test(
    'replaced volume prevents incremental deletion and retains old index',
    () async {
      final a = await file('A.mkv');
      await repository.scan(source.id);
      await a.delete();
      identity = 'replacement-volume';
      await expectLater(
        repository.scan(source.id, changedPaths: {a.path}),
        throwsA(isA<SourceFailure>()),
      );
      expect(await ids(), {'A.mkv'});
    },
  );

  test('identity lost after discovery still prevents deletion', () async {
    final a = await file('A.mkv');
    await repository.scan(source.id);
    await a.delete();
    await expectLater(
      repository.scan(
        source.id,
        changedPaths: {a.path},
        onProgress: (progress) {
          if (progress.processedFiles > 0) identity = 'replacement-volume';
        },
      ),
      throwsA(isA<SourceFailure>()),
    );
    expect(await ids(), {'A.mkv'});
  });

  test('file recreated after its missing event is not deleted', () async {
    final a = await file('A.mkv');
    await repository.scan(source.id);
    await a.delete();
    await repository.scan(
      source.id,
      changedPaths: {a.path},
      onProgress: (progress) {
        if (progress.processedFiles > 0) a.writeAsStringSync('recreated');
      },
    );
    expect(await ids(), {'A.mkv'});
  });

  test('hidden ancestors and directory links cannot introduce media', () async {
    final hidden = await file('.hidden/A.mkv');
    final external = await Directory.systemTemp.createTemp(
      'reelnest-incremental-external-',
    );
    final link = Link(p.join(root.path, 'linked'));
    try {
      await File(p.join(external.path, 'B.mkv')).writeAsString('fixture');
      await link.create(external.path);
      await repository.scan(
        source.id,
        changedPaths: {hidden.path, p.join(link.path, 'B.mkv')},
      );
      expect(await ids(), isEmpty);
    } finally {
      if (await link.exists()) await link.delete();
      await external.delete(recursive: true);
    }
  });

  test('deleting the last episode removes only its orphan series', () async {
    final episode = await file('Show/Show.S01E01.mkv');
    await file('Movie.mkv');
    await repository.scan(source.id);
    await episode.delete();
    await repository.scan(source.id, changedPaths: {episode.path});
    expect(await ids(), {'Movie.mkv'});
  });
}
