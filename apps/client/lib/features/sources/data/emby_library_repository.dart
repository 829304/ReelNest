import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_client.dart';
import '../../../api/emby/emby_detail.dart';
import '../../../domain/media_source.dart';
import '../../playback/domain/playback_record.dart';
import '../domain/emby_library.dart';
import 'source_repository.dart';

class EmbyVideoSnapshot {
  const EmbyVideoSnapshot({
    required this.source,
    required this.libraries,
    required this.entries,
  });
  final MediaSource source;
  final List<EmbyLibrary> libraries;
  final List<VideoLibraryEntry> entries;
  List<VideoLibraryEntry> scope(EmbyVideoDestination destination) =>
      entries.where((e) {
        if (e.item.identity.sourceId != destination.sourceId ||
            e.item.parentId != null ||
            e.item.type == 'music') {
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
      }).toList();
}

class EmbyLibraryRepository {
  const EmbyLibraryRepository(this.sources);
  final SourceRepository sources;
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

  Future<EmbyVideoSnapshot> snapshot(
    String sourceId,
  ) => sources.database.transaction(() async {
    final source = await sources.source(sourceId);
    if (source.kind != MediaSourceKind.emby) {
      throw const SourceFailure('此来源不是 Emby。');
    }
    final items = await sources.indexedSource(sourceId);
    final rows = await sources.database
        .customSelect(
          '''
      SELECT m.local_id, p.watchlist, p.user_rating, p.created_at,
        s.position_ms, s.duration_ms, s.watched, s.last_played_at, d.value AS details
      FROM media m
      LEFT JOIN media_library_preferences p USING(source_id, local_id)
      LEFT JOIN playback_states s USING(source_id, local_id)
      LEFT JOIN remote_media_details d USING(source_id, local_id)
      WHERE m.source_id = ?
    ''',
          variables: [Variable(sourceId)],
        )
        .get();
    final byId = {for (final r in rows) r.read<String>('local_id'): r};
    final children = <String, List<IndexedMedia>>{};
    for (final item in items) {
      if (item.parentId != null) (children[item.parentId!] ??= []).add(item);
    }
    List<String?> terms(IndexedMedia item) => [
      item.title,
      item.originalTitle,
      item.overview,
      item.year?.toString(),
      item.remote?.externalId,
      'Emby',
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
          record: PlaybackRecord(
            identity: item.identity,
            position: Duration(
              milliseconds:
                  row.readNullable<int>('position_ms') ??
                  remote?.positionMs ??
                  0,
            ),
            duration: Duration(
              milliseconds:
                  row.readNullable<int>('duration_ms') ??
                  remote?.durationMs ??
                  0,
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
          userRating: row.readNullable<double>('user_rating') ?? remote?.rating,
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
    final views = await sources.database
        .customSelect(
          'SELECT * FROM remote_library_views WHERE source_id = ?',
          variables: [Variable(sourceId)],
        )
        .get();
    final selected = source.options.selectedEmbyLibraryIDs;
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
                  v.collectionType?.toLowerCase() != 'music',
            )
            .toList()
          ..sort((a, b) => libraryTitleCompare(a.name, b.name));
    return EmbyVideoSnapshot(
      source: source,
      libraries: libraries,
      entries: entries,
    );
  });
  Future<void> setWatchlist(MediaIdentity id, bool value) async {
    final item = await sources.media(id);
    if (item.remote == null || item.type == 'music') {
      throw const SourceFailure('此媒体不支持想看操作。');
    }
    await sources.database.customStatement(
      '''
      INSERT INTO media_library_preferences(source_id, local_id, watchlist, user_rating, created_at)
      VALUES (?, ?, ?, ?, ?) ON CONFLICT(source_id, local_id) DO UPDATE SET watchlist = excluded.watchlist
    ''',
      [
        id.sourceId,
        id.localId,
        value ? 1 : 0,
        item.remote?.rating,
        item.modified.millisecondsSinceEpoch,
      ],
    );
    sources.traceChanged();
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
