import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/app_failure.dart';
import 'package:reelnest/platform/windows_data_protection.dart';
import 'package:reelnest/storage/portable_credential_store.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/player/playback_diagnostics.dart';

Future<Link> _directoryAlias(String path, String target) async {
  if (!Platform.isWindows) return Link(path).create(target);
  // Directory junctions do not require Windows symbolic-link privileges.
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-Command',
      'New-Item -ItemType Junction -Path \$env:REELNEST_TEST_JUNCTION '
          '-Target \$env:REELNEST_TEST_TARGET -ErrorAction Stop | Out-Null',
    ],
    environment: {
      'REELNEST_TEST_JUNCTION': path,
      'REELNEST_TEST_TARGET': target,
    },
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return Link(path);
}

void main() {
  // Rejected LazyDatabase openers have no native executor to close, but Drift
  // rethrows the opening error from close and retains its debug instance count.
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning,
  );
  late Directory sandbox;
  setUp(
    () async => sandbox = await Directory.systemTemp.createTemp(
      'reelnest-portable-test-',
    ),
  );
  tearDown(() async {
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-portable-test-'));
    await sandbox.delete(recursive: true);
  });

  test(
    'portable paths are anchored to program directory, prepare stays inside it',
    () async {
      final paths = RuntimeStoragePaths(root: sandbox, portable: true);
      await paths.prepare();
      expect((await paths.support()).path, p.join(sandbox.path, 'userdata'));
      expect((await paths.logs()).path, p.join(sandbox.path, 'log'));
      expect((await paths.cache()).path, p.join(sandbox.path, 'cache'));
      expect((await paths.temporary()).path, p.join(sandbox.path, 'temp'));
      expect(
        (await paths.credentials()).path,
        p.join(sandbox.path, 'userdata', 'credentials'),
      );
      expect(await sandbox.list().length, 4);
    },
  );
  test('an unusable portable directory fails without falling back', () async {
    await File(p.join(sandbox.path, 'cache')).writeAsString('block directory');
    await expectLater(
      RuntimeStoragePaths(root: sandbox, portable: true).prepare(),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await File(p.join(sandbox.path, 'cache')).readAsString(),
      'block directory',
    );
  });
  test(
    'database and default diagnostics use the injected portable directory',
    () async {
      final paths = RuntimeStoragePaths.current;
      final db = LibraryDatabase.open();
      await db.customSelect('SELECT 1').get();
      await db.close();
      expect(
        await File(
          p.join((await paths.support()).path, 'library', 'reelnest.sqlite'),
        ).exists(),
        isTrue,
      );
      final logs = PlaybackDiagnostics(writerId: '123-456');
      logs.begin().event('portable_test');
      await logs.close();
      expect(
        await File(p.join((await paths.logs()).path, 'playback-123-456.jsonl'))
            .exists(),
        isTrue,
      );
    },
  );

  LibraryDatabase database(RuntimeStoragePaths paths) => runZoned(
    LibraryDatabase.open,
    zoneValues: {RuntimeStoragePaths.zoneKey: paths},
  );

  Future<void> closeRejectedDatabase(LibraryDatabase db, Link alias) async {
    try {
      await expectLater(db.close(), throwsA(isA<FileSystemException>()));
    } finally {
      await alias.delete();
    }
  }

  test(
    'startup and database reject a library junction outside the program',
    () async {
      final program = await Directory(p.join(sandbox.path, 'program')).create();
      final outside = await Directory(p.join(sandbox.path, 'outside')).create();
      await Directory(p.join(program.path, 'userdata')).create();
      final alias = await _directoryAlias(
        p.join(program.path, 'userdata', 'library'),
        outside.path,
      );
      final paths = RuntimeStoragePaths(root: program, portable: true);
      final db = database(paths);
      try {
        await expectLater(paths.prepare(), throwsA(isA<FileSystemException>()));
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          await outside.list().toList(),
          isEmpty,
          reason: 'No database or write probe may escape',
        );
      } finally {
        await closeRejectedDatabase(db, alias);
      }
    },
  );

  test(
    'database rechecks a library junction installed after startup preflight',
    () async {
      final program = await Directory(p.join(sandbox.path, 'program')).create();
      final outside = await Directory(p.join(sandbox.path, 'outside')).create();
      final paths = RuntimeStoragePaths(root: program, portable: true);
      await paths.prepare();
      final libraryPath = p.join(program.path, 'userdata', 'library');
      await Directory(libraryPath)
          .delete(); // The owned preflight directory is empty.
      final alias = await _directoryAlias(libraryPath, outside.path);
      final db = database(paths);
      try {
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outside.list().toList(), isEmpty);
      } finally {
        await closeRejectedDatabase(db, alias);
      }
    },
  );

  test(
    'external userdata junction is rejected before creating library children',
    () async {
      final program = await Directory(p.join(sandbox.path, 'program')).create();
      final outside = await Directory(p.join(sandbox.path, 'outside')).create();
      final alias = await _directoryAlias(
        p.join(program.path, 'userdata'),
        outside.path,
      );
      final paths = RuntimeStoragePaths(root: program, portable: true);
      final db = database(paths);
      try {
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outside.list().toList(), isEmpty);
      } finally {
        await closeRejectedDatabase(db, alias);
      }
    },
  );

  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    test('database rejects an external SQLite file link ($suffix)', () async {
      final program = await Directory(p.join(sandbox.path, 'program')).create();
      final paths = RuntimeStoragePaths(root: program, portable: true);
      await paths.prepare();
      final outside = await File(p.join(sandbox.path, 'outside-file'))
          .writeAsString('unchanged fixture');
      final alias = await Link(
        p.join(program.path, 'userdata', 'library', 'reelnest.sqlite$suffix'),
      ).create(outside.path);
      final db = database(paths);
      try {
        await expectLater(paths.prepare(), throwsA(isA<FileSystemException>()));
        await expectLater(
          db.customSelect('SELECT 1').get(),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outside.readAsString(), 'unchanged fixture');
        if (suffix.isNotEmpty) {
          expect(
            await File(
              p.join(program.path, 'userdata', 'library', 'reelnest.sqlite'),
            ).exists(),
            isFalse,
          );
        }
      } finally {
        await closeRejectedDatabase(db, alias);
      }
    });
  }

  test(
    'a library junction inside the program uses its verified real directory',
    () async {
      final program = await Directory(p.join(sandbox.path, 'program')).create();
      final inside = await Directory(p.join(program.path, 'internal-library'))
          .create();
      await Directory(p.join(program.path, 'userdata')).create();
      final alias = await _directoryAlias(
        p.join(program.path, 'userdata', 'library'),
        inside.path,
      );
      final paths = RuntimeStoragePaths(root: program, portable: true);
      final db = database(paths);
      try {
        await paths.prepare();
        await db.customSelect('SELECT 1').get();
        expect(
          await File(p.join(inside.path, 'reelnest.sqlite')).exists(),
          isTrue,
        );
      } finally {
        await db.close();
        await alias.delete();
      }
    },
  );

  group('Windows encrypted credentials', () {
    PortableCredentialStore store(String key) => PortableCredentialStore(
      directory: () async => Directory(p.join(sandbox.path, 'credentials')),
      key: key,
    );
    test('DPAPI is authenticated and account-protected, not plaintext', () {
      final protection = WindowsDataProtection();
      final plain = utf8.encode('fixture-secret');
      final cipher = protection.protect(plain);
      expect(cipher, isNot(plain));
      expect(protection.unprotect(cipher), plain);
      cipher[cipher.length - 1] ^= 1;
      expect(() => protection.unprotect(cipher), throwsFormatException);
    });
    test(
      'independent keys, atomic overwrite and clear preserve other sessions',
      () async {
        await Future.wait([
          for (var i = 0; i < 10; i++) store('source-$i').write('token-$i'),
        ]);
        await store('source-1').write('rotated');
        await store('source-2').clear();
        expect(await store('source-1').read(), 'rotated');
        expect(await store('source-2').read(), isNull);
        expect(await store('source-9').read(), 'token-9');
        final files = await Directory(p.join(sandbox.path, 'credentials'))
            .list()
            .where((f) => f is File)
            .cast<File>()
            .toList();
        expect(files.length, 9);
        for (final file in files) {
          expect(
            utf8.decode(await file.readAsBytes(), allowMalformed: true),
            isNot(contains('token-')),
          );
        }
      },
    );
    test('failed replacement retains previous credentials; corrupt data is never removed', () async {
      final value = store('source');
      await value.write('previous');
      await expectLater(
        value.write('x' * (1024 * 1024)),
        throwsA(isA<AppFailure>()),
      );
      expect(await value.read(), 'previous');
      final file =
          (await Directory(
                p.join(sandbox.path, 'credentials'),
              ).list().where((f) => f is File).toList()).single
              as File;
      await file.writeAsBytes([1, 2, 3]);
      await expectLater(value.read(), throwsA(isA<AppFailure>()));
      expect(await file.readAsBytes(), [1, 2, 3]);
    });
  }, skip: !Platform.isWindows);
}
