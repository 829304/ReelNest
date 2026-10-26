import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_detail.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/remote_media_policy.dart';
import '../../playback/domain/playback_record.dart';
import '../../playback/data/playback_repository.dart';
import '../../sources/data/source_repository.dart';
import '../../sources/domain/emby_library.dart';
import '../domain/home_snapshot.dart';
import '../domain/home_search.dart';
import 'home_search_worker.dart';

class HomeRepository {
  HomeRepository(this.sources);
  // Only decoded search documents are retained, never database/worker handles.
  final _searchIndexes = <String, _CachedSearchIndex>{};
  static const _maxSearchDocuments = 50000;
  static const _maxSearchCharacters = 8 * 1024 * 1024;

  Future<(int, int)> _searchRevision() async {
    final row = await sources.database
        .customSelect(
          'SELECT total_changes() AS local_revision, data_version AS external_revision FROM pragma_data_version',
        )
        .getSingle();
    return (
      row.read<int>('local_revision'),
      row.read<int>('external_revision'),
    );
  }

  void _retainSearchIndex(String id, _CachedSearchIndex index) {
    _searchIndexes.remove(id);
    if (index.documents.length > _maxSearchDocuments ||
        index.characters > _maxSearchCharacters) {
      return;
    }
    _searchIndexes[id] = index;
    while (_searchIndexes.length > 4 ||
        _searchIndexes.values.fold(0, (n, e) => n + e.documents.length) >
            _maxSearchDocuments ||
        _searchIndexes.values.fold(0, (n, e) => n + e.characters) >
            _maxSearchCharacters) {
      _searchIndexes.remove(_searchIndexes.keys.first);
    }
  }

  final SourceRepository sources;

  static bool accepts(MediaSource source) =>
      (source.kind.isFileSource || source.kind.isEmbyCompatible) &&
      !{
        SourceMediaType.privateCollection,
        SourceMediaType.photo,
        SourceMediaType.music,
      }.contains(source.mediaType);

  // Do not join details or read a complete connector snapshot. This projection
  // stays in SQLite; only bounded card rows/grouped counts cross to Dart.
  String get _scope =>
      '''WITH RECURSIVE blocked(local_id) AS (
    SELECT local_id FROM media WHERE source_id = ? AND type IN ('private','privateCollection','photo')
    UNION SELECT child.local_id FROM media child INDEXED BY media_parent JOIN blocked parent
      ON child.parent_id = parent.local_id WHERE child.source_id = ?
  ), scope AS NOT MATERIALIZED (
    SELECT m.*, r.value AS remote_metadata, a.updated_at AS activity_updated_at,
      COALESCE(p.created_at,m.modified) AS created_at,
      p.user_rating, COALESCE(p.watchlist,0) AS watchlist,
      COALESCE(json_extract(r.value,'\$.favorite'), f.value = 'true',0) AS favorite,
      COALESCE(json_extract(r.value,'\$.rating'),json_extract(lm.value,'\$.candidate.rating'),json_extract(lt.value,'\$.candidate.rating')) AS metadata_rating,
      MAX(COALESCE(json_extract(r.value,'\$.rating'),json_extract(lm.value,'\$.candidate.rating'),json_extract(lt.value,'\$.candidate.rating'),0),COALESCE(p.user_rating * 2,0)) AS score,
      COALESCE(s.position_ms,json_extract(r.value,'\$.positionMs'),0) AS position_ms,
      COALESCE(s.duration_ms,json_extract(r.value,'\$.durationMs'),0) AS duration_ms,
      CASE WHEN t.key IS NULL THEN json_extract(r.value,'\$.playedPercentage') / 100.0 END AS reported_progress,
      COALESCE(s.watched,json_extract(r.value,'\$.watched'),0) AS watched,
      CASE WHEN s.last_played_at IS NOT NULL THEN NULLIF(s.last_played_at,0)
        ELSE CAST(ROUND((julianday(json_extract(r.value,'\$.lastPlayedAt')) - 2440587.5) * 86400000) AS INTEGER) END AS last_played_at
    FROM media m
    LEFT JOIN remote_media_metadata r USING(source_id,local_id)
    LEFT JOIN local_movie_metadata lm USING(source_id,local_id)
    LEFT JOIN local_series_metadata lt USING(source_id,local_id)
    LEFT JOIN media_activity a USING(source_id,local_id)
    LEFT JOIN media_library_preferences p USING(source_id,local_id)
    LEFT JOIN playback_states s USING(source_id,local_id)
    LEFT JOIN player_preferences t ON t.key = '${PlaybackRepository.localTracePrefix}' || json_array(m.source_id,m.local_id)
    LEFT JOIN player_preferences f ON f.key = 'library.favorite.' || json_array(m.source_id,m.local_id)
    WHERE m.source_id = ? AND m.type NOT IN ('music','photo','private','privateCollection')
      AND m.local_id NOT IN (SELECT local_id FROM blocked)
      AND (? = '[]' OR json_extract(r.value,'\$.libraryId') IN (SELECT value FROM json_each(?)))
  )''';

