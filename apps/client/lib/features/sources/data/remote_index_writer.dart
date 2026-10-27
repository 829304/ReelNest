import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../domain/remote_media_policy.dart';
import '../../../domain/source_options.dart';
import '../../../domain/source_scan.dart';
import '../../../storage/library_database.dart';
import '../../playback/data/playback_repository.dart';

/// Queue prepared statements per chunk: one isolate round trip, not one per SQL.
/// The caller owns the transaction, so cancellation still rolls back the snapshot.
class RemoteIndexWriter {
  const RemoteIndexWriter(this.database);
  final LibraryDatabase database;

  Future<void> write(
    String sourceId,
    List<IndexedMedia> items, {
    required RemoteTraceSyncMode traceMode,
    required ScanCancellation cancellation,
    String? runId,
    DateTime? importedAt,
    void Function(SourceScanProgress)? onProgress,
  }) async {
    final favorites = <String, bool>{};
    final plex = await database
        .customSelect(
          "SELECT id FROM sources WHERE id = ? AND kind = 'plex'",
          variables: [Variable(sourceId)],
        )
        .getSingleOrNull();
    if (traceMode == RemoteTraceSyncMode.disabled || plex != null) {
      final rows = await database
          .customSelect(
            '''SELECT r.local_id, json_type(r.value, '\$.favorite') = 'true' AS favorite
               FROM json_each(?) ids CROSS JOIN remote_media_metadata r
               WHERE r.source_id = ? AND r.local_id = ids.value''',
            variables: [
              Variable(
                jsonEncode(
                  items.map((i) => i.identity.localId).toSet().toList(),
                ),
              ),
              Variable(sourceId),
            ],
          )
          .get();
      for (final row in rows) {
        favorites[row.read<String>('local_id')] =
            row.readNullable<int>('favorite') == 1;
      }
    }
    final now = (importedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    void progress(int count) => onProgress?.call(
      SourceScanProgress(
        phase: SourceScanPhase.persisting,
        totalFiles: items.length,
        processedFiles: count,
        importedItems: count,
      ),
    );
    progress(0);
    for (var start = 0; start < items.length; start += 250) {
      cancellation.check();
      final end = (start + 250).clamp(0, items.length);
      await database.batch((batch) {
        for (var i = start; i < end; i++) {
          final item = items[i], id = item.identity.localId;
          final kind = item.isSeries ? 'show' : item.type;
          batch.customStatement(
            '''
            DELETE FROM playback_states WHERE source_id = ? AND local_id = ?
              AND EXISTS (SELECT 1 FROM media WHERE source_id = ? AND local_id = ?
                AND identity_kind != ?)
          ''',
            [sourceId, id, sourceId, id, kind],
          );
          batch.customStatement(
            '''
            INSERT INTO media(source_id, local_id, title, type, bytes, modified, missing,
              year, season_number, episode_number, series_directory, is_series, parent_id,
              original_title, overview, poster_path, backdrop_path, identity_kind)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_id, local_id) DO UPDATE SET
              title = excluded.title, type = excluded.type, bytes = excluded.bytes,
              modified = excluded.modified, missing = 0, year = excluded.year,
              season_number = excluded.season_number, episode_number = excluded.episode_number,
              series_directory = excluded.series_directory, is_series = excluded.is_series,
              parent_id = excluded.parent_id, original_title = excluded.original_title,
              overview = excluded.overview, poster_path = excluded.poster_path,
              backdrop_path = excluded.backdrop_path, identity_kind = excluded.identity_kind
          ''',
            [
              sourceId,
              id,
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
              kind,
            ],
          );
          if (runId != null) {
            batch.customStatement(
              'INSERT OR IGNORE INTO scan_stage(run_id, local_id) VALUES (?, ?)',
              [runId, id],
            );
          }
          batch.customStatement(
            '''
            INSERT OR IGNORE INTO media_library_preferences(source_id, local_id, user_rating, created_at)
              VALUES (?, ?, ?, ?)
          ''',
            [
              sourceId,
              id,
              RemoteRatingPolicy.initialUserRating(item.remote),
              now,
            ],
          );
          batch.customStatement(
            '''
            INSERT INTO media_activity(source_id, local_id, updated_at) VALUES (?, ?, ?)
              ON CONFLICT(source_id, local_id) DO UPDATE SET updated_at = excluded.updated_at
          ''',
            [sourceId, id, now],
          );
          final trace = item.remote!;
          final metadata = trace.toJson();
          if (favorites.containsKey(id)) metadata['favorite'] = favorites[id];
          batch.customStatement(
            '''
            INSERT INTO remote_media_metadata(source_id, local_id, value) VALUES (?, ?, ?)
              ON CONFLICT(source_id, local_id) DO UPDATE SET value = excluded.value
          ''',
            [sourceId, id, jsonEncode(metadata)],
          );
          if (!item.isSeries) {
            batch.customStatement(
              '''
              INSERT INTO playback_states(source_id, local_id, position_ms, duration_ms, watched, last_played_at)
              VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(source_id, local_id) DO UPDATE SET
                position_ms = excluded.position_ms, duration_ms = excluded.duration_ms,
                watched = excluded.watched, last_played_at = excluded.last_played_at
              WHERE ? != 'disabled'
            ''',
              [
                sourceId,
                id,
                trace.positionMs,
                trace.durationMs ?? 0,
                trace.watched ? 1 : 0,
                trace.lastPlayedAt?.millisecondsSinceEpoch ?? 0,
                traceMode.name,
              ],
            );
          }
          // Enabled trace imports replace the local overlay. Do not reset the
          // independent history epoch or allow disabled imports to undo clears.
          if (traceMode != RemoteTraceSyncMode.disabled) {
            batch.customStatement(
              'DELETE FROM player_preferences WHERE key = ?',
              [PlaybackRepository.localTraceKey(item.identity)],
            );
          }
        }
      });
      cancellation.check();
      progress(end);
    }
  }
}
