import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../domain/remote_media_metadata.dart';
import '../../../domain/library_health.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/source_options.dart';
import '../../../domain/source_scan.dart';
import '../../../domain/source_add_result.dart';
import '../../../sources/source_adapter.dart';
import '../../../sources/filesystem/file_source_adapter.dart';
import '../../../platform/directory_safety.dart';
import '../../../storage/library_database.dart';

String _newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _embyLocation(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'emby' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.pathSegments.length != 1) {
    throw const SourceFailure('Emby 来源标识无效。');
  }
  return uri.toString();
}

class SourceRepository {
  SourceRepository({
    required this.database,
    required this.adapters,
    DirectoryIdentityLookup? identityLookup,
  }) : identityLookup = identityLookup ?? directoryIdentity,
       _explicitIdentityLookup = identityLookup != null;

  final LibraryDatabase database;
  final Map<MediaSourceKind, SourceAdapter> adapters;
  final DirectoryIdentityLookup identityLookup;
  final bool _explicitIdentityLookup;
  bool _indexMaintenance = false;
  Completer<void>? _maintenanceDone;
  final _changes = StreamController<void>.broadcast();
  final _scans = <String, ScanCancellation>{};
  final _pendingScans = <Future<SourceScanSummary>>{};
  bool _closed = false;
  Stream<void> get changes => _changes.stream;
  bool isScanning(String id) => _scans.containsKey(id);

  SourceAdapter _adapter(MediaSourceKind kind) =>
      adapters[kind] ?? (throw SourceFailure('${kind.label} 尚未接入。'));

  String _locationKey(String location) =>
      Platform.isWindows ? location.toLowerCase() : location;

  void _changed() {
    if (!_closed) _changes.add(null);
  }

  /// Publish connector-owned trace mutations through the same browse refresh.
  void traceChanged() => _changed();