  List<Variable> _variables(MediaSource source) {
    final selected = source.kind.isEmbyCompatible
        ? jsonEncode(source.options.selectedEmbyLibraryIDs)
        : '[]';
    return [
      Variable(source.id),
      Variable(source.id),
      Variable(source.id),
      Variable(selected),
      Variable(selected),
    ];
  }

  static const _progress =
      'CASE WHEN duration_ms > 0 THEN 1.0 * position_ms / duration_ms ELSE COALESCE(reported_progress,0) END';
  static const _recency =
      'COALESCE(last_played_at,activity_updated_at,modified)';

  /// Recommendation scoring needs all public top-level candidates, never all
  /// episodes/details. Transfer and decode this projection off the UI isolate.
  Future<List<HomeVideo>> recommendationCandidates(String sourceId) async {
    final source = await sources.source(sourceId, includeCounts: false);
    if (!accepts(source)) return [];
    final rows = await sources.database.customSelect('''$_scope
      SELECT * FROM scope WHERE parent_id IS NULL AND type != 'episode'
      ORDER BY local_id
    ''', variables: _variables(source)).get();
    final data = rows.map((r) => r.data).toList();
    return data.length > 180
        ? Isolate.run(() => _recommendationCandidates(data, source))
        : _recommendationCandidates(data, source);
  }

  /// One coherent SQLite snapshot, including cached details and public child
  /// titles. No connector/HTTP calls, per-card queries or complete scan.
  Future<List<HomeVideo>> search(
    String sourceId,
    String query, {
    required String scope,
    required ScanCancellation cancellation,
  }) async {
    cancellation.check();
    if (query.trim().isEmpty) return [];
    // Retry a changed database snapshot; a version mismatch is not an empty
    // search result. Bound retries so continuous writes cannot starve the UI.
    for (var attempt = 0; attempt < 3; attempt++) {
      cancellation.check();
      final source = await sources.source(sourceId, includeCounts: false);
      cancellation.check();
      if (!accepts(source) || homeSearchScope(source) != scope) return [];
      // total_changes observes this connection's writes, data_version observes
      // other connections (including the player window). Do not rely only on
      // UI notifications: detail caching and direct writes must expire the index.
      final revision = await _searchRevision();
      _searchIndexes.removeWhere((_, value) => value.revision != revision);
      var index = _searchIndexes[sourceId];
      if (index == null || index.scope != scope) {
        final rows = await sources.database.customSelect('''$_scope
        SELECT scope.*, d.value AS details FROM scope
        LEFT JOIN remote_media_details d USING(source_id,local_id)
        ORDER BY local_id
      ''', variables: _variables(source)).get();
        cancellation.check();
        final data = rows.map((r) => r.data).toList();
        final documents = data.length > 180
            ? await runHomeSearchWorker(_indexWork(data, source), cancellation)
            : _buildSearchIndex(data, source);
        index = _CachedSearchIndex(
          scope,
          revision,
          documents,
          data.length > 180,
        );
      }
      cancellation.check();
      final documents = index.documents;
      // A single series can contain thousands of episode search fields. Preserve
      // the original row-based worker threshold after projecting to root items.
      final results = index.useWorker
          ? await runHomeSearchWorker(
              _filterWork(documents, query),
              cancellation,
            )
          : _filterSearchIndex(documents, query);
      cancellation.check();
      final current = await sources.source(sourceId, includeCounts: false);
      final latest = await _searchRevision();
      cancellation.check();
      if (!accepts(current) || homeSearchScope(current) != scope) return [];
      if (latest != revision) continue;
      _retainSearchIndex(sourceId, index);
      return results;
    }
    throw const SourceFailure('媒体索引正在更新，请稍后重试搜索。');
  }

