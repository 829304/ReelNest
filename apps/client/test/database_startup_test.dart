import 'dart:io';
import 'dart:async';

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

  for (final rollback in [false, true]) {
    test(
      'close drains background transaction ${rollback ? 'rollback' : 'commit'} and rejects new work',
      () async {
        final database = LibraryDatabase(
          NativeDatabase.createInBackground(file),
        );
        await database.customStatement('SELECT 1');
        final entered = Completer<void>(), release = Completer<void>();
        final work = database.transaction(() async {
          await database.customStatement(
            "INSERT INTO player_preferences VALUES ('drain', 'first')",
          );
          entered.complete();
          await release.future;
          await database.transaction(() async {
            await database.customStatement(
              "UPDATE player_preferences SET value='nested' WHERE key='drain'",
            );
          }, requireNew: true);
          if (rollback) throw StateError('test rollback');
        });
        final outcome = rollback ? expectLater(work, throwsStateError) : work;
        await entered.future.timeout(const Duration(seconds: 5));
        var closed = false;
        final closing = database.close();
        expect(identical(database.close(), closing), isTrue);
        final observedClose = closing.then((_) => closed = true);
        try {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(closed, isFalse);
          await expectLater(
            database.transaction(() async {}),
            throwsStateError,
          );
        } finally {
          release.complete();
          await outcome;
          await observedClose.timeout(const Duration(seconds: 5));
        }
        final reopened = LibraryDatabase(
          NativeDatabase.createInBackground(file),
        );
        try {
          final value = await reopened
              .customSelect(
                "SELECT value FROM player_preferences WHERE key='drain'",
              )
              .getSingleOrNull();
          expect(value?.read<String>('value'), rollback ? isNull : 'nested');
        } finally {
          await reopened.close();
        }
      },
    );
  }

  test(
    'closing inside a transaction fails promptly without deadlocking it',
    () async {
      final database = LibraryDatabase(NativeDatabase.createInBackground(file));
      try {
        await database
            .transaction(() async {
              await expectLater(database.close(), throwsStateError);
              await database.customStatement('SELECT 1');
            })
            .timeout(const Duration(seconds: 5));
      } finally {
        await database.close();
      }
    },
  );

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
