import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../domain/media_source.dart';
import '../../../storage/library_database.dart';
import '../../../storage/preference_store.dart';
import '../domain/playback_record.dart';

class PlaybackRepository {
  PlaybackRepository(this.database);
  final LibraryDatabase database;

  // A zero clock imported from Emby is not an explicit local reset. Keep this
  // provenance separate from the history epoch, which must survive re-syncs to
  // reject checkpoints from players opened before a clear operation.
  static const localTracePrefix = 'playback.trace.local.';
  static String localTraceKey(MediaIdentity id) =>
      '$localTracePrefix${jsonEncode([id.sourceId, id.localId])}';

  Future<void> _markLocalTrace(MediaIdentity id) => database.customStatement(
    '''INSERT INTO player_preferences(key,value)
       SELECT ?, 'true' WHERE EXISTS
         (SELECT 1 FROM playback_states WHERE source_id=? AND local_id=?)
       ON CONFLICT(key) DO UPDATE SET value=excluded.value''',
    [localTraceKey(id), id.sourceId, id.localId],
  );

  Future<PlaybackRecord> read(MediaIdentity identity) async {
    final row = await database
        .customSelect(
          'SELECT * FROM playback_states WHERE source_id = ? AND local_id = ?',
          variables: [Variable(identity.sourceId), Variable(identity.localId)],
        )
        .getSingleOrNull();
    return _record(identity, row);
  }

  Future<Map<MediaIdentity, PlaybackRecord>> readMany(
    Iterable<MediaIdentity> identities, {
    Map<MediaIdentity, PlaybackRecord> fallbacks = const {},
  }) async {
    final ids = identities.toSet().toList();
    final result = {
      for (final id in ids) id: fallbacks[id] ?? PlaybackRecord(identity: id),
    };
    for (var start = 0; start < ids.length; start += 200) {
      final batch = ids.skip(start).take(200).toList();
      final rows = await database
          .customSelect(
            'SELECT * FROM playback_states WHERE (source_id, local_id) IN '
            '(${List.filled(batch.length, '(?, ?)').join(', ')})',
            variables: [
              for (final id in batch) ...[
                Variable(id.sourceId),
                Variable(id.localId),
              ],
            ],
          )
          .get();
      for (final row in rows) {
        final id = (
          sourceId: row.read<String>('source_id'),
          localId: row.read<String>('local_id'),
        );
        result[id] = _record(id, row);
      }
    }
    return result;
  }

  PlaybackRecord _record(MediaIdentity identity, QueryRow? row) =>
      PlaybackRecord(
        identity: identity,
        position: Duration(milliseconds: row?.read<int>('position_ms') ?? 0),
        duration: Duration(milliseconds: row?.read<int>('duration_ms') ?? 0),
        watched: row?.read<int>('watched') == 1,
        lastPlayedAt: row == null || row.read<int>('last_played_at') == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('last_played_at'),
                isUtc: true,
              ),
      );

  /// Original markWatched keeps the resume position when marking watched,
  /// and clears position/date when marking unwatched. No fake playback date.
  Future<void> markWatched(Iterable<MediaIdentity> identities, bool watched) =>
      database.transaction(() async {
        for (final id in identities.toSet()) {
          await database.customStatement(
            '''
        INSERT INTO playback_states(source_id, local_id, position_ms, duration_ms, watched, last_played_at)
        SELECT source_id, local_id, 0, 0, ?, 0 FROM media
        WHERE source_id = ? AND local_id = ?
        ON CONFLICT(source_id, local_id) DO UPDATE SET watched = excluded.watched,
          position_ms = CASE WHEN ? THEN playback_states.position_ms ELSE 0 END,
          last_played_at = CASE WHEN ? THEN playback_states.last_played_at ELSE 0 END
      ''',
            [
              watched ? 1 : 0,
              id.sourceId,
              id.localId,
              watched ? 1 : 0,
              watched ? 1 : 0,
            ],
          );
          await _markLocalTrace(id);
        }
      });

  String _epochKey(MediaIdentity id) =>
      'playback.history.epoch.${jsonEncode([id.sourceId, id.localId])}';

  Future<String> historyEpoch(MediaIdentity id) async =>
      await database.preferenceValue(_epochKey(id)) ?? '';

  /// A delayed checkpoint from an already open player cannot restore a trace
  /// cleared by a different window. Keep this marker in the existing prefs store.
  Future<void> clearHistory(Iterable<MediaIdentity> identities) =>
      database.transaction(() async {
        final ids = identities.toSet();
        for (final id in ids) {
          final epoch = (int.tryParse(await historyEpoch(id)) ?? 0) + 1;
          await database.writePreference(_epochKey(id), '$epoch');
        }
        await markWatched(ids, false);
      });
  Future<void> save(
    MediaIdentity identity, {
    required Duration position,
    required Duration duration,
    DateTime? playedAt,
    String? historyEpoch,
    bool autoMarkWatched = true,
    double watchedThreshold = .9,
  }) async {
    // Unknown clocks must not erase a previously saved resume point.
    if (duration <= Duration.zero || position < Duration.zero) return;
    final progress = position.inMilliseconds / duration.inMilliseconds;
    await database.transaction(() async {
      if (historyEpoch != null &&
          historyEpoch != await this.historyEpoch(identity)) {
        return;
      }
      final updatedAt =
          (playedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
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
          autoMarkWatched &&
                  progress >=
                      (watchedThreshold.isFinite
                          ? watchedThreshold.clamp(0, 1)
                          : .9)
              ? 1
              : 0,
          updatedAt,
          identity.sourceId,
          identity.localId,
        ],
      );
      await database.customStatement(
        '''INSERT INTO media_activity(source_id, local_id, updated_at)
         SELECT source_id, local_id, ? FROM media
         WHERE source_id = ? AND local_id = ? AND is_series = 0
         ON CONFLICT(source_id, local_id) DO UPDATE SET updated_at = excluded.updated_at''',
        [updatedAt, identity.sourceId, identity.localId],
      );
      await _markLocalTrace(identity);
    });
  }
}