  /// Original includesCachedVideo: a series is offline-ready if at least one
  /// child has a valid cached file. Call only with file-validated identities.
  Future<Set<MediaIdentity>> offlineParents(Set<MediaIdentity> valid) async {
    final result = <MediaIdentity>{...valid};
    for (final id in valid.map((v) => v.sourceId).toSet()) {
      final source = await sources.source(id, includeCounts: false);
      if (!accepts(source)) continue;
      final children = jsonEncode(
        valid.where((v) => v.sourceId == id).map((v) => v.localId).toList(),
      );
      final rows = await sources.database
          .customSelect(
            '''$_scope
        SELECT DISTINCT parent_id FROM scope WHERE parent_id IS NOT NULL
        AND local_id IN (SELECT value FROM json_each(?))
      ''',
            variables: [..._variables(source), Variable(children)],
          )
          .get();
      for (final row in rows) {
        result.add((sourceId: id, localId: row.read<String>('parent_id')));
      }
    }
    return result;
  }

  Future<HomeStats> stats(String sourceId, double threshold) async {
    final source = await sources.source(sourceId, includeCounts: false);
    if (!accepts(source)) return const HomeStats();
    final rows = await sources.database
        .customSelect(
          '''$_scope
      SELECT type, parent_id IS NOT NULL AS child,
        json_extract(remote_metadata,'\$.libraryName') AS library_name,
        json_extract(remote_metadata,'\$.collectionType') AS collection_type,
        json_extract(remote_metadata,'\$.genres') AS genres,
        watched = 1 OR $_progress >= ? AS finished, COUNT(*) AS count
      FROM scope GROUP BY type,child,library_name,collection_type,genres,finished
    ''',
          variables: [..._variables(source), Variable(threshold)],
        )
        .get();
    final data = rows.map((r) => r.data).toList();
    return data.length > 180 ? Isolate.run(() => _stats(data)) : _stats(data);
  }

