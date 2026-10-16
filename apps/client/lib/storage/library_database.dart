import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
// Local background connections wrap initialization errors in this public type.
// Drift marks its wire protocol experimental; both peers use our locked version.
// ignore: experimental_member_use
import 'package:drift/remote.dart';

import 'runtime_storage_paths.dart';

class LibrarySchemaMismatch implements Exception {
  const LibrarySchemaMismatch();
  static const message = '本地开发数据库结构与当前版本不一致，请备份后重新初始化。媒体文件未受影响。';
  static bool isCause(Object error) =>
      error is LibrarySchemaMismatch ||
      (error is DriftRemoteException &&
          error.remoteCause.toString() == message);
  @override
  String toString() => message;
}

class _TransactionLifetime {
  bool active = true;
}

/// Explicit SQL schema, owned solely by ReelNest. No old MediaLib DB is opened.
class LibraryDatabase extends GeneratedDatabase {
  LibraryDatabase(super.executor);

  final _transactionZone = Object();
  final _transactions = <Future<void>>{};
  Future<void>? _closing;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) {
    if ((Zone.current[_transactionZone] as _TransactionLifetime?)?.active ==
        true) {
      return super.transaction(action, requireNew: requireNew);
    }
    if (_closing != null) {
      return Future.error(StateError('Database is closing'));
    }
    final lifetime = _TransactionLifetime();
    final work = runZoned(
      () => super.transaction(action, requireNew: requireNew),
      zoneValues: {_transactionZone: lifetime},
    );
    // Keep the caller's result/error intact, while shutdown only waits for the
    // transaction's commit or rollback to finish, including nested savepoints.
    final settled = work.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _transactions.add(settled);
    unawaited(
      settled.then((_) {
        lifetime.active = false;
        _transactions.remove(settled);
      }),
    );
    return work;
  }

  @override
  Future<void> close() {
    if ((Zone.current[_transactionZone] as _TransactionLifetime?)?.active ==
        true) {
      return Future.error(StateError('Cannot close inside a transaction'));
    }
    return _closing ??= _closeAfterTransactions();
  }

  Future<void> _closeAfterTransactions() async {
    await Future.wait(_transactions.toList());
    await super.close();
  }

  factory LibraryDatabase.open() {
    final paths = RuntimeStoragePaths.current;
    return LibraryDatabase(
      LazyDatabase(() async {
        final file = await paths.databaseFile();
        return NativeDatabase.createInBackground(file);
      }),
    );
  }

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (_, _, _) async => throw const LibrarySchemaMismatch(),
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
          access_identity TEXT,
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
      final columns = await customSelect('PRAGMA table_info(sources)').get();
      final names = columns.map((row) => row.read<String>('name')).toSet();
      if (!names.containsAll({
        'access_identity',
        'options',
        'updated_at',
        'created_at',
      })) {
        throw const LibrarySchemaMismatch();
      }
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS media_activity (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(source_id, local_id),
          FOREIGN KEY(source_id, local_id) REFERENCES media(source_id, local_id)
            ON DELETE CASCADE
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS player_preferences (
          key TEXT PRIMARY KEY, value TEXT NOT NULL
        )
      ''');
      // This module owns one current table. Idempotent provisioning does not
      // modify existing media/source columns or add a historical upgrade chain.
      await customStatement('''
        CREATE TABLE IF NOT EXISTS playback_states (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL,
          position_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
          watched INTEGER NOT NULL DEFAULT 0, last_played_at INTEGER NOT NULL,
          PRIMARY KEY(source_id, local_id),
          FOREIGN KEY(source_id, local_id) REFERENCES media(source_id, local_id)
            ON DELETE CASCADE
        )
      ''');
      // Current module-owned marker table; no historical schema branches.
      await customStatement('''
        CREATE TABLE IF NOT EXISTS playback_markers (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL, id TEXT NOT NULL,
          kind TEXT NOT NULL, title TEXT NOT NULL, start_us INTEGER NOT NULL,
          end_us INTEGER, origin TEXT NOT NULL, review_status TEXT NOT NULL,
          detector_identifier TEXT, confidence REAL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          PRIMARY KEY(source_id,local_id,id),
          FOREIGN KEY(source_id,local_id) REFERENCES media(source_id,local_id)
            ON DELETE CASCADE
        )
      ''');
      // Current connector-owned metadata table; no historical schema branches.
      await customStatement('''
        CREATE TABLE IF NOT EXISTS remote_media_metadata (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL, value TEXT NOT NULL,
          PRIMARY KEY(source_id, local_id),
          FOREIGN KEY(source_id, local_id) REFERENCES media(source_id, local_id)
            ON DELETE CASCADE
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS remote_media_details (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL,
          value TEXT NOT NULL, fetched_at INTEGER NOT NULL,
          PRIMARY KEY(source_id, local_id),
          FOREIGN KEY(source_id, local_id) REFERENCES media(source_id, local_id)
            ON DELETE CASCADE
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS remote_library_views (
          source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          library_id TEXT NOT NULL, name TEXT NOT NULL, collection_type TEXT,
          PRIMARY KEY(source_id, library_id)
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS media_library_preferences (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL,
          watchlist INTEGER NOT NULL DEFAULT 0, user_rating REAL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY(source_id, local_id),
          FOREIGN KEY(source_id, local_id) REFERENCES media(source_id, local_id)
            ON DELETE CASCADE
        )
      ''');

      // Track this run's imported identities for successful-scan pruning.
      await customStatement('''
        CREATE TABLE IF NOT EXISTS artwork_disk_cache (
          cache_key TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          filename TEXT NOT NULL, bytes INTEGER NOT NULL, accessed_at INTEGER NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS video_disk_cache (
          source_id TEXT NOT NULL, local_id TEXT NOT NULL, bundle TEXT NOT NULL, root TEXT NOT NULL,
          filename TEXT NOT NULL, bytes INTEGER NOT NULL, quality_id TEXT NOT NULL,
          quality_label TEXT NOT NULL, created_at INTEGER NOT NULL, accessed_at INTEGER NOT NULL,
          PRIMARY KEY(source_id, local_id),
          FOREIGN KEY(source_id, local_id) REFERENCES media(source_id, local_id) ON DELETE CASCADE
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS video_cache_leases (
          owner TEXT PRIMARY KEY, bundle TEXT NOT NULL, expires_at INTEGER NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS video_cache_staging (
          token TEXT PRIMARY KEY, root TEXT NOT NULL, touched_at INTEGER NOT NULL
        )
      ''');
      await customStatement('''
        CREATE TABLE IF NOT EXISTS video_offline_subscriptions (
          id TEXT NOT NULL UNIQUE, source_id TEXT NOT NULL, series_id TEXT NOT NULL,
          title TEXT NOT NULL, mode TEXT NOT NULL, episode_limit INTEGER NOT NULL,
          season INTEGER, quality_id TEXT, enabled INTEGER NOT NULL,
          paused_until INTEGER, expires_at INTEGER, network TEXT NOT NULL,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          PRIMARY KEY(source_id,series_id),
          FOREIGN KEY(source_id,series_id) REFERENCES media(source_id,local_id) ON DELETE CASCADE
        )
      ''');
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
