import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/library_health.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/health/application/missing_index_cleanup.dart';
import 'package:reelnest/features/health/domain/local_health_evaluator.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/directory_safety.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late Directory sandbox;
  late SourceRepository repository;
  String? mount = 'test-volume-A';
  Future<File> write(String relative) async {
    final file = File(p.join(sandbox.path, relative));
    await file.parent.create(recursive: true);
    return file.writeAsString('index fixture');
  }

  Future<MediaSource> source(String relative) async {
    final root = await Directory(p.join(sandbox.path, relative))
        .create(recursive: true);
    return repository.add(
      kind: MediaSourceKind.localFolder,
      name: relative,
      location: root.path,
      minimumFileSize: 0,
    );
  }

  Future<LibraryHealthSnapshot> health() async => LocalHealthEvaluator(
    paths: p.context,
    exists: (path) async =>
        await FileSystemEntity.type(path) != FileSystemEntityType.notFound,
    sourceAvailable: repository.isSafeDirectory,
  ).evaluate(await repository.inventory(), cancellation: ScanCancellation());

  setUp(() async {
    mount = 'test-volume-A';
    sandbox = await Directory.systemTemp.createTemp('reelnest-cleanup-test-');
    repository = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => mount,
    );
  });
  tearDown(() async {
    await repository.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, sandbox.absolute.path),
      isTrue,
    );
    expect(
      p.basename(sandbox.path).startsWith('reelnest-cleanup-test-'),
      isTrue,
    );
    await sandbox.delete(recursive: true);
  });

  test(
    'cleanup is scoped to the requested source and never removes present media',
    () async {
      final missing = await write('a/Film.mkv');
      final present = await write('a/Other.mkv');
      await write('b/Film.mkv');
      final a = await source('a'), b = await source('b');
      await repository.scan(a.id);
      await repository.scan(b.id);
      await missing.delete();
      final snapshot = await health();
      final result = await MissingIndexCleanup(repository)
          .remove(snapshot, snapshot.safeMissing);
      expect(result, (removed: 1, retained: 0));
      expect(
        (await repository.browse(a.id)).items.single.identity.localId,
        'Other.mkv',
      );
      expect((await repository.browse(b.id)).total, 1);
      expect(await present.exists(), isTrue);
    },
  );

  test('removing an episode retains siblings and removes only the last orphan parent', () async {
    final first = await write('series/Show/Season 1/Show.S01E01.mkv');
    final second = await write('series/Show/Season 1/Show.S01E02.mkv');
    final series = await source('series');
    await repository.scan(series.id);
    await first.delete();
    var snapshot = await health();
    await MissingIndexCleanup(repository)
        .remove(snapshot, snapshot.safeMissing);
    expect(
      (await repository.inventory()).items
          .where((i) => i.identity.sourceId == series.id)
          .length,
      2,
    ); // parent and sibling
    expect(await second.exists(), isTrue);
    await second.delete();
    snapshot = await health();
    await MissingIndexCleanup(repository)
        .remove(snapshot, snapshot.safeMissing);
    expect((await repository.inventory()).items, isEmpty);
  });

  test('restored files invalidate a stale cleanup request', () async {
    final file = await write('a/Film.mkv');
    final a = await source('a');
    await repository.scan(a.id);
    await file.delete();
    final snapshot = await health();
    await file.writeAsString('restored');
    final result = await MissingIndexCleanup(repository)
        .remove(snapshot, snapshot.safeMissing);
    expect(result, (removed: 0, retained: 1));
    expect((await repository.browse(a.id)).total, 1);
    expect(await file.readAsString(), 'restored');
  });

  test('source relocation invalidates confirmation for its old path', () async {
    final file = await write('a/Film.mkv');
    final a = await source('a');
    await repository.scan(a.id);
    await file.delete();
    final snapshot = await health();
    final relocated = await Directory(p.join(sandbox.path, 'relocated'))
        .create();
    await repository.relocate(a.id, relocated.path);
    await expectLater(
      MissingIndexCleanup(repository).remove(snapshot, snapshot.safeMissing),
      throwsA(isA<SourceFailure>()),
    );
    expect((await repository.browse(a.id)).total, 1);
  });

  test('changed or unknown mount at an empty readable directory protects the entire index', () async {
    final file = await write('a/Film.mkv');
    final a = await source('a');
    await repository.scan(a.id);
    final timestamp = (await repository.source(a.id)).lastScan;
    await file.delete();
    final snapshot = await health();
    for (final state in <String?>['test-volume-B', null]) {
      mount = state;
      expect(await Directory(a.location).exists(), isTrue);
      expect(
        await repository.isReachable(await repository.source(a.id)),
        isFalse,
      );
      expect(() => repository.scan(a.id), throwsA(isA<SourceFailure>()));
      final current = await health();
      expect(current.offline, contains(a.id));
      expect(current.safeMissing, isEmpty);
      expect(
        await MissingIndexCleanup(repository)
            .remove(snapshot, snapshot.safeMissing),
        (removed: 0, retained: 1),
      );
      expect((await repository.browse(a.id)).total, 1);
      expect((await repository.source(a.id)).lastScan, timestamp);
    }
    mount = 'test-volume-A';
    expect(await repository.isReachable(await repository.source(a.id)), isTrue);
  });

  test(
    'mount change at the end of enumeration prevents pruning old rows',
    () async {
      final file = await write('a/Old.mkv');
      final a = await source('a');
      await repository.scan(a.id);
      final stamp = (await repository.source(a.id)).lastScan;
      await file.delete();
      await write('a/New.mkv');
      await expectLater(
        repository.scan(
          a.id,
          onProgress: (progress) {
            if (progress.processedFiles > 0) mount = 'test-volume-B';
          },
        ),
        throwsA(isA<SourceFailure>()),
      );
      expect((await repository.browse(a.id)).total, 2);
      expect((await repository.source(a.id)).lastScan, stamp);
    },
  );

  test(
    'mount loss during file validation retires cleanup candidates',
    () async {
      final file = await write('a/Film.mkv');
      final a = await source('a');
      await repository.scan(a.id);
      await file.delete();
      final snapshot = await health();
      final cleanup = MissingIndexCleanup(
        repository,
        missingProbe: (root, path) async {
          final result = await fileDefinitelyMissing(root, path);
          mount = null;
          return result;
        },
      );
      expect(await cleanup.remove(snapshot, snapshot.safeMissing), (
        removed: 0,
        retained: 1,
      ));
      expect((await repository.browse(a.id)).total, 1);
    },
  );

  test(
    'denied parent listing retains a candidate rather than reporting absence',
    () async {
      final file = await write('a/Film.mkv');
      final a = await source('a');
      await repository.scan(a.id);
      await file.delete();
      final snapshot = await health();
      final cleanup = MissingIndexCleanup(
        repository,
        missingProbe: (_, _) async {
          throw const FileSystemException('access denied');
        },
      );
      expect(await cleanup.remove(snapshot, snapshot.safeMissing), (
        removed: 0,
        retained: 1,
      ));
      expect((await repository.browse(a.id)).total, 1);
    },
  );

  test(
    'cleanup gates scans and mutations and detects a bypassed SQL edit',
    () async {
      final file = await write('a/Film.mkv');
      final a = await source('a');
      await repository.scan(a.id);
      await file.delete();
      final snapshot = await health();
      final entered = Completer<void>(), release = Completer<void>();
      final cleanup = MissingIndexCleanup(
        repository,
        missingProbe: (_, _) async {
          entered.complete();
          await release.future;
          return true;
        },
      );
      final work = cleanup.remove(snapshot, snapshot.safeMissing);
      final assertion = expectLater(work, throwsA(isA<SourceFailure>()));
      await entered.future;
      expect(() => repository.scan(a.id), throwsA(isA<SourceFailure>()));
      await expectLater(
        repository.updateSettings(a.id, name: 'Changed'),
        throwsA(isA<SourceFailure>()),
      );
      await expectLater(repository.remove(a.id), throwsA(isA<SourceFailure>()));
      await expectLater(
        repository.relocate(a.id, a.location),
        throwsA(isA<SourceFailure>()),
      );
      await repository.database.customStatement(
        "UPDATE media SET title = 'external edit' WHERE source_id = ?",
        [a.id],
      );
      release.complete();
      await assertion;
      expect((await repository.browse(a.id)).total, 1);
      // Failed cleanup releases the gate and permits later operations.
      await repository.updateSettings(a.id, name: 'After cleanup');
    },
  );

  test('scan already in progress prevents cleanup from starting', () async {
    await write('a/Film.mkv');
    final a = await source('a');
    await repository.scan(a.id);
    final snapshot = await health();
    final scan = repository.scan(a.id);
    await expectLater(
      MissingIndexCleanup(repository)
          .remove(snapshot, {(sourceId: a.id, localId: 'Film.mkv')}),
      throwsA(isA<SourceFailure>()),
    );
    await scan;
  });

  test('delete failure rolls back the whole batch', () async {
    final aFile = await write('a/A.mkv'), bFile = await write('a/B.mkv');
    final a = await source('a');
    await repository.scan(a.id);
    await aFile.delete();
    await bFile.delete();
    final snapshot = await health();
    await repository.database.customStatement('''
      CREATE TEMP TRIGGER reject_delete BEFORE DELETE ON media
      WHEN OLD.local_id = 'B.mkv'
      BEGIN SELECT RAISE(ABORT, 'injected delete failure'); END
    ''');
    await expectLater(
      MissingIndexCleanup(repository).remove(snapshot, snapshot.safeMissing),
      throwsA(isA<Exception>()),
    );
    expect((await repository.browse(a.id)).total, 2);
    await repository.database.customStatement('DROP TRIGGER reject_delete');
    expect(
      await MissingIndexCleanup(repository)
          .remove(snapshot, snapshot.safeMissing),
      (removed: 2, retained: 0),
    );
  });

  test(
    'excluded nested sources prevent deleting their items from a parent source',
    () async {
      final file = await write('a/nested/Film.mkv');
      final a = await source('a');
      final nested = await source('a/nested');
      await repository.updateSettings(
        nested.id,
        options: SourceOptions(includeInHealthCheck: false),
      );
      await repository.scan(a.id);
      await file.delete();
      final snapshot = await health();
      expect(snapshot.safeMissing, isEmpty);
      expect(
        await MissingIndexCleanup(repository)
            .remove(snapshot, {(sourceId: a.id, localId: 'nested/Film.mkv')}),
        (removed: 0, retained: 1),
      );
      expect((await repository.browse(a.id)).total, 1);
    },
  );

  test(
    'unknown initial mount remains disconnected and cannot publish a scan',
    () async {
      mount = null;
      final a = await source('unknown');
      expect(a.accessIdentity, isNull);
      expect(await repository.isReachable(a), isFalse);
      await expectLater(repository.scan(a.id), throwsA(isA<SourceFailure>()));
      expect((await repository.source(a.id)).lastScan, isNull);
      mount = 'confirmed-volume';
      await repository.relocate(a.id, a.location);
      expect(
        await repository.isReachable(await repository.source(a.id)),
        isTrue,
      );
    },
  );

  test('real directory identity is stable and unreadable/missing roots are unknown', () async {
    final first = await directoryIdentity(sandbox.path);
    expect(first, isNotNull);
    expect(await directoryIdentity(sandbox.path), first);
    expect(await directoryIdentity(p.join(sandbox.path, 'missing')), isNull);
  });

  test(
    'absence proof handles missing ancestors and refuses outside-root paths',
    () async {
      final present = await write('a/nested/Film.mkv');
      final root = p.join(sandbox.path, 'a');
      expect(await fileDefinitelyMissing(root, present.path), isFalse);
      await present.parent.delete(recursive: true);
      expect(await fileDefinitelyMissing(root, present.path), isTrue);
      expect(
        await fileDefinitelyMissing(
          root,
          p.join(sandbox.path, 'elsewhere.mkv'),
        ),
        isFalse,
      );
    },
  );

  test(
    'Linux UUID replacement at a reused device name blocks scan and cleanup',
    () async {
      await repository.close();
      var uuid = 'volume-a';
      repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) => linuxDirectoryIdentity(
          '/mnt/Media',
          readMountInfo: () async =>
              '21 1 8:17 / /mnt/Media rw - ext4 /dev/sdb1 rw',
          volumeUuid: (_) async => uuid,
        ),
      );
      final file = await write('a/Film.mkv');
      final a = await source('a');
      await repository.scan(a.id);
      final timestamp = (await repository.source(a.id)).lastScan;
      await file.delete();
      final snapshot = await health();
      expect(snapshot.safeMissing, hasLength(1));
      // Path, device name and device number are deliberately unchanged.
      uuid = 'volume-b';
      expect(await Directory(a.location).exists(), isTrue);
      expect(
        await repository.isReachable(await repository.source(a.id)),
        isFalse,
      );
      await expectLater(repository.scan(a.id), throwsA(isA<SourceFailure>()));
      expect(
        await MissingIndexCleanup(repository)
            .remove(snapshot, snapshot.safeMissing),
        (removed: 0, retained: 1),
      );
      expect((await repository.browse(a.id)).total, 1);
      expect((await repository.source(a.id)).lastScan, timestamp);
    },
  );

  test('a block mount without a stable volume UUID is unknown', () {
    const info = '21 1 8:17 / /mnt/Media rw - ext4 /dev/sdb1 rw';
    expect(linuxMountIdentity('/mnt/Media/Film.mkv', info), isNull);
  });

  test('mount parsers select the closest mount and strip network user information', () {
    const rootLine = '1 0 8:1 / / rw - ext4 /dev/root rw';
    const uuids = {'8:1': 'root-uuid'};
    const nasLine =
        r'2 1 0:9 / /mnt/NAS\040Media rw - cifs //user:secret@nas/Media rw';
    final mounted = linuxMountIdentity(
      '/mnt/NAS Media/Film.mkv',
      '$rootLine\n$nasLine',
      volumeUuids: uuids,
    );
    expect(
      mounted,
      isNot(
        linuxMountIdentity(
          '/mnt/NAS Media/Film.mkv',
          rootLine,
          volumeUuids: uuids,
        ),
      ),
    );
    expect(mounted, contains('//nas/Media'));
    expect(mounted, isNot(contains('secret')));
    expect(
      linuxMountIdentity(
        '/mnt/NAS Mediabox/Film.mkv',
        '$rootLine\n$nasLine',
        volumeUuids: uuids,
      ),
      linuxMountIdentity('/other', rootLine, volumeUuids: uuids),
    );
    const table =
        '/dev/disk1 on / (apfs, local)\n//user:secret@nas/Media on /Volumes/Media (smbfs, nodev)';
    expect(
      macMountIdentity('/Volumes/Media/Film.mkv', table),
      contains('//nas/Media'),
    );
    expect(
      macMountIdentity('/Volumes/Media/Film.mkv', table),
      isNot(contains('secret')),
    );
    expect(
      macMountIdentity('/Volumes/Media/Film.mkv', table),
      isNot(
        macMountIdentity(
          '/Volumes/Media/Film.mkv',
          '/dev/disk1 on / (apfs, local)',
        ),
      ),
    );
  });
}