  /// Offsets advance through classified exclusions as well as visible cards.
  /// View-more uses the same query/order, never a truncated cached snapshot.
  Future<HomeVideoPage> page(
    String sourceId,
    HomeCollection collection, {
    int offset = 0,
    int limit = 36,
    double threshold = .9,
  }) async {
    final source = await sources.source(sourceId, includeCounts: false);
    if (!accepts(source)) {
      return HomeVideoPage(const [], nextOffset: offset, hasMore: false);
    }
    final seriesKeys =
        collection == HomeCollection.recentSeries ||
            collection == HomeCollection.continueWatching
        ? await _seriesKeys(source)
        : null;
    final items = <HomeVideo>[];
    var position = offset, more = true;
    while (items.length < limit && more) {
      final take = (limit - items.length).clamp(1, 64);
      final predicate = switch (collection) {
        HomeCollection.seriesRecommendations || HomeCollection.highRated =>
          throw ArgumentError('Recommendations use the daily board projection'),
        HomeCollection.continueWatching =>
          'parent_id IS NULL AND is_series = 0 AND $_progress > 0 AND $_progress < 0.95',
        HomeCollection.recentlyPlayed =>
          'parent_id IS NULL AND (position_ms > 0 OR $_progress > 0 OR watched = 1 OR last_played_at IS NOT NULL)',
        HomeCollection.watchlist => 'parent_id IS NULL AND watchlist = 1',
        HomeCollection.favorites => 'parent_id IS NULL AND favorite = 1',
        HomeCollection.recentSeries => "parent_id IS NULL AND json_array(type,json_extract(remote_metadata,'\$.libraryName'),json_extract(remote_metadata,'\$.collectionType'),json_extract(remote_metadata,'\$.genres')) IN (SELECT value FROM json_each(?))",
      };
      final order = switch (collection) {
        HomeCollection.seriesRecommendations ||
        HomeCollection.highRated => 'score DESC',
        HomeCollection.continueWatching => 'COALESCE(last_played_at,0) DESC',
        HomeCollection.recentlyPlayed => '$_recency DESC',
        HomeCollection.watchlist =>
          'score DESC, COALESCE(activity_updated_at,modified) DESC',
        HomeCollection.favorites => '$_recency DESC, score DESC',
        HomeCollection.recentSeries =>
          'COALESCE(activity_updated_at,modified) DESC',
      };
      // Window rank follows MediaHierarchyPolicy, including special/missing
      // seasons. Next up is after the *last* finished episode, never episode+1.
      final next = collection == HomeCollection.continueWatching
          ? ''', ordered AS (
        SELECT local_id, parent_id,
          ROW_NUMBER() OVER (PARTITION BY parent_id ORDER BY COALESCE(season_number,0),COALESCE(episode_number,0),title COLLATE NOCASE,local_id) AS n,
          watched = 1 OR $_progress >= ? AS finished
        FROM scope WHERE parent_id IS NOT NULL AND type = 'episode'
      ), last_finished AS (SELECT parent_id, MAX(n) AS n FROM ordered WHERE finished GROUP BY parent_id),
      next_ids AS (SELECT o.local_id FROM ordered o JOIN last_finished l ON o.parent_id=l.parent_id AND o.n=l.n+1 WHERE NOT o.finished)
      '''
          : '';
      // Apply the original preference for series/next-up before LIMIT: a long
      // movie history must not hide next-up cards on a later page.
      final from = next.isEmpty ? 'scope' : 'candidates';
      final candidates = next.isEmpty
          ? ''
          : ''', candidates AS (
        SELECT * FROM scope WHERE ($predicate) OR local_id IN (SELECT local_id FROM next_ids)
      ), preferred AS (
        SELECT local_id FROM candidates WHERE type = 'episode' OR
          json_array(type,json_extract(remote_metadata,'\$.libraryName'),json_extract(remote_metadata,'\$.collectionType'),json_extract(remote_metadata,'\$.genres')) IN (SELECT value FROM json_each(?))
      )''';
      final filter = next.isEmpty
          ? predicate
          : 'NOT EXISTS(SELECT 1 FROM preferred) OR local_id IN(SELECT local_id FROM preferred)';
      final rows = await sources.database
          .customSelect(
            '''$_scope $next $candidates
        SELECT * FROM $from WHERE ($filter)
        ORDER BY $order, title COLLATE NOCASE,local_id LIMIT ? OFFSET ?
      ''',
            variables: [
              ..._variables(source),
              if (next.isNotEmpty) Variable(threshold),
              if (seriesKeys != null) Variable(seriesKeys),
              Variable(take),
              Variable(position),
            ],
          )
          .get();
      position += rows.length;
      more = rows.length == take;
      for (final row in rows) {
        final item = SourceRepository.decodeIndexedRow(row.data);
        if (item.displayType == 'music') continue;
        if (collection == HomeCollection.recentSeries &&
            !HomeVideoPolicy.seriesTypes.contains(item.displayType)) {
          continue;
        }
        DateTime? date(String key) {
          final value = row.readNullable<int>(key);
          return value == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        }

        items.add(
          HomeVideo(
            source: source,
            favorite: row.read<int>('favorite') == 1,
            metadataRating: row.readNullable<double>('metadata_rating'),
            entry: VideoLibraryEntry(
              item: item,
              reportedProgress: row.readNullable<double>('reported_progress'),
              record: PlaybackRecord(
                identity: item.identity,
                position: Duration(milliseconds: row.read<int>('position_ms')),
                duration: Duration(milliseconds: row.read<int>('duration_ms')),
                watched: row.read<int>('watched') == 1,
                lastPlayedAt: date('last_played_at'),
              ),
              createdAt: date('created_at')!,
              watchlist: row.read<int>('watchlist') == 1,
              userRating: row.readNullable<double>('user_rating'),
            ),
          ),
        );
      }
    }
    return HomeVideoPage(
      List.unmodifiable(items),
      nextOffset: position,
      hasMore: more,
    );
  }

