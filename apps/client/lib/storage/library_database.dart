import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Explicit SQL schema, owned solely by ReelNest. No old MediaLib DB is opened.
class LibraryDatabase extends GeneratedDatabase {
  LibraryDatabase(super.executor);

  factory LibraryDatabase.open() => LibraryDatabase(
    LazyDatabase(() async {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(p.join(support.path, 'library'));
      await directory.create(recursive: true);
      return NativeDatabase.createInBackground(
        File(p.join(directory.path, 'reelnest.sqlite')),
      );
    }),
  );

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement('''
        CREATE TABLE sources (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL,
          location TEXT NOT NULL, location_key TEXT NOT NULL UNIQUE,
          recursive INTEGER NOT NULL, ignore_hidden INTEGER NOT NULL,
          last_scan INTEGER,
          media_type TEXT NOT NULL DEFAULT 'auto',
          minimum_file_size INTEGER NOT NULL DEFAULT 52428800
        )
      ''');
      await customStatement('''
        CREATE TABLE media (
          source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          local_id TEXT NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL,
          bytes INTEGER NOT NULL, modified INTEGER NOT NULL,
          missing INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (source_id, local_id)
        )
      ''');
      await customStatement(
        'CREATE INDEX media_title ON media(source_id, title COLLATE NOCASE, local_id)',
      );
    },
    onUpgrade: (m, from, to) => transaction(() async {
      if (from < 2) {
        // Version 1 had no classification/size setting. Adopt the original
        // defaults without touching existing media or triggering a rescan.
        await customStatement(
          "ALTER TABLE sources ADD COLUMN media_type TEXT NOT NULL DEFAULT 'auto'",
        );
        await customStatement(
          'ALTER TABLE sources ADD COLUMN minimum_file_size INTEGER NOT NULL DEFAULT 52428800',
        );
      }
      // Commit schema and version together so an interrupted upgrade cannot
      // leave v1 with an already-added column on the next launch.
      await customStatement('PRAGMA user_version = $to');
    }),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      // Connection-local staging disappears even after a crash and cannot
      // overwrite another process's unfinished scan.
      await customStatement('''
        CREATE TEMP TABLE scan_stage (
          run_id TEXT NOT NULL, source_id TEXT NOT NULL,
          local_id TEXT NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL,
          bytes INTEGER NOT NULL, modified INTEGER NOT NULL,
          PRIMARY KEY (run_id, local_id)
        )
      ''');
    },
  );
}
