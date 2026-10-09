import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../storage/library_database.dart';
import '../domain/playback_record.dart';

class PlaybackRepository {
  PlaybackRepository(this.database);
  final LibraryDatabase database;

  Future<PlaybackRecord> read(MediaIdentity identity) async {
    final row = await database
        .customSelect(
          'SELECT * FROM playback_states WHERE source_id = ? AND local_id = ?',
          variables: [Variable(identity.sourceId), Variable(identity.localId)],
        )
        .getSingleOrNull();
    return PlaybackRecord(
      identity: identity,
      position: Duration(milliseconds: row?.read<int>('position_ms') ?? 0),
      duration: Duration(milliseconds: row?.read<int>('duration_ms') ?? 0),
      watched: row?.read<int>('watched') == 1,
      lastPlayedAt: row == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('last_played_at'),
              isUtc: true,
            ),
    );
  }

  Future<void> save(
    MediaIdentity identity, {
    required Duration position,
    required Duration duration,
    DateTime? playedAt,
  }) async {
    // Unknown clocks must not erase a previously saved resume point.
    if (duration <= Duration.zero || position < Duration.zero) return;
    final progress = position.inMilliseconds / duration.inMilliseconds;
    await database.customStatement(
      '''
      INSERT INTO playback_states(source_id, local_id, position_ms, duration_ms, watched, last_played_at)
      SELECT source_id, local_id, ?, ?, ?, ? FROM media
        WHERE source_id = ? AND local_id = ? AND is_series = 0
      ON CONFLICT(source_id, local_id) DO UPDATE SET
        position_ms = excluded.position_ms, duration_ms = excluded.duration_ms,
        watched = MAX(playback_states.watched, excluded.watched),
        last_played_at = excluded.last_played_at
    ''',
      [
        position.inMilliseconds,
        duration.inMilliseconds,
        progress >= .9 ? 1 : 0,
        (playedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
        identity.sourceId,
        identity.localId,
      ],
    );
  }
}