  Future<String> _seriesKeys(MediaSource source) async {
    final groups = await sources.database.customSelect('''$_scope
      SELECT DISTINCT type, json_extract(remote_metadata,'\$.libraryName') AS name,
        json_extract(remote_metadata,'\$.collectionType') AS collection,
        json_extract(remote_metadata,'\$.genres') AS genres,
        json_array(type,json_extract(remote_metadata,'\$.libraryName'),json_extract(remote_metadata,'\$.collectionType'),json_extract(remote_metadata,'\$.genres')) AS classification_key
      FROM scope WHERE parent_id IS NULL
    ''', variables: _variables(source)).get();
    return jsonEncode(
      groups
          .where(
            (row) => HomeVideoPolicy.seriesTypes.contains(
              RemoteLibraryClassificationPolicy.inferredMediaType(
                type: row.read<String>('type'),
                libraryName: row.readNullable<String>('name'),
                collectionType: row.readNullable<String>('collection'),
                genres: (jsonDecode(
                  row.readNullable<String>('genres') ?? '[]',
                ) as List).cast<String>(),
              ),
            ),
          )
          // Keep SQLite's JSON subtype/escaping exactly as the page predicate.
          .map((row) => row.read<String>('classification_key'))
          .toList(),
    );
  }

  Future<MediaIdentity> playbackTarget(
    MediaIdentity series,
    double threshold,
  ) async {
    final source = await sources.source(series.sourceId, includeCounts: false);
    final rows = await sources.database
        .customSelect(
          '''$_scope
      SELECT local_id,watched,position_ms,duration_ms,last_played_at,$_progress AS progress FROM scope
      WHERE parent_id = ? AND type = 'episode'
      ORDER BY COALESCE(season_number,0),COALESCE(episode_number,0),title COLLATE NOCASE,local_id
    ''',
          variables: [..._variables(source), Variable(series.localId)],
        )
        .get();
    if (rows.isEmpty) throw const SourceFailure('此媒体没有可播放文件。');
    var lastFinished = -1;
    QueryRow? resume;
    for (var n = 0; n < rows.length; n++) {
      final row = rows[n];
      final progress = row.read<double>('progress');
      if (row.read<int>('watched') == 1 || progress >= threshold) {
        lastFinished = n;
      } else if (progress > 0 &&
          progress < .95 &&
          (resume == null ||
              (row.readNullable<int>('last_played_at') ?? 0) >
                  (resume.readNullable<int>('last_played_at') ?? 0))) {
        resume = row;
      }
    }
    final target =
        resume ??
        (lastFinished + 1 < rows.length ? rows[lastFinished + 1] : rows.first);
    return (
      sourceId: series.sourceId,
      localId: target.read<String>('local_id'),
    );
  }

  Future<void> ensurePublic(MediaIdentity id) async {
    final source = await sources.source(id.sourceId, includeCounts: false);
    final row = !accepts(source)
        ? null
        : await sources.database
              .customSelect(
                '''$_scope
      SELECT * FROM scope WHERE local_id = ? LIMIT 1
    ''',
                variables: [..._variables(source), Variable(id.localId)],
              )
              .getSingleOrNull();
    if (row == null ||
        SourceRepository.decodeIndexedRow(row.data).displayType == 'music') {
      throw const SourceFailure('此媒体已移除或不在公开首页范围内。');
    }
  }

  Future<bool> needsSeed(MediaSource source) async =>
      source.kind.isEmbyCompatible &&
      source.lastScan == null &&
      (await sources.database.customSelect('''$_scope
        SELECT 1 FROM scope WHERE parent_id IS NULL LIMIT 1
      ''', variables: _variables(source)).getSingleOrNull()) ==
          null;
}

List<HomeVideo> _recommendationCandidates(
  List<Map<String, dynamic>> rows,
  MediaSource source,
) {
  final result = <HomeVideo>[];
  for (final row in rows) {
    final video = _recommendationVideo(row, source);
    if (video.item.displayType != 'music') result.add(video);
  }
  return result;
}

HomeVideo _recommendationVideo(Map<String, dynamic> row, MediaSource source) {
  final item = SourceRepository.decodeIndexedRow(row);
  DateTime? date(String key) => row[key] == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(row[key] as int, isUtc: true);
  return HomeVideo(
    source: source,
    favorite: row['favorite'] == 1,
    metadataRating: (row['metadata_rating'] as num?)?.toDouble(),
    entry: VideoLibraryEntry(
      item: item,
      reportedProgress: (row['reported_progress'] as num?)?.toDouble(),
      record: PlaybackRecord(
        identity: item.identity,
        position: Duration(milliseconds: row['position_ms'] as int),
        duration: Duration(milliseconds: row['duration_ms'] as int),
        watched: row['watched'] == 1,
        lastPlayedAt: date('last_played_at'),
      ),
      createdAt: date('created_at')!,
      watchlist: row['watchlist'] == 1,
      userRating: (row['user_rating'] as num?)?.toDouble(),
    ),
  );
}

