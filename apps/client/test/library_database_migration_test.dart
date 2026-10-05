import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  test(
    'v1 upgrade preserves source identity, settings, timestamps and index',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-migration-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final file = File(p.join(sandbox.path, 'library.sqlite'));
      final legacy = _VersionOneDatabase(NativeDatabase(file));
      try {
        await legacy.customStatement('''
        INSERT INTO sources VALUES ('old-id', 'mountedNas', 'My NAS',
          '/offline/library', '/offline/library', 0, 0, 12345)
      ''');
        await legacy.customStatement('''
        INSERT INTO media VALUES ('old-id', 'film.mp4', 'Film', 'homeVideo', 12, 111, 1)
      ''');
      } finally {
        await legacy.close();
      }

      final repository = SourceRepository(
        database: LibraryDatabase(NativeDatabase(file)),
        adapters: {},
      );
      try {
        final source = (await repository.sources()).single;
        expect(source.id, 'old-id');
        expect(source.kind, MediaSourceKind.mountedNas);
        expect(source.location, '/offline/library');
        expect(source.recursive, isFalse);
        expect(source.ignoreHidden, isFalse);
        expect(source.mediaType, SourceMediaType.auto);
        expect(source.minimumFileSize, 52428800);
        expect(source.lastScan!.millisecondsSinceEpoch, 12345);
        final item = (await repository.browse(source.id)).items.single;
        expect(item.identity, (sourceId: 'old-id', localId: 'film.mp4'));
        expect(item.bytes, 12);
        expect(item.missing, isTrue);
      } finally {
        await repository.close();
      }

      // A second open must not run ALTER TABLE again or discard migrated data.
      final reopened = LibraryDatabase(NativeDatabase(file));
      try {
        final version = await reopened
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.read<int>('user_version'), 2);
        expect(
          (await reopened.customSelect('SELECT * FROM media').get()).length,
          1,
        );
      } finally {
        await reopened.close();
      }
    },
  );
}

/// Frozen v1 schema. Do not derive it from the current migration under test.
class _VersionOneDatabase extends GeneratedDatabase {
  _VersionOneDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL,
        location TEXT NOT NULL, location_key TEXT NOT NULL UNIQUE,
        recursive INTEGER NOT NULL, ignore_hidden INTEGER NOT NULL, last_scan INTEGER)
    ''');
      await customStatement('''
      CREATE TABLE media (
        source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        local_id TEXT NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL,
        bytes INTEGER NOT NULL, modified INTEGER NOT NULL,
        missing INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (source_id, local_id))
    ''');
      await customStatement(
        'CREATE INDEX media_title ON media(source_id, title COLLATE NOCASE, local_id)',
      );
    },
  );
}
