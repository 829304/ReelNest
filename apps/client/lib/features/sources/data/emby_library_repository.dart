import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_client.dart';
import '../../../api/emby/emby_detail.dart';
import '../../../domain/media_source.dart';
import '../../../domain/remote_media_policy.dart';
import '../../playback/domain/playback_record.dart';
import '../../playback/data/playback_repository.dart';
import '../domain/emby_library.dart';
import 'source_repository.dart';

class EmbyVideoSnapshot {
  EmbyVideoSnapshot({
    required this.source,
    required List<EmbyLibrary> libraries,
    required List<VideoLibraryEntry> entries,
  }) : libraries = List.unmodifiable(libraries),
       entries = List.unmodifiable(entries),
       _base = null,
       _overrides = const {} {
    // Built once with the snapshot (in the worker for large libraries), rather
    // than traversing the entire library for each card entering the viewport.
    for (final entry in this.entries) {
      _positions[entry.item.identity] = _byIdentity.length;
      _byIdentity[entry.item.identity] = entry;
      if (entry.watchlist ||
          entry.userRating !=
              RemoteRatingPolicy.seedUserRating(entry.item.remote?.rating) ||
          entry.createdAt != entry.item.modified.toUtc()) {
        _preferenceCandidates.add(entry.item.identity);
      }
      final parent = entry.item.parentId;
      if (parent != null) {
        _children
            .putIfAbsent((
              sourceId: entry.item.identity.sourceId,
              localId: parent,
            ), () => [])
            .add(entry);
      }
    }
    _children.updateAll((_, children) => List.unmodifiable(children));
  }
  EmbyVideoSnapshot._preferences(
    EmbyVideoSnapshot base,
    Map<MediaIdentity, VideoLibraryEntry> overrides,
  ) : _base = base,
      _overrides = Map.unmodifiable(overrides),
      source = base.source,
      libraries = base.libraries,
      entries = _PreferenceEntries(base.entries, Map.unmodifiable(overrides));

  final EmbyVideoSnapshot? _base;
  final Map<MediaIdentity, VideoLibraryEntry> _overrides;
  EmbyVideoSnapshot get _root => _base ?? this;
  final _preferenceCandidates = <MediaIdentity>{};
  final MediaSource source;
  final List<EmbyLibrary> libraries;
  final List<VideoLibraryEntry> entries;
  final _positions = <MediaIdentity, int>{};
  final _byIdentity = <MediaIdentity, VideoLibraryEntry>{};
  final _children = <MediaIdentity, List<VideoLibraryEntry>>{};
  final _scopes = <EmbyVideoDestination, List<VideoLibraryEntry>>{};
  VideoLibraryEntry? entryFor(MediaIdentity identity) =>
      _overrides[identity] ?? _root._byIdentity[identity];
  List<VideoLibraryEntry> childrenOf(MediaIdentity identity) => _base == null
      ? _children[identity] ?? const []
      : _PreferenceEntries(_root.childrenOf(identity), _overrides);
  List<VideoLibraryEntry> scope(EmbyVideoDestination destination) {
    if (_base != null) {
      return _scopes.putIfAbsent(destination, () {
        if (destination.libraryId == null &&
            destination.section == EmbyVideoSection.watchlist) {
          final candidates = {
            ..._root._preferenceCandidates,
            ..._overrides.keys,
          };
          // Preserve the original snapshot order, including title ties.
          final result =
              candidates
                  .map(entryFor)
                  .whereType<VideoLibraryEntry>()
                  .where(
                    (e) =>
                        e.watchlist &&
                        e.item.parentId == null &&
                        e.item.displayType != 'music' &&
                        e.item.identity.sourceId == destination.sourceId,
                  )
                  .toList()
                ..sort(
                  (a, b) => _root._positions[a.item.identity]!.compareTo(
                    _root._positions[b.item.identity]!,
                  ),
                );
          return List.unmodifiable(result);
        }
        return _PreferenceEntries(_root.scope(destination), _overrides);
      });
    }
    return _scopes.putIfAbsent(
      destination,
      () => List.unmodifiable(
        entries.where((e) {
          if (e.item.identity.sourceId != destination.sourceId ||
              e.item.parentId != null ||
              e.item.displayType == 'music') {
            return false;
          }
          if (destination.libraryId != null) {
            return e.item.remote?.libraryId == destination.libraryId;
          }
          return switch (destination.section) {
            EmbyVideoSection.videos => true,
            EmbyVideoSection.watchlist => e.watchlist,
            EmbyVideoSection.favorites => e.item.remote?.favorite == true,
          };
        }),
      ),
    );
  }
}

