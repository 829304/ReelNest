import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late Directory sandbox;
  late File file;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-startup-test-');
    file = File(p.join(sandbox.path, 'library.sqlite'));
  });
  tearDown(() async {
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-startup-test-'));
    await sandbox.delete(recursive: true);
  });

  test(
    'real background connection creates and reopens an empty current database',
    () async {
      for (var i = 0; i < 2; i++) {
        final database = LibraryDatabase(
          NativeDatabase.createInBackground(file),
        );
        try {
          final rows = await database
              .customSelect('SELECT * FROM sources')
              .get()
              .timeout(const Duration(seconds: 10));
          expect(rows, isEmpty);
          expect(
            await database
                .customSelect('SELECT * FROM ignored_health_issues')
                .get(),
            isEmpty,
          );
        } finally {
          await database.close();
        }
      }
    },
  );

  test(
    'old development version produces a specific error without resetting data',
    () async {
      final old = _VersionTwo(NativeDatabase(file));
      await old.customStatement('SELECT 1');
      await old.close();
      final database = LibraryDatabase(NativeDatabase.createInBackground(file));
      try {
        await expectLater(
          database
              .customSelect('SELECT * FROM sources')
              .get()
              .timeout(const Duration(seconds: 10)),
          throwsA(
            predicate<Object>(
              (error) =>
                  LibrarySchemaMismatch.isCause(error) &&
                  sourceErrorMessage(error) == LibrarySchemaMismatch.message,
            ),
          ),
        );
        expect(
          sourceErrorMessage(const LibrarySchemaMismatch()),
          LibrarySchemaMismatch.message,
        );
      } finally {
        await database.close();
      }
      final preserved = _VersionTwo(NativeDatabase(file));
      try {
        expect(
          (await preserved.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          2,
        );
      } finally {
        await preserved.close();
      }
    },
  );

  test('same-version incomplete development schema is rejected without changing it', () async {
    final old = LibraryDatabase(NativeDatabase(file));
    await old.customStatement(
      'ALTER TABLE sources DROP COLUMN access_identity',
    );
    await old.close();
    final database = LibraryDatabase(NativeDatabase.createInBackground(file));
    try {
      await expectLater(
        database
            .customSelect('SELECT * FROM sources')
            .get()
            .timeout(const Duration(seconds: 10)),
        throwsA(
          predicate<Object>(
            (error) =>
                LibrarySchemaMismatch.isCause(error) &&
                sourceErrorMessage(error) == LibrarySchemaMismatch.message,
          ),
        ),
      );
    } finally {
      await database.close();
    }
    // Guard only: no upgrade or destructive recovery strategy is installed.
    expect(await file.exists(), isTrue);
  });
}

class _VersionTwo extends LibraryDatabase {
  _VersionTwo(super.executor);
  @override
  int get schemaVersion => 2;
}