  Future<void> setRemoteFavorite(MediaIdentity identity, bool favorite) async {
    final item = await media(identity);
    if (item.remote == null) throw const SourceFailure('此媒体没有远程状态。');
    await database.customStatement(
      'UPDATE remote_media_metadata SET value = ? WHERE source_id = ? AND local_id = ?',
      [
        jsonEncode({...item.remote!.toJson(), 'favorite': favorite}),
        identity.sourceId,
        identity.localId,
      ],
    );
    _changed();
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
            accessIdentity: r.readNullable<String>('access_identity'),
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
    final rows = await database.customSelect('''SELECT media.*, (SELECT value FROM remote_media_metadata r WHERE r.source_id = media.source_id AND r.local_id = media.local_id) AS remote_metadata, media_activity.updated_at AS activity_updated_at
             FROM media LEFT JOIN media_activity USING(source_id, local_id)
             ORDER BY title COLLATE NOCASE, source_id, local_id''').get();
    return (
      sources: List<MediaSource>.unmodifiable(sourceList),
      items: List<IndexedMedia>.unmodifiable(rows.map(_media)),
    );
  });

  DateTime _date(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

  Future<bool> isReachable(MediaSource source) async {
    if (!source.kind.isFileSource) {
      return false; // Remote reachability is owned by its connection service.
    }
    if (!await _adapter(source.kind).isReachable(source.location)) return false;
    return !_tracksIdentity(source.kind) || await isSafeDirectory(source);
  }

  Future<bool> isSafeDirectory(MediaSource source) async =>
      source.accessIdentity != null &&
      await identityLookup(source.location) == source.accessIdentity;

  bool _tracksIdentity(MediaSourceKind kind) =>
      kind.isFileSource &&
      (_explicitIdentityLookup || _adapter(kind) is FileSourceAdapter);

  void _requireNoMaintenance() {
    if (_indexMaintenance) throw const SourceFailure('正在清理索引，请稍后再试。');
  }

  Future<MediaSource> add({
    String? sourceId,
    required MediaSourceKind kind,
    required String name,
    required String location,
    bool recursive = true,
    bool ignoreHidden = true,
    SourceMediaType mediaType = SourceMediaType.auto,
    int? minimumFileSize,
    SourceOptions options = const SourceOptions.defaults(),
  }) async {
    _requireNoMaintenance();
    final minimumBytes = minimumFileSize ?? mediaType.newSourceMinimumFileSize;
    if (minimumBytes < 0) {
      throw const SourceFailure('最小文件大小不能为负数。');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const SourceFailure('请输入来源名称。');
    }
    final root = kind == MediaSourceKind.emby
        ? _embyLocation(location)
        : await _adapter(kind).validateLocation(location);
    final identity = _tracksIdentity(kind) ? await identityLookup(root) : null;
    final id = sourceId ?? _newId();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await database.transaction(() async {
      _requireNoMaintenance();
      await _checkDuplicate(root);
      await database.customStatement(
        '''
        INSERT INTO sources(id, kind, name, location, location_key, recursive, ignore_hidden,
          media_type, minimum_file_size, options, created_at, updated_at, access_identity)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          identity,
        ],
      );
    });
    _changed();
    return source(id);
  }

  /// AppState.addSources: skip existing directories, name from the directory,
  /// save in selection order, then let the controller enqueue only new sources.
  Future<FolderAddResult> addFolders({
    required List<String> locations,
    SourceMediaType mediaType = SourceMediaType.auto,
  }) async {
    final existing = (await sources())
        .map((s) => _locationKey(s.location))
        .toSet();
    final saved = <MediaSource>[];
    final skipped = <String>[];
    final failures = <FolderAddFailure>[];
    for (final location in locations) {
      // A disconnected directory that is already in the library is still a
      // duplicate; don't require a new access grant just to skip it.
      if (existing.contains(_locationKey(p.normalize(location)))) {
        skipped.add(location);
        continue;
      }
      try {
        final root = await _adapter(MediaSourceKind.localFolder)
            .validateLocation(location);
        if (existing.contains(_locationKey(root))) {
          skipped.add(location);
          continue;
        }
        final created = await add(
          kind: MediaSourceKind.localFolder,
          name: p.basename(location).isEmpty ? location : p.basename(location),
          location: root,
          mediaType: mediaType,
          options: SourceOptions(
            includeInMetadataFetch:
                mediaType != SourceMediaType.photo &&
                mediaType != SourceMediaType.homeVideo,
          ),
        );
        saved.add(created);
        // Failed saves must remain retryable within this batch and later ones.
        existing.add(_locationKey(root));
      } on Exception catch (error) {
        failures.add((location: location, error: error));
      }
    }
    if (saved.isEmpty && failures.isEmpty && locations.isNotEmpty) {
      final private = mediaType == SourceMediaType.privateCollection;
      throw SourceFailure(
        private
            ? (locations.length == 1 ? '该保险库媒体源已添加。' : '所选保险库媒体源均已添加。')
            : (locations.length == 1
                  ? '目录「${p.basename(locations.single).isEmpty ? locations.single : p.basename(locations.single)}」已添加为媒体源。'
                  : '所选目录均已添加为媒体源。'),
      );
    }
    return FolderAddResult(
      added: saved,
      skippedLocations: skipped,
      failures: failures,
    );
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
    _requireNoMaintenance();
    if (!allowDuringScan) _requireIdle(id);
    await database.transaction(() async {
      _requireNoMaintenance();
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
    _requireNoMaintenance();
    if (_scans.containsKey(id)) {
      throw const SourceFailure('请先取消扫描并等待结束。');
    }
  }

  Future<void> relocate(String id, String location) async {
    _requireIdle(id);
    final existing = await source(id);
    final root = await _adapter(existing.kind).validateLocation(location);
    final identity = _tracksIdentity(existing.kind)
        ? await identityLookup(root)
        : null;
    await database.transaction(() async {
      _requireIdle(id);
      await _checkDuplicate(root, except: id);
      await database.customStatement(
        'UPDATE sources SET location = ?, location_key = ?, access_identity = ?, last_scan = NULL, updated_at = ? WHERE id = ?',
        [
          root,
          _locationKey(root),
          identity,
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

  /// Validation runs outside SQL transactions. Gate mutations/scans until the
  /// fresh filesystem checks and atomic index commit finish.
  Future<({int removed, int retained})> removeRevalidatedMissing(
    Set<MediaIdentity> requested,
    Future<Set<MediaIdentity>> Function(LibraryInventory) revalidate,
  ) async {
    if (_closed) throw const SourceFailure('媒体库已关闭。');
    _requireNoMaintenance();
    if (_scans.isNotEmpty) throw const SourceFailure('请先取消扫描并等待结束。');
    if (requested.isEmpty) return (removed: 0, retained: 0);
    _indexMaintenance = true;
    final done = _maintenanceDone = Completer<void>();
    try {
      final before = await database.transaction(
        () async => (
          inventory: await inventory(),
          fingerprint: await _cleanupFingerprint(requested),
        ),
      );
      final safe = (await revalidate(before.inventory)).intersection(requested);
      if (safe.isEmpty) return (removed: 0, retained: requested.length);
      var removed = 0;
      await database.transaction(() async {
        if (_closed ||
            await _cleanupFingerprint(requested) != before.fingerprint) {
          throw const SourceFailure('媒体库状态已变化，请重新检测后再清理。');
        }
        final parents = <MediaIdentity>{};
        for (final item in before.inventory.items) {
          if (!safe.contains(item.identity) || item.isSeries) continue;
          removed += await database.customUpdate(
            'DELETE FROM media WHERE source_id = ? AND local_id = ? AND is_series = 0',
            variables: [
              Variable(item.identity.sourceId),
              Variable(item.identity.localId),
            ],
          );
          if (item.parentId != null) {
            parents.add((
              sourceId: item.identity.sourceId,
              localId: item.parentId!,
            ));
          }
        }
        for (final parent in parents) {
          await database.customStatement(
            '''
            DELETE FROM media WHERE source_id = ? AND local_id = ? AND is_series = 1
              AND NOT EXISTS (SELECT 1 FROM media child
                WHERE child.source_id = media.source_id AND child.parent_id = media.local_id)
          ''',
            [parent.sourceId, parent.localId],
          );
        }
      });
      if (removed > 0) _changed();
      return (removed: removed, retained: requested.length - removed);
    } finally {
      _indexMaintenance = false;
      _maintenanceDone = null;
      done.complete();
    }
  }

  Future<String> _cleanupFingerprint(Set<MediaIdentity> requested) async {
    final sources = await database
        .customSelect('SELECT * FROM sources ORDER BY id')
        .get();
    final ids = requested.toList()
      ..sort((a, b) {
        final source = a.sourceId.compareTo(b.sourceId);
        return source == 0 ? a.localId.compareTo(b.localId) : source;
      });
    final records = <Map<String, Object?>>[];
    for (var offset = 0; offset < ids.length; offset += 200) {
      final chunk = ids.skip(offset).take(200).toList();
      final rows = await database
          .customSelect(
            'SELECT media.*, (SELECT value FROM remote_media_metadata r WHERE r.source_id = media.source_id AND r.local_id = media.local_id) AS remote_metadata FROM media WHERE (source_id, local_id) IN '
            '(${List.filled(chunk.length, '(?, ?)').join(',')}) ORDER BY source_id, local_id',
            variables: chunk
                .expand((id) => [Variable(id.sourceId), Variable(id.localId)])
                .toList(),
          )
          .get();
      records.addAll(rows.map((row) => row.data));
    }
    return jsonEncode([sources.map((row) => row.data).toList(), records]);
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
        SELECT media.*, (SELECT value FROM remote_media_metadata r WHERE r.source_id = media.source_id AND r.local_id = media.local_id) AS remote_metadata FROM media WHERE source_id = ? AND ${topLevelOnly ? 'parent_id IS NULL' : 'is_series = 0'}
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

  Future<List<IndexedMedia>> indexedSource(String id) async =>
      (await database
              .customSelect(
                '''
    SELECT media.*, r.value AS remote_metadata, a.updated_at AS activity_updated_at
    FROM media LEFT JOIN remote_media_metadata r USING(source_id, local_id)
    LEFT JOIN media_activity a USING(source_id, local_id)
    WHERE media.source_id = ? ORDER BY media.title COLLATE NOCASE, media.local_id
  ''',
                variables: [Variable(id)],
              )
              .get())
          .map(_media)
          .toList();

  IndexedMedia _media(QueryRow r) => IndexedMedia(
    updatedAt: r.data['activity_updated_at'] == null
        ? null
        : _date(r.read<int>('activity_updated_at')),
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
    remote: r.data['remote_metadata'] == null
        ? null
        : RemoteMediaMetadata.fromJson(
            jsonDecode(r.data['remote_metadata'] as String)
                as Map<String, dynamic>,
          ),
  );

  Future<IndexedMedia> media(MediaIdentity identity) async {
    final row = await database
        .customSelect(
          'SELECT media.*, (SELECT value FROM remote_media_metadata r WHERE r.source_id = media.source_id AND r.local_id = media.local_id) AS remote_metadata FROM media WHERE source_id = ? AND local_id = ?',
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
        SELECT media.*, (SELECT value FROM remote_media_metadata r WHERE r.source_id = media.source_id AND r.local_id = media.local_id) AS remote_metadata FROM media WHERE $where
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

  /// Remote sync is a snapshot transaction, not a filesystem scan. Failed or
  /// cancelled fetches never modify media, progress, or the last successful time.
  Future<SourceScanSummary> syncRemote(
    String id,
    Future<List<IndexedMedia>> Function(MediaSource, ScanCancellation) fetch, {
    void Function(SourceScanProgress)? onProgress,
    Future<void> Function()? commitSnapshot,
  }) {
    _requireIdle(id);
    if (_closed) throw const SourceFailure('媒体库已关闭。');
    final cancellation = ScanCancellation();
    _scans[id] = cancellation;
    final work = _syncRemote(
      id,
      cancellation,
      fetch,
      onProgress,
      commitSnapshot,
    );
    _pendingScans.add(work);
    return work.whenComplete(() {
      _pendingScans.remove(work);
      _scans.remove(id);
    });
  }

  Future<SourceScanSummary> _syncRemote(
    String id,
    ScanCancellation cancellation,
    Future<List<IndexedMedia>> Function(MediaSource, ScanCancellation) fetch,
    void Function(SourceScanProgress)? onProgress,
    Future<void> Function()? commitSnapshot,
  ) async {
    final runId = _newId();
    try {
      final current = await source(id);
      if (current.kind != MediaSourceKind.emby) {
        throw const SourceFailure('此来源不支持远程同步。');
      }
      final snapshot = await fetch(current, cancellation);
      cancellation.check();
      if (snapshot.any(
        (item) => item.identity.sourceId != id || item.remote == null,
      )) {
        throw const SourceFailure('远程媒体来源身份无效，已保留原索引。');
      }
      await database.transaction(() async {
        cancellation.check();
        final latest = await source(id);
        if (jsonEncode(latest.options.toJson()) !=
            jsonEncode(current.options.toJson())) {
          throw const SourceFailure('同步期间库范围已改变，请重新同步。');
        }
        for (final item in snapshot) {
          cancellation.check();
          await _upsert(
            runId,
            item,
            identityKind: item.isSeries ? 'show' : item.type,
          );
          final previousTrace =
              current.options.remoteTraceSyncMode ==
                  RemoteTraceSyncMode.disabled
              ? await database
                    .customSelect(
                      'SELECT value FROM remote_media_metadata WHERE source_id = ? AND local_id = ?',
                      variables: [
                        Variable(id),
                        Variable(item.identity.localId),
                      ],
                    )
                    .getSingleOrNull()
              : null;
          final metadata = item.remote!.toJson();
          if (previousTrace != null) {
            metadata['favorite'] =
                (jsonDecode(previousTrace.read<String>('value'))
                    as Map)['favorite'] ??
                false;
          }
          await database.customStatement(
            'INSERT INTO remote_media_metadata(source_id, local_id, value) VALUES (?, ?, ?) ON CONFLICT(source_id, local_id) DO UPDATE SET value = excluded.value',
            [id, item.identity.localId, jsonEncode(metadata)],
          );
          if (!item.isSeries) {
            final trace = item.remote!;
            // Disabled keeps existing local trace, but an initial import uses
            // server values, matching preservingLocalTraceForDisabledEmbySync.
            await database.customStatement(
              '''INSERT INTO playback_states(
              source_id, local_id, position_ms, duration_ms, watched, last_played_at)
              VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(source_id, local_id) DO UPDATE SET
                position_ms = excluded.position_ms, duration_ms = excluded.duration_ms,
                watched = excluded.watched, last_played_at = excluded.last_played_at
              WHERE ? != 'disabled'
              ''',
              [
                id,
                item.identity.localId,
                trace.positionMs,
                trace.durationMs ?? 0,
                trace.watched ? 1 : 0,
                trace.lastPlayedAt?.millisecondsSinceEpoch ?? 0,
                current.options.remoteTraceSyncMode.name,
              ],
            );
          }
        }
        await commitSnapshot?.call();
        await database.customStatement(
          'DELETE FROM media WHERE source_id = ? AND local_id NOT IN (SELECT local_id FROM scan_stage WHERE run_id = ?)',
          [id, runId],
        );
        await database.customStatement(
          'UPDATE sources SET last_scan = ? WHERE id = ?',
          [DateTime.now().toUtc().millisecondsSinceEpoch, id],
        );
        cancellation.check();
      });
      onProgress?.call(
        SourceScanProgress(
          totalFiles: snapshot.length,
          processedFiles: snapshot.length,
          importedItems: snapshot.length,
        ),
      );
      return SourceScanSummary(
        scannedFiles: snapshot.length,
        importedItems: snapshot.length,
        skippedFiles: 0,
        errors: const [],
      );
    } finally {
      await database.customStatement(
        'DELETE FROM scan_stage WHERE run_id = ?',
        [runId],
      );
      _changed();
    }
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
      if (_tracksIdentity(current.kind) && !await isSafeDirectory(current)) {
        throw const SourceFailure('无法确认原媒体来源的挂载状态或读取权限，已保留索引。请恢复挂载或重新定位来源。');
      }
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
        if (_tracksIdentity(current.kind) && !await isSafeDirectory(current)) {
          throw const SourceFailure('扫描结束时来源状态发生变化，已保留索引。');
        }
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
    await database.customStatement(
      '''
      DELETE FROM playback_states WHERE source_id = ? AND local_id = ?
        AND EXISTS (SELECT 1 FROM media WHERE source_id = ? AND local_id = ?
          AND identity_kind != ?)
    ''',
      [
        item.identity.sourceId,
        item.identity.localId,
        item.identity.sourceId,
        item.identity.localId,
        identityKind,
      ],
    );
    // MediaRepository.upsert retains missing descriptive fields. The original
    // scanner uses different ID prefixes for movie/episode/albumvideo/etc.; our
    // relative file key stays stable, so a kind change explicitly resets them.
    String metadataValue(String column) => item.remote != null
        ? 'excluded.$column'
        : 'CASE WHEN media.identity_kind = excluded.identity_kind '
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
    await database.customStatement(
      'INSERT OR IGNORE INTO media_library_preferences(source_id, local_id, user_rating, created_at) VALUES (?, ?, ?, ?)',
      [
        item.identity.sourceId,
        item.identity.localId,
        item.remote?.rating,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      '''INSERT INTO media_activity(source_id, local_id, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(source_id, local_id) DO UPDATE SET updated_at = excluded.updated_at''',
      [
        item.identity.sourceId,
        item.identity.localId,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
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
    await _maintenanceDone?.future;
    await _changes.close();
    await database.close();
  }
}