class _PreferenceEntries extends ListBase<VideoLibraryEntry> {
  _PreferenceEntries(this.base, this.overrides);
  final List<VideoLibraryEntry> base;
  final Map<MediaIdentity, VideoLibraryEntry> overrides;
  @override
  int get length => base.length;
  @override
  set length(int value) => throw UnsupportedError("Immutable snapshot");
  @override
  VideoLibraryEntry operator [](int index) {
    final entry = base[index];
    return overrides[entry.item.identity] ?? entry;
  }

  @override
  void operator []=(int index, VideoLibraryEntry value) =>
      throw UnsupportedError("Immutable snapshot");
}

class EmbyLibraryRepository {
  const EmbyLibraryRepository(this.sources);
  final SourceRepository sources;

  /// Sidebar visibility does not need episodes, playback records or details.
  /// Probe only eligible top-level rows, stopping at the first visible match.
  Future<Set<EmbyVideoSection>> sidebarSections(String sourceId) async {
    final result = <EmbyVideoSection>{};
    for (final section in EmbyVideoSection.values) {
      final predicate = switch (section) {
        EmbyVideoSection.videos => '1 = 1',
        EmbyVideoSection.watchlist => 'p.watchlist = 1',
        EmbyVideoSection.favorites =>
          "json_extract(r.value, '\$.favorite') = 1",
      };
      const limit = 64;
      for (var offset = 0; ; offset += limit) {
        final rows = await sources.database
            .customSelect(
              '''
          SELECT m.type,
            json_extract(r.value, '\$.libraryName') AS library_name,
            json_extract(r.value, '\$.collectionType') AS collection_type,
            json_extract(r.value, '\$.genres') AS genres
          FROM media m INDEXED BY media_parent
          ${section == EmbyVideoSection.watchlist ? 'CROSS JOIN media_library_preferences p ON p.source_id = m.source_id AND p.local_id = m.local_id' : ''}
          LEFT JOIN remote_media_metadata r
            ON r.source_id = m.source_id AND r.local_id = m.local_id
          WHERE m.source_id = ? AND m.parent_id IS NULL
            AND m.type != 'music' AND $predicate
          LIMIT ? OFFSET ?
        ''',
              variables: [
                Variable(sourceId),
                Variable(limit),
                Variable(offset),
              ],
            )
            .get();
        final visible = rows.any(
          (row) =>
              RemoteLibraryClassificationPolicy.inferredMediaType(
                type: row.read<String>('type'),
                libraryName: row.readNullable<String>('library_name'),
                collectionType: row.readNullable<String>('collection_type'),
                genres: (jsonDecode(
                  row.readNullable<String>('genres') ?? '[]',
                ) as List).cast<String>(),
              ) !=
              'music',
        );
        if (visible) result.add(section);
        if (visible || rows.length < limit) break;
      }
    }
    return result;
  }

  Future<void> replaceViews(String sourceId, List<EmbyLibrary> views) async {
    await sources.database.customStatement(
      'DELETE FROM remote_library_views WHERE source_id = ?',
      [sourceId],
    );
    for (final view in views) {
      await sources.database.customStatement(
        'INSERT INTO remote_library_views(source_id, library_id, name, collection_type) VALUES (?, ?, ?, ?)',
        [sourceId, view.id, view.name, view.collectionType],
      );
    }
  }

