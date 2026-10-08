import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../domain/library_health.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/source_options.dart';
import '../../../domain/source_scan.dart';
import '../../../sources/source_adapter.dart';
import '../../../storage/library_database.dart';

String _newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class SourceRepository {
  SourceRepository({required this.database, required this.adapters});

  final LibraryDatabase database;
  final Map<MediaSourceKind, SourceAdapter> adapters;
  final _changes = StreamController<void>.broadcast();
  final _scans = <String, ScanCancellation>{};
  final _pendingScans = <Future<SourceScanSummary>>{};
  bool _closed = false;
  Stream<void> get changes => _changes.stream;

  SourceAdapter _adapter(MediaSourceKind kind) =>
      adapters[kind] ?? (throw SourceFailure('${kind.label} 尚未接入。'));

  String _locationKey(String location) =>
      Platform.isWindows ? location.toLowerCase() : location;

  void _changed() {
    if (!_closed) _changes.add(null);
  }

  Future<List<MediaSource>> sources() async {
    final rows = await database.customSelect('''
      SELECT s.*, COUNT(m.local_id) AS item_count,
        COALESCE(SUM(m.missing), 0) AS missing_count
      FROM sources s LEFT JOIN media m ON m.source_id = s.id AND m.is_series = 0
      GROUP BY s.id ORDER BY s.name COLLATE NOCASE, s.id
    ''').get();
    return rows
        .map(
          (r) => MediaSource(
            id: r.read<String>('id'),
            kind: MediaSourceKind.values.byName(r.read<String>('kind')),
            name: r.read<String>('name'),
            location: r.read<String>('location'),
            recursive: r.read<int>('recursive') != 0,
            ignoreHidden: r.read<int>('ignore_hidden') != 0,
            mediaType: SourceMediaType.fromStorage(
              r.read<String>('media_type'),
            ),
            minimumFileSize: r.read<int>('minimum_file_size'),
            options: SourceOptions.fromJson(
              jsonDecode(r.read<String>('options')) as Map<String, dynamic>,
            ),
            createdAt: _date(r.read<int>('created_at')),
            updatedAt: _date(r.read<int>('updated_at')),
            lastScan: r.readNullable<int>('last_scan') == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    r.read<int>('last_scan'),
                    isUtc: true,
                  ),
            itemCount: r.read<int>('item_count'),
            missingCount: r.read<int>('missing_count'),
          ),
        )
        .toList();
  }

  Future<MediaSource> source(String id) async {
    final matches = (await sources()).where((s) => s.id == id);
    if (matches.isEmpty) throw const SourceFailure('该媒体源已移除。');
    return matches.first;
  }

  /// Consistent database snapshot. Filesystem probing happens after this read
  /// transaction, so slow NAS I/O never holds the database transaction open.
  Future<LibraryInventory> inventory() => database.transaction(() async {
    final sourceList = await sources();
    final rows = await database
        .customSelect(
          'SELECT * FROM media ORDER BY title COLLATE NOCASE, source_id, local_id',
        )
        .get();
    return (
      sources: List<MediaSource>.unmodifiable(sourceList),
      items: List<IndexedMedia>.unmodifiable(rows.map(_media)),
    );
  });

  DateTime _date(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

  Future<bool> isReachable(MediaSource source) =>
      _adapter(source.kind).isReachable(source.location);

  Future<MediaSource> add({
    required MediaSourceKind kind,
    required String name,
    required String location,
    bool recursive = true,
    bool ignoreHidden = true,
    SourceMediaType mediaType = SourceMediaType.auto,
    int? minimumFileSize,
    SourceOptions options = const SourceOptions.defaults(),
  }) async {
    final minimumBytes = minimumFileSize ?? mediaType.newSourceMinimumFileSize;
    if (minimumBytes < 0) {
      throw const SourceFailure('最小文件大小不能为负数。');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const SourceFailure('请输入来源名称。');
    }
    final root = await _adapter(kind).validateLocation(location);
    final id = _newId();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.transaction(() async {
      await _checkDuplicate(root);
      await database.customStatement(
        '''
        INSERT INTO sources(id, kind, name, location, location_key, recursive, ignore_hidden,
          media_type, minimum_file_size, options, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          id,
          kind.name,
          normalizedName,
          root,
          _locationKey(root),
          recursive ? 1 : 0,
          ignoreHidden ? 1 : 0,
          mediaType.storageValue,
          minimumBytes,
          jsonEncode(options.toJson()),
          now,
          now,
        ],
      );
    });
    _changed();
    return source(id);
  }

  /// AppState.addSources: skip existing directories, name from the directory,
  /// save in selection order, then let the controller enqueue only new sources.
  Future<List<MediaSource>> addFolders({
    required List<String> locations,
    SourceMediaType mediaType = SourceMediaType.auto,
  }) async {
    if (locations.isEmpty) return [];
    final existing = (await sources())
        .map((s) => _locationKey(s.location))
        .toSet();
    final saved = <MediaSource>[];
    for (final location in locations) {
      // A disconnected directory that is already in the library is still a
      // duplicate; don't require a new access grant just to skip it.
      if (existing.contains(_locationKey(p.normalize(location)))) continue;
      final root = await _adapter(MediaSourceKind.localFolder)
          .validateLocation(location);
      if (!existing.add(_locationKey(root))) continue;
      saved.add(
        await add(
          kind: MediaSourceKind.localFolder,
          name: p.basename(location).isEmpty ? location : p.basename(location),
          location: root,
          mediaType: mediaType,
          options: SourceOptions(
            includeInMetadataFetch:
                mediaType != SourceMediaType.photo &&
                mediaType != SourceMediaType.homeVideo,
          ),
        ),
      );
    }
    if (saved.isEmpty) {
      final private = mediaType == SourceMediaType.privateCollection;
      throw SourceFailure(
        private
            ? (locations.length == 1 ? '该保险库媒体源已添加。' : '所选保险库媒体源均已添加。')
            : (locations.length == 1
                  ? '目录「${p.basename(locations.single).isEmpty ? locations.single : p.basename(locations.single)}」已添加为媒体源。'
                  : '所选目录均已添加为媒体源。'),
      );
    }
    return saved;
  }

  /// Storage operation. SourceScans coordinates AppState's save/restart sequence.
  /// Configuration can be saved during a scan: that scan keeps its immutable
  /// source snapshot until the controller cancels it after a successful save.
  Future<MediaSource> updateSettings(
    String id, {
    String? name,
    bool? recursive,
    bool? ignoreHidden,
    SourceMediaType? mediaType,
    int? minimumFileSize,
    SourceOptions? options,
    bool allowDuringScan = false,
  }) async {
    if (!allowDuringScan) _requireIdle(id);
    await database.transaction(() async {
      if (!allowDuringScan) _requireIdle(id);
      final current = await source(id);
      final title = (name ?? current.name).trim();
      if (title.isEmpty) {
        throw const SourceFailure('请输入来源名称。');
      }
      final type = mediaType ?? current.mediaType;
      var minimum = minimumFileSize ?? current.minimumFileSize;
      if (minimum < 0) throw const SourceFailure('最小文件大小不能为负数。');
      // AppState.updateSource uses a strict > 5 MiB adjustment for music.
      if (type == SourceMediaType.music && minimum > 5 * 1024 * 1024) {
        minimum = 512 * 1024;
      }
      await database.customStatement(
        '''
        UPDATE sources SET name = ?, recursive = ?, ignore_hidden = ?,
          media_type = ?, minimum_file_size = ?, options = ?, updated_at = ? WHERE id = ?
      ''',
        [
          title,
          (recursive ?? current.recursive) ? 1 : 0,
          (ignoreHidden ?? current.ignoreHidden) ? 1 : 0,
          type.storageValue,
          minimum,
          jsonEncode((options ?? current.options).toJson()),
          DateTime.now().toUtc().millisecondsSinceEpoch,
          id,
        ],
      );
    });
    _changed();
    return source(id);
  }

  Future<void> _checkDuplicate(String root, {String? except}) async {
    final rows = await database
        .customSelect(
          'SELECT id FROM sources WHERE location_key = ?',
          variables: [Variable(_locationKey(root))],
        )
        .get();
    if (rows.any((r) => r.read<String>('id') != except)) {
      throw const SourceFailure('此目录已经添加为媒体源。');
    }
  }

  void _requireIdle(String id) {
    if (_scans.containsKey(id)) {
      throw const SourceFailure('请先取消扫描并等待结束。');
    }
  }

  Future<void> relocate(String id, String location) async {
    _requireIdle(id);
    final existing = await source(id);
    final root = await _adapter(existing.kind).validateLocation(location);
    await database.transaction(() async {
      _requireIdle(id);
      await _checkDuplicate(root, except: id);
      await database.customStatement(
        'UPDATE sources SET location = ?, location_key = ?, last_scan = NULL, updated_at = ? WHERE id = ?',
        [
          root,
          _locationKey(root),
          DateTime.now().toUtc().millisecondsSinceEpoch,
          id,
        ],
      );
    });
    _changed();
  }

  /// Removes this application's index only, never files in the selected folder.
  Future<void> remove(String id) async {
    _requireIdle(id);
    await database.transaction(() async {
      _requireIdle(id);
      await database.customStatement('DELETE FROM sources WHERE id = ?', [id]);
    });
    _changed();
  }

  Future<IndexedMediaPage> browse(
    String id, {
    int offset = 0,
    int limit = 60,
    bool topLevelOnly = false,
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Invalid page');
    }
    return database.transaction(() async {
      final total = await database
          .customSelect(
            'SELECT COUNT(*) AS n FROM media WHERE source_id = ? AND ${topLevelOnly ? 'parent_id IS NULL' : 'is_series = 0'}',
            variables: [Variable(id)],
          )
          .getSingle();
      final rows = await database
          .customSelect(
            '''
        SELECT * FROM media WHERE source_id = ? AND ${topLevelOnly ? 'parent_id IS NULL' : 'is_series = 0'}
        ORDER BY title COLLATE NOCASE, local_id LIMIT ? OFFSET ?
      ''',
            variables: [Variable(id), Variable(limit), Variable(offset)],
          )
          .get();
      return IndexedMediaPage(
        items: rows.map(_media).toList(),
        total: total.read<int>('n'),
      );
    });
  }

  IndexedMedia _media(QueryRow r) => IndexedMedia(
    identity: (
      sourceId: r.read<String>('source_id'),
      localId: r.read<String>('local_id'),
    ),
    title: r.read<String>('title'),
    type: r.read<String>('type'),
    bytes: r.read<int>('bytes'),
    modified: DateTime.fromMillisecondsSinceEpoch(
      r.read<int>('modified'),
      isUtc: true,
    ),
    missing: r.read<int>('missing') != 0,
    year: r.readNullable<int>('year'),
    seasonNumber: r.readNullable<int>('season_number'),
    episodeNumber: r.readNullable<int>('episode_number'),
    seriesDirectory: r.readNullable<String>('series_directory'),
    isSeries: r.read<int>('is_series') != 0,
    parentId: r.readNullable<String>('parent_id'),
    originalTitle: r.readNullable<String>('original_title'),
    overview: r.readNullable<String>('overview'),
    posterPath: r.readNullable<String>('poster_path'),
    backdropPath: r.readNullable<String>('backdrop_path'),
  );

  Future<IndexedMedia> media(MediaIdentity identity) async {
    final row = await database
        .customSelect(
          'SELECT * FROM media WHERE source_id = ? AND local_id = ?',
          variables: [Variable(identity.sourceId), Variable(identity.localId)],
        )
        .getSingleOrNull();
    if (row == null) throw const SourceFailure('该媒体已移除或尚未入库。');
    return _media(row);
  }

  Future<List<IndexedSeason>> seasons(MediaIdentity series) async {
    final parent = await media(series);
    if (!parent.isSeries) return [];
    final rows = await database
        .customSelect(
          '''
      SELECT season_number, COUNT(*) AS count FROM media
      WHERE source_id = ? AND parent_id = ?
      GROUP BY season_number ORDER BY season_number IS NULL, season_number
    ''',
          variables: [Variable(series.sourceId), Variable(series.localId)],
        )
        .get();
    return rows
        .map(
          (row) => IndexedSeason(
            number: row.readNullable<int>('season_number'),
            episodeCount: row.read<int>('count'),
          ),
        )
        .toList();
  }

  Future<IndexedMediaPage> episodes(
    MediaIdentity series, {
    required int? seasonNumber,
    int offset = 0,
    int limit = 60,
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Invalid page');
    }
    await media(series);
    return database.transaction(() async {
      final where = 'source_id = ? AND parent_id = ? AND season_number IS ?';
      final bindings = <Variable>[
        Variable(series.sourceId),
        Variable(series.localId),
        Variable<int>(seasonNumber),
      ];
      final total = await database
          .customSelect(
            'SELECT COUNT(*) AS n FROM media WHERE $where',
            variables: bindings,
          )
          .getSingle();
      final rows = await database
          .customSelect(
            '''
        SELECT * FROM media WHERE $where
        ORDER BY episode_number ASC, title COLLATE NOCASE ASC, local_id ASC LIMIT ? OFFSET ?
      ''',
            variables: [...bindings, Variable(limit), Variable(offset)],
          )
          .get();
      return IndexedMediaPage(
        items: rows.map(_media).toList(),
        total: total.read<int>('n'),
      );
    });
  }

  void cancel(String id) => _scans[id]?.cancel();

  Future<SourceScanSummary> scan(
    String id, {
    void Function(SourceScanProgress progress)? onProgress,
  }) {
    _requireIdle(id);
    if (_closed) throw const SourceFailure('媒体库已关闭。');
    final token = ScanCancellation();
    _scans[id] = token;
    final work = _scan(id, token, onProgress);
    _pendingScans.add(work);
    return work.whenComplete(() {
      _pendingScans.remove(work);
      _scans.remove(id);
    });
  }

  Future<SourceScanSummary> _scan(
    String id,
    ScanCancellation token,
    void Function(SourceScanProgress)? progress,
  ) async {
    final runId = _newId();
    var total = 0;
    var processed = 0;
    var imported = 0;
    var skipped = 0;
    final errors = <String>[];
    try {
      final current = await source(id);
      void publish(String? path) => progress?.call(
        SourceScanProgress(
          totalFiles: total,
          processedFiles: processed,
          importedItems: imported,
          skippedFiles: skipped,
          errors: List.unmodifiable(errors),
          currentPath: current.mediaType == SourceMediaType.privateCollection
              ? null
              : path,
        ),
      );
      await for (final event in _adapter(current.kind).scan(current, token)) {
        token.check();
        switch (event) {
          case ScanCatalogued():
            total = event.totalFiles;
            publish(null);
          case ScanFileProcessed():
            var error = event.error;
            if (error == null && event.item != null) {
              try {
                await _import(
                  runId,
                  event.item!,
                  parent: event.parent,
                  sourceType: current.mediaType,
                );
                imported++;
              } catch (_) {
                error = '文件索引写入失败，请检查磁盘空间和数据库。';
              }
            } else if (error == null) {
              skipped++;
            }
            if (error != null) {
              errors.add(
                current.mediaType == SourceMediaType.privateCollection
                    ? '隐私媒体源中有文件扫描失败。'
                    : error,
              );
            }
            processed++;
            publish(event.path);
        }
      }
      token.check();
      // Original MediaScanner commits each import immediately, and prunes
      // missing items only after an uninterrupted run with no file errors.
      if (errors.isEmpty) {
        await database.transaction(() async {
          token.check();
          await database.customStatement(
            '''
            DELETE FROM media WHERE source_id = ? AND local_id NOT IN
              (SELECT local_id FROM scan_stage WHERE run_id = ?)
          ''',
            [id, runId],
          );
          await database.customStatement(
            'UPDATE sources SET last_scan = ? WHERE id = ?',
            [DateTime.now().toUtc().millisecondsSinceEpoch, id],
          );
          token.check();
        });
      }
      return SourceScanSummary(
        scannedFiles: total,
        importedItems: imported,
        skippedFiles: skipped,
        errors: errors,
      );
    } finally {
      try {
        await database.customStatement(
          'DELETE FROM scan_stage WHERE run_id = ?',
          [runId],
        );
      } finally {
        // Failed and cancelled runs can contain successfully committed files.
        _changed();
      }
    }
  }

  Future<void> _import(
    String runId,
    IndexedMedia item, {
    IndexedMedia? parent,
    required SourceMediaType sourceType,
  }) => database.transaction(() async {
    if (parent != null) {
      if (!parent.isSeries ||
          parent.identity.sourceId != item.identity.sourceId ||
          item.parentId != parent.identity.localId) {
        throw StateError('Invalid series/episode association');
      }
      await _upsert(runId, parent, identityKind: 'show');
    }
    final identityKind = sourceType == SourceMediaType.photo
        ? (item.type == 'photo' ? 'photo' : 'albumvideo')
        : item.type == 'episode'
        ? 'episode'
        : item.type == 'music'
        ? 'music'
        : 'movie';
    await _upsert(runId, item, identityKind: identityKind);
  });

  Future<void> _upsert(
    String runId,
    IndexedMedia item, {
    required String identityKind,
  }) async {
    // MediaRepository.upsert retains missing descriptive fields. The original
    // scanner uses different ID prefixes for movie/episode/albumvideo/etc.; our
    // relative file key stays stable, so a kind change explicitly resets them.
    String metadataValue(String column) =>
        'CASE WHEN media.identity_kind = excluded.identity_kind '
        'THEN COALESCE(excluded.$column, media.$column) ELSE excluded.$column END';
    await database.customStatement(
      '''
      INSERT INTO media(source_id, local_id, title, type, bytes, modified, missing,
        year, season_number, episode_number, series_directory, is_series, parent_id,
        original_title, overview, poster_path, backdrop_path, identity_kind)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_id, local_id) DO UPDATE SET
        title = excluded.title, type = excluded.type, bytes = excluded.bytes,
        modified = excluded.modified, missing = 0, year = ${metadataValue('year')},
        season_number = excluded.season_number, episode_number = excluded.episode_number,
        series_directory = excluded.series_directory, is_series = excluded.is_series,
        parent_id = excluded.parent_id, original_title = ${metadataValue('original_title')},
        overview = ${metadataValue('overview')}, poster_path = ${metadataValue('poster_path')},
        backdrop_path = ${metadataValue('backdrop_path')}, identity_kind = excluded.identity_kind
    ''',
      [
        item.identity.sourceId,
        item.identity.localId,
        item.title,
        item.type,
        item.bytes,
        item.modified.millisecondsSinceEpoch,
        item.year,
        item.seasonNumber,
        item.episodeNumber,
        item.seriesDirectory,
        item.isSeries ? 1 : 0,
        item.parentId,
        item.originalTitle,
        item.overview,
        item.posterPath,
        item.backdropPath,
        identityKind,
      ],
    );
    await database.customStatement(
      'INSERT OR IGNORE INTO scan_stage(run_id, local_id) VALUES (?, ?)',
      [runId, item.identity.localId],
    );
  }

  Future<void> close() async {
    _closed = true;
    for (final token in _scans.values) {
      token.cancel();
    }
    await Future.wait(
      _pendingScans.toList().map((f) async {
        try {
          await f;
        } catch (_) {
          /* Caller handles scan failure. */
        }
      }),
    );
    await _changes.close();
    await database.close();
  }
}
