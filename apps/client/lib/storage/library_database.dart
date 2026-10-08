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
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement('''
        CREATE TABLE ignored_health_issues (
          category TEXT NOT NULL, source_id TEXT NOT NULL, local_id TEXT NOT NULL,
          PRIMARY KEY (category, source_id, local_id)
        )
      ''');
      await customStatement('''
        CREATE TABLE sources (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL,
          location TEXT NOT NULL, location_key TEXT NOT NULL UNIQUE,
          recursive INTEGER NOT NULL, ignore_hidden INTEGER NOT NULL,
          last_scan INTEGER,
          media_type TEXT NOT NULL DEFAULT 'auto',
          minimum_file_size INTEGER NOT NULL DEFAULT 52428800,
          options TEXT NOT NULL DEFAULT '{}',
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE media (
          source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          local_id TEXT NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL,
          bytes INTEGER NOT NULL, modified INTEGER NOT NULL,
          missing INTEGER NOT NULL DEFAULT 0,
          year INTEGER, season_number INTEGER, episode_number INTEGER,
          series_directory TEXT,
          is_series INTEGER NOT NULL DEFAULT 0,
          identity_kind TEXT NOT NULL,
          parent_id TEXT, original_title TEXT, overview TEXT,
          poster_path TEXT, backdrop_path TEXT,
          PRIMARY KEY (source_id, local_id),
          FOREIGN KEY (source_id, parent_id) REFERENCES media(source_id, local_id)
            DEFERRABLE INITIALLY DEFERRED
        )
      ''');
      await customStatement(
        'CREATE INDEX media_title ON media(source_id, title COLLATE NOCASE, local_id)',
      );
      await customStatement(
        'CREATE INDEX media_parent ON media(source_id, parent_id, season_number, episode_number)',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      // Track this run's imported identities for successful-scan pruning.
      // Imported media are committed per file, as in the original scanner.
      await customStatement('''
        CREATE TEMP TABLE scan_stage (
          run_id TEXT NOT NULL, local_id TEXT NOT NULL,
          PRIMARY KEY (run_id, local_id)
        )
      ''');
    },
  );
}