  Future<EmbyVideoSnapshot> snapshot(String sourceId) async {
    final data = await sources.database.transaction(() async {
      final source = await sources.source(sourceId);
      if (!source.kind.isEmbyCompatible) {
        throw const SourceFailure('此来源不是远程媒体库。');
      }
      final rows = await sources.database
          .customSelect(
            '''
      SELECT m.*, r.value AS remote_metadata, a.updated_at AS activity_updated_at,
        p.local_id AS preference_id, p.watchlist, p.user_rating, p.created_at,
        s.position_ms, s.duration_ms, s.watched, s.last_played_at, d.value AS details,
        t.key AS local_trace
      FROM media m
      LEFT JOIN remote_media_metadata r USING(source_id, local_id)
      LEFT JOIN media_activity a USING(source_id, local_id)
      LEFT JOIN media_library_preferences p USING(source_id, local_id)
      LEFT JOIN playback_states s USING(source_id, local_id)
      LEFT JOIN player_preferences t ON t.key = '${PlaybackRepository.localTracePrefix}' || json_array(m.source_id,m.local_id)
      LEFT JOIN remote_media_details d USING(source_id, local_id)
      WHERE m.source_id = ? ORDER BY m.title COLLATE NOCASE, m.local_id
    ''',
            variables: [Variable(sourceId)],
          )
          .get();
      final views = await sources.database
          .customSelect(
            'SELECT * FROM remote_library_views WHERE source_id = ?',
            variables: [Variable(sourceId)],
          )
          .get();
      return _SnapshotData(
        source,
        rows.map((r) => r.data).toList(),
        views.map((r) => r.data).toList(),
      );
    });
    return data.rows.length > 180
        ? _snapshotInBackground(data)
        : _buildSnapshot(data);
  }

  Future<List<IndexedMedia>> targets(
    Iterable<MediaIdentity> identities, {
    bool descendants = false,
  }) async {
    final ids = identities.toSet();
    if (ids.isEmpty) return [];
    final sourceId = ids.first.sourceId;
    if (ids.any((id) => id.sourceId != sourceId) ||
        !(await sources.source(
          sourceId,
          includeCounts: false,
        )).kind.isEmbyCompatible) {
      throw const SourceFailure('请选择同一远程媒体库来源的内容。');
    }
    final items = await sources.indexedSelection(
      sourceId,
      ids.map((id) => id.localId),
      descendants: descendants,
    );
    final byId = {for (final item in items) item.identity: item};
    for (final id in ids) {
      if (byId[id]?.remote == null || byId[id]?.type == 'music') {
        throw const SourceFailure('部分内容已移除或不支持此操作，请刷新媒体库。');
      }
    }
    final result = <IndexedMedia>[];
    final visited = <MediaIdentity>{};
    final children = <String, List<IndexedMedia>>{};
    for (final item in items) {
      if (item.parentId != null) (children[item.parentId!] ??= []).add(item);
    }
    void add(IndexedMedia item) {
      if (!visited.add(item.identity)) return;
      result.add(item);
      if (descendants) {
        for (final child
            in children[item.identity.localId] ?? <IndexedMedia>[]) {
          add(child);
        }
      }
    }

    for (final id in ids) {
      add(byId[id]!);
    }
    return result;
  }

  Future<void> setWatchlist(MediaIdentity id, bool value) =>
      setWatchlistMany([id], value);

  Future<void> setWatchlistMany(Iterable<MediaIdentity> ids, bool value) async {
    final identities = ids.toSet();
    await sources.database.transaction(() async {
      final items = await targets(identities);
      for (final item in items) {
        await sources.database.customStatement(
          '''INSERT INTO media_library_preferences(source_id,local_id,watchlist,user_rating,created_at)
             VALUES (?,?,?,?,?) ON CONFLICT(source_id,local_id)
             DO UPDATE SET watchlist=excluded.watchlist''',
          [
            item.identity.sourceId,
            item.identity.localId,
            value ? 1 : 0,
            RemoteRatingPolicy.seedUserRating(item.remote?.rating),
            item.modified.millisecondsSinceEpoch,
          ],
        );
      }
    });
    sources.libraryPreferencesChanged(identities.map((id) => id.sourceId));
  }

  Future<void> setRating(Iterable<MediaIdentity> ids, double? rating) async {
    if (rating != null && (!rating.isFinite || rating < 1 || rating > 5)) {
      throw const SourceFailure('评级必须在 1 到 5 星之间。');
    }
    final identities = ids.toSet();
    await sources.database.transaction(() async {
      final items = await targets(identities);
      for (final item in items) {
        await sources.database.customStatement(
          '''INSERT INTO media_library_preferences(source_id,local_id,watchlist,user_rating,created_at)
             VALUES (?,?,0,?,?) ON CONFLICT(source_id,local_id)
             DO UPDATE SET user_rating=excluded.user_rating''',
          [
            item.identity.sourceId,
            item.identity.localId,
            rating,
            item.modified.millisecondsSinceEpoch,
          ],
        );
      }
    });
    sources.libraryPreferencesChanged(identities.map((id) => id.sourceId));
  }