HomeStats _stats(List<Map<String, dynamic>> rows) {
  var movies = 0, series = 0, episodes = 0, unwatched = 0;
  for (final row in rows) {
    final count = row['count'] as int;
    if (row['child'] == 1) {
      episodes += count;
      continue;
    }
    final type = RemoteLibraryClassificationPolicy.inferredMediaType(
      type: row['type'] as String,
      libraryName: row['library_name'] as String?,
      collectionType: row['collection_type'] as String?,
      genres: (jsonDecode(row['genres'] as String? ?? '[]') as List)
          .cast<String>(),
    );
    if (type == 'music') continue;
    if (type == 'movie') {
      movies += count;
    } else {
      series += count;
    }
    if (row['finished'] != 1) unwatched += count;
  }
  return HomeStats(
    movies: movies,
    series: series,
    episodes: episodes,
    unwatched: unwatched,
  );
}

List<_SearchDocument> _buildSearchIndex(
  List<Map<String, dynamic>> rows,
  MediaSource source,
) {
  List<String?> terms(IndexedMedia item) => [
    item.title,
    item.originalTitle,
    item.overview,
    item.year?.toString(),
    item.remote?.artist,
    item.remote?.album,
    item.remote?.externalId,
    if (source.kind.isEmbyCompatible) source.kind.label,
    ...?item.remote?.genres,
    item.remote?.videoCodec,
    item.remote?.audioCodec,
    item.remote?.resolution,
  ];
  final decoded = rows.map(SourceRepository.decodeIndexedRow).toList();
  final children = <String, List<String?>>{};
  for (final child in decoded) {
    if (child.parentId != null && child.type == 'episode') {
      (children[child.parentId!] ??= []).addAll([
        ...terms(child),
        child.episodeLabel,
        if (child.seasonNumber != null) '第 ${child.seasonNumber} 季',
        if (child.episodeNumber != null) '第 ${child.episodeNumber} 集',
      ]);
    }
  }
  final results = <_SearchDocument>[];
  for (var n = 0; n < rows.length; n++) {
    final item = decoded[n];
    if (item.type == 'episode' || item.displayType == 'music') continue;
    final fields = [...terms(item), ...?children[item.identity.localId]];
    final raw = rows[n]['details'] as String?;
    if (raw != null) {
      final extra = EmbyDetail.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      fields.addAll([
        extra.overview,
        extra.status,
        extra.contentRating,
        extra.firstAirDate,
        extra.endDate,
        extra.originalLanguage,
        extra.tmdbId,
        extra.imdbId,
        if (extra.tmdbId != null) 'tmdb',
        if (extra.imdbId != null) 'imdb',
        ...extra.genres,
        ...extra.countries,
        ...extra.companies,
        ...extra.networks,
        for (final p in extra.people) ...[p.name, p.role, p.department],
        extra.technical.videoCodec,
        extra.technical.audioCodec,
        extra.technical.resolution,
      ]);
    }
    results.add((
      video: _recommendationVideo(rows[n], source),
      fields: List.unmodifiable(fields),
    ));
  }
  return List.unmodifiable(results);
}

typedef _SearchDocument = ({HomeVideo video, List<String?> fields});

class _CachedSearchIndex {
  _CachedSearchIndex(this.scope, this.revision, this.documents, this.useWorker)
    : characters = documents.fold(
        0,
        (n, document) =>
            n + document.fields.fold(0, (n, field) => n + (field?.length ?? 0)),
      );
  final String scope;
  final (int, int) revision;
  final List<_SearchDocument> documents;
  final bool useWorker;
  final int characters;
}

// Factories keep repository, cancellation tokens and cache maps out of workers.
List<_SearchDocument> Function() _indexWork(
  List<Map<String, dynamic>> rows,
  MediaSource source,
) =>
    () => _buildSearchIndex(rows, source);
List<HomeVideo> Function() _filterWork(
  List<_SearchDocument> documents,
  String query,
) =>
    () => _filterSearchIndex(documents, query);
List<HomeVideo> _filterSearchIndex(
  List<_SearchDocument> documents,
  String query,
) => List.unmodifiable(
  documents
      .where((doc) => LibrarySearchMatcher.matches(query, doc.fields))
      .map((doc) => doc.video),
);
