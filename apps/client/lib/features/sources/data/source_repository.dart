import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
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
  final _pendingScans = <Future<void>>{};
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
      FROM sources s LEFT JOIN media m ON m.source_id = s.id
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
  }) async {
    final minimumBytes = minimumFileSize ?? mediaType.newSourceMinimumFileSize;
    if (minimumBytes < 0) {
      throw const SourceFailure('最小文件大小不能为负数。');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 120) {
      throw const SourceFailure('请输入 1–120 个字符的来源名称。');
    }
    final root = await _adapter(kind).validateLocation(location);
    final id = _newId();
    await database.transaction(() async {
      await _checkDuplicate(root);
      await database.customStatement(
        '''
        INSERT INTO sources(id, kind, name, location, location_key, recursive, ignore_hidden,
          media_type, minimum_file_size)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        'UPDATE sources SET location = ?, location_key = ?, last_scan = NULL WHERE id = ?',
        [root, _locationKey(root), id],
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
  }) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Invalid page');
    }
    return database.transaction(() async {
      final total = await database
          .customSelect(
            'SELECT COUNT(*) AS n FROM media WHERE source_id = ?',
            variables: [Variable(id)],
          )
          .getSingle();
      final rows = await database
          .customSelect(
            '''
        SELECT * FROM media WHERE source_id = ?
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
  );

  void cancel(String id) => _scans[id]?.cancel();

  Future<void> scan(String id, {void Function(int count)? onProgress}) {
    _requireIdle(id);
    if (_closed) throw const SourceFailure('媒体库已关闭。');
    final token = ScanCancellation();
    _scans[id] = token;
    final work = _scan(id, token, onProgress);
    _pendingScans.add(work);
    // Cleanup is inside the returned future so callers observe the idle state.
    return work.whenComplete(() {
      _pendingScans.remove(work);
      _scans.remove(id);
    });
  }

  Future<void> _scan(
    String id,
    ScanCancellation token,
    void Function(int)? progress,
  ) async {
    final runId = _newId();
    var count = 0;
    final batch = <IndexedMedia>[];
    try {
      final current = await source(id);
      await for (final item in _adapter(current.kind).scan(current, token)) {
        token.check();
        batch.add(item);
        count++;
        if (batch.length >= 100) {
          await _stage(runId, batch);
          batch.clear();
          progress?.call(count);
        }
      }
      await _stage(runId, batch);
      token.check();
      await database.transaction(() async {
        token.check();
        await database.customStatement(
          '''
          INSERT INTO media(source_id, local_id, title, type, bytes, modified, missing)
          SELECT source_id, local_id, title, type, bytes, modified, 0
          FROM scan_stage WHERE run_id = ?
          ON CONFLICT(source_id, local_id) DO UPDATE SET
            title = excluded.title, type = excluded.type, bytes = excluded.bytes,
            modified = excluded.modified, missing = 0
        ''',
          [runId],
        );
        // MediaScanner.scan prunes stale index rows only after a successful
        // full scan. An offline/failed/cancelled scan never reaches this point.
        // This SQL does not touch files in the source directory.
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
      progress?.call(count);
      _changed();
    } finally {
      await database.customStatement(
        'DELETE FROM scan_stage WHERE run_id = ?',
        [runId],
      );
    }
  }

  Future<void> _stage(String runId, List<IndexedMedia> items) =>
      database.transaction(() async {
        for (final item in items) {
          await database.customStatement(
            '''
        INSERT INTO scan_stage(run_id, source_id, local_id, title, type, bytes, modified)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
            [
              runId,
              item.identity.sourceId,
              item.identity.localId,
              item.title,
              item.type,
              item.bytes,
              item.modified.millisecondsSinceEpoch,
            ],
          );
        }
      });

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