  /// Overlay local preferences without re-reading/decoding remote details,
  /// episode metadata, playback history or the source's aggregate counts.
  Future<EmbyVideoSnapshot> refreshPreferences(EmbyVideoSnapshot base) async {
    final rows = await sources.database
        .customSelect(
          'SELECT * FROM media_library_preferences WHERE source_id = ?',
          variables: [Variable(base.source.id)],
        )
        .get();
    final byId = {for (final row in rows) row.read<String>('local_id'): row};
    // Always rebase on content, never chain overlays or traverse all episodes.
    final root = base._root;
    final candidates = {
      ...root._preferenceCandidates,
      for (final id in byId.keys) (sourceId: root.source.id, localId: id),
    };
    final overrides = <MediaIdentity, VideoLibraryEntry>{};
    for (final id in candidates) {
      final entry = root.entryFor(id);
      if (entry == null) continue;
      final row = byId[entry.item.identity.localId];
      final watchlist = row?.read<int>('watchlist') == 1;
      final rating = row == null
          ? RemoteRatingPolicy.seedUserRating(entry.item.remote?.rating)
          : row.readNullable<double>('user_rating');
      final createdAt = row == null
          ? entry.item.modified.toUtc()
          : DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('created_at'),
              isUtc: true,
            );
      if (watchlist == entry.watchlist &&
          rating == entry.userRating &&
          createdAt == entry.createdAt) {
        continue;
      }
      overrides[id] = VideoLibraryEntry(
        item: entry.item,
        record: entry.record,
        createdAt: createdAt,
        watchlist: watchlist,
        userRating: rating,
        searchTerms: entry.searchTerms,
        reportedProgress: entry.reportedProgress,
        episodePlayback: entry.episodePlayback,
      );
    }
    return overrides.isEmpty
        ? root
        : EmbyVideoSnapshot._preferences(root, overrides);
  }

  Future<int> removeFromLibrary(Iterable<MediaIdentity> ids) async {
    final items = await targets(ids, descendants: true);
    return sources.removeIndexedItems(items.map((i) => i.identity).toSet());
  }

  String _viewKey(EmbyVideoDestination id) =>
      'library.view.${jsonEncode([id.sourceId, id.section.name, id.libraryId])}';
  Future<VideoLibrarySettings> settings(EmbyVideoDestination id) async {
    final value = await preference(_viewKey(id));
    return value == null
        ? const VideoLibrarySettings()
        : VideoLibrarySettings.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          );
  }

  Future<void> saveSettings(
    EmbyVideoDestination id,
    VideoLibrarySettings settings,
  ) => savePreference(_viewKey(id), jsonEncode(settings.toJson()));
  Future<String?> preference(String key) async =>
      (await sources.database
              .customSelect(
                'SELECT value FROM player_preferences WHERE key = ?',
                variables: [Variable(key)],
              )
              .getSingleOrNull())
          ?.read<String>('value');
  Future<void> savePreference(String key, String value) =>
      sources.database.customStatement(
        'INSERT INTO player_preferences(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );
}

/// Only plain rows and immutable models cross this worker boundary; no live
/// database, credential, stream or provider is captured.
class _SnapshotData {
  const _SnapshotData(this.source, this.rows, this.views);
  final MediaSource source;
  final List<Map<String, dynamic>> rows, views;
}

class _SnapshotRow {
  const _SnapshotRow(this.data);
  final Map<String, dynamic> data;
  T read<T>(String key) => data[key] as T;
  T? readNullable<T>(String key) => data[key] as T?;
}

Future<EmbyVideoSnapshot> _snapshotInBackground(_SnapshotData data) =>
    Isolate.run(() => _buildSnapshot(data));

