import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../sources/data/source_repository.dart';

typedef VideoPreferences = ({bool watchlist, bool favorite, double? rating});

/// Public video state uses existing preference storage for file sources too.
class VideoPreferencesRepository {
  const VideoPreferencesRepository(this.sources);
  final SourceRepository sources;
  static String favoriteKey(MediaIdentity id) =>
      'library.favorite.${jsonEncode([id.sourceId, id.localId])}';
  Future<VideoPreferences> read(MediaIdentity id) async {
    final row = await sources.database
        .customSelect(
          '''
      SELECT p.watchlist, p.user_rating,
        CASE WHEN r.value IS NOT NULL THEN json_extract(r.value, '\$.favorite')
          ELSE f.value = 'true' END AS favorite
      FROM media m
      LEFT JOIN media_library_preferences p USING(source_id,local_id)
      LEFT JOIN remote_media_metadata r USING(source_id,local_id)
      LEFT JOIN player_preferences f ON f.key = ?
      WHERE m.source_id = ? AND m.local_id = ?
    ''',
          variables: [
            Variable(favoriteKey(id)),
            Variable(id.sourceId),
            Variable(id.localId),
          ],
        )
        .getSingleOrNull();
    return (
      watchlist: row?.readNullable<int>('watchlist') == 1,
      favorite: row?.readNullable<int>('favorite') == 1,
      rating: row?.readNullable<double>('user_rating'),
    );
  }

  Future<void> setWatchlist(MediaIdentity id, bool value) async {
    await sources.database.transaction(() async {
      final item = await sources.media(id);
      await sources.database.customStatement(
        '''
        INSERT INTO media_library_preferences(source_id,local_id,watchlist,created_at)
        VALUES (?,?,?,?) ON CONFLICT(source_id,local_id) DO UPDATE SET watchlist=excluded.watchlist
      ''',
        [
          id.sourceId,
          id.localId,
          value ? 1 : 0,
          item.modified.millisecondsSinceEpoch,
        ],
      );
    });
    sources.traceChanged();
  }

  Future<void> setLocalFavorite(MediaIdentity id, bool value) async {
    await sources.database.transaction(() async {
      if (!(await sources.source(
        id.sourceId,
        includeCounts: false,
      )).kind.isFileSource) {
        throw const SourceFailure('远程收藏必须通过对应服务器保存。');
      }
      await sources.media(id);
      await sources.database.customStatement(
        '''INSERT INTO player_preferences(key,value) VALUES (?,?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value''',
        [favoriteKey(id), '$value'],
      );
    });
    sources.traceChanged();
  }
}