EmbyVideoSnapshot _buildSnapshot(_SnapshotData data) {
  final source = data.source;
  final items = data.rows.map(SourceRepository.decodeIndexedRow).toList();
  final rows = data.rows.map(_SnapshotRow.new).toList();
  final views = data.views.map(_SnapshotRow.new).toList();
  final byId = {for (final r in rows) r.read<String>('local_id'): r};
  final children = <String, List<IndexedMedia>>{};
  for (final item in items) {
    if (item.parentId != null) {
      (children[item.parentId!] ??= []).add(item);
    }
  }
  List<String?> terms(IndexedMedia item) => [
    item.title,
    item.originalTitle,
    item.overview,
    item.year?.toString(),
    item.remote?.externalId,
    source.kind.label,
    item.remote?.genres.join(', '),
    item.remote?.videoCodec,
    item.remote?.audioCodec,
    item.remote?.resolution,
    item.episodeLabel,
    if (item.seasonNumber != null) '第 ${item.seasonNumber} 季',
    if (item.episodeNumber != null) '第 ${item.episodeNumber} 集',
  ];
  final entries = <VideoLibraryEntry>[];
  for (final item in items) {
    final row = byId[item.identity.localId]!;
    final detail = row.readNullable<String>('details');
    final extra = detail == null
        ? null
        : EmbyDetail.fromJson(jsonDecode(detail) as Map<String, dynamic>);
    final remote = item.remote;
    entries.add(
      VideoLibraryEntry(
        item: item,
        reportedProgress: row.readNullable<String>('local_trace') == null
            ? remote?.playedPercentage == null
                  ? null
                  : remote!.playedPercentage! / 100
            : null,
        record: PlaybackRecord(
          identity: item.identity,
          position: Duration(
            milliseconds:
                row.readNullable<int>('position_ms') ?? remote?.positionMs ?? 0,
          ),
          duration: Duration(
            milliseconds:
                row.readNullable<int>('duration_ms') ?? remote?.durationMs ?? 0,
          ),
          watched:
              (row.readNullable<int>('watched') ??
                  (remote?.watched == true ? 1 : 0)) ==
              1,
          lastPlayedAt: switch (row.readNullable<int>('last_played_at')) {
            null => remote?.lastPlayedAt,
            0 => null,
            final value => DateTime.fromMillisecondsSinceEpoch(
              value,
              isUtc: true,
            ),
          },
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row.readNullable<int>('created_at') ??
              item.modified.millisecondsSinceEpoch,
          isUtc: true,
        ),
        watchlist: row.readNullable<int>('watchlist') == 1,
        userRating: row.readNullable<String>('preference_id') == null
            ? RemoteRatingPolicy.seedUserRating(remote?.rating)
            : row.readNullable<double>('user_rating'),
        searchTerms: [
          ...terms(item),
          if (extra != null) ...[
            extra.overview,
            ...extra.people.map((p) => p.name),
            ...extra.companies,
            ...extra.countries,
          ],
          for (final child
              in children[item.identity.localId] ?? <IndexedMedia>[])
            ...terms(child),
        ],
      ),
    );
  }
  final selected = source.options.selectedEmbyLibraryIDs;
  final episodesByParent = <String, List<PlaybackRecord>>{};
  for (final entry in entries) {
    final parent = entry.item.parentId;
    if (parent != null &&
        entry.item.type == 'episode' &&
        entry.item.displayType != 'music') {
      (episodesByParent[parent] ??= []).add(entry.record);
    }
  }
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry.item.isSeries) {
      entries[i] = entry.withEpisodePlayback(
        episodesByParent[entry.item.identity.localId] ?? const [],
      );
    }
  }
  final libraries =
      views
          .map(
            (r) => EmbyLibrary(
              id: r.read<String>('library_id'),
              name: r.read<String>('name'),
              collectionType: r.readNullable<String>('collection_type'),
            ),
          )
          .where(
            (v) =>
                (selected.isEmpty || selected.contains(v.id)) &&
                v.collectionType?.toLowerCase() != 'music' &&
                v.collectionType?.toLowerCase() != 'photos',
          )
          .toList()
        ..sort((a, b) => libraryTitleCompare(a.name, b.name));
  return EmbyVideoSnapshot(
    source: source,
    libraries: libraries,
    entries: entries,
  );
}
