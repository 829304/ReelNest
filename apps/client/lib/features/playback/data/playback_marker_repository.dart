import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../storage/library_database.dart';
import '../domain/playback_marker.dart';
import '../domain/intro_outro_candidates.dart';

class PlaybackMarkerRepository {
  PlaybackMarkerRepository(this.database);
  final LibraryDatabase database;

  Future<List<PlaybackMarker>> read(
    MediaIdentity identity, {
    bool includingRejected = false,
  }) async =>
      (await database
              .customSelect(
                'SELECT * FROM playback_markers WHERE source_id=? AND local_id=? '
                "${includingRejected ? '' : "AND review_status!='rejected' "}"
                'ORDER BY start_us,created_at,id',
                variables: [
                  Variable(identity.sourceId),
                  Variable(identity.localId),
                ],
              )
              .get())
          .map(_map)
          .toList();

  /// Re-read and insert in the same transaction. A concurrent review cannot be
  /// overwritten with pending status; rejected IDs also remain in this input.
  Future<int> generateIntroOutroCandidates(
    MediaIdentity identity, {
    required Duration duration,
    ScanCancellation? cancellation,
  }) => database.transaction(() async {
    cancellation?.check();
    final existing = await read(identity, includingRejected: true);
    cancellation?.check();
    final candidates = IntroOutroCandidates.generate(
      identity: identity,
      duration: duration,
      existing: existing,
    );
    for (final marker in candidates) {
      cancellation?.check();
      await save(marker);
    }
    cancellation?.check();
    return candidates.length;
  });

  /// Only pending automatic candidates are reviewable. Repeated/late clicks
  /// from another window cannot reverse a completed review or edit manual data.
  Future<void> reviewAutomatic(
    MediaIdentity identity,
    String id, {
    required bool accepted,
  }) => database.customStatement(
    "UPDATE playback_markers SET review_status=?,updated_at=? "
    "WHERE source_id=? AND local_id=? AND id=? AND origin='automatic' "
    "AND review_status='pending'",
    [
      accepted ? 'accepted' : 'rejected',
      DateTime.now().toUtc().millisecondsSinceEpoch,
      identity.sourceId,
      identity.localId,
      id,
    ],
  );

  Future<void> save(PlaybackMarker marker) => database.customStatement(
    '''
    INSERT INTO playback_markers(source_id,local_id,id,kind,title,start_us,end_us,
      origin,review_status,detector_identifier,confidence,created_at,updated_at)
    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(source_id,local_id,id) DO UPDATE SET
      kind=excluded.kind,title=excluded.title,start_us=excluded.start_us,end_us=excluded.end_us,
      origin=excluded.origin,review_status=excluded.review_status,
      detector_identifier=excluded.detector_identifier,confidence=excluded.confidence,
      updated_at=excluded.updated_at
  ''',
    [
      marker.identity.sourceId,
      marker.identity.localId,
      marker.id,
      marker.kind.name,
      marker.title,
      marker.start.inMicroseconds,
      marker.end?.inMicroseconds,
      marker.origin.name,
      marker.review.name,
      marker.detectorIdentifier,
      marker.confidence,
      marker.createdAt.millisecondsSinceEpoch,
      DateTime.now().toUtc().millisecondsSinceEpoch,
    ],
  );

  Future<void> deleteManual(MediaIdentity identity, String id) =>
      database.customStatement(
        "DELETE FROM playback_markers WHERE source_id=? AND local_id=? AND id=? AND origin='manual'",
        [identity.sourceId, identity.localId, id],
      );

  /// PlayerView.setMarkerBoundary: edit one manual range without replacing
  /// embedded/automatic markers. Read and save together for concurrent windows.
  Future<void> setManualBoundary(
    MediaIdentity identity,
    PlaybackMarkerKind kind, {
    required bool isStart,
    required Duration at,
  }) => database.transaction(() async {
    if (kind != PlaybackMarkerKind.intro &&
        kind != PlaybackMarkerKind.credits) {
      throw ArgumentError('Not a range marker');
    }
    final previous = (await read(identity))
        .where((m) => m.kind == kind && m.origin == PlaybackMarkerOrigin.manual)
        .firstOrNull;
    final time = at < Duration.zero ? Duration.zero : at;
    var start = previous?.start ?? time;
    var end = previous?.end;
    if (isStart) {
      start = time;
      if (end != null && end <= start) end = null;
    } else {
      if (start >= time) {
        start = time - const Duration(seconds: 90);
        if (start < Duration.zero) start = Duration.zero;
      }
      final minimumEnd = start + const Duration(milliseconds: 100);
      end = time > minimumEnd ? time : minimumEnd;
    }
    await save(
      PlaybackMarker(
        id:
            previous?.id ??
            'manual-${identity.sourceId}-${identity.localId}-${kind.name}',
        identity: identity,
        kind: kind,
        title: kind.title,
        start: start,
        end: end,
        createdAt: previous?.createdAt,
      ),
    );
  });

  /// Replacing embedded chapters never removes user chapters or bookmarks.
  Future<void> replaceEmbedded(
    MediaIdentity identity,
    List<PlaybackMarker> chapters,
  ) => database.transaction(() async {
    if (chapters.any(
      (m) =>
          m.identity != identity ||
          m.kind != PlaybackMarkerKind.chapter ||
          m.origin != PlaybackMarkerOrigin.embedded,
    )) {
      throw ArgumentError('Invalid embedded chapters');
    }
    final existing = (await read(identity))
        .where(
          (m) =>
              m.kind == PlaybackMarkerKind.chapter &&
              m.origin == PlaybackMarkerOrigin.embedded,
        )
        .toList();
    if (existing.length == chapters.length &&
        List.generate(
          existing.length,
          (i) =>
              existing[i].id == chapters[i].id &&
              existing[i].title == chapters[i].title &&
              (existing[i].start - chapters[i].start).inMicroseconds.abs() <
                  1000 &&
              (existing[i].end == chapters[i].end ||
                  existing[i].end != null &&
                      chapters[i].end != null &&
                      (existing[i].end! - chapters[i].end!).inMicroseconds
                              .abs() <
                          1000),
        ).every((same) => same)) {
      return;
    }
    await database.customStatement(
      "DELETE FROM playback_markers WHERE source_id=? AND local_id=? AND kind='chapter' AND origin='embedded'",
      [identity.sourceId, identity.localId],
    );
    for (final chapter in chapters) {
      await save(chapter);
    }
  });

  PlaybackMarker _map(QueryRow row) => PlaybackMarker(
    id: row.read<String>('id'),
    identity: (
      sourceId: row.read<String>('source_id'),
      localId: row.read<String>('local_id'),
    ),
    kind: PlaybackMarkerKind.values.byName(row.read<String>('kind')),
    title: row.read<String>('title'),
    start: Duration(microseconds: row.read<int>('start_us')),
    end: row.readNullable<int>('end_us') == null
        ? null
        : Duration(microseconds: row.read<int>('end_us')),
    origin: PlaybackMarkerOrigin.values.byName(row.read<String>('origin')),
    review: PlaybackMarkerReview.values.byName(
      row.read<String>('review_status'),
    ),
    detectorIdentifier: row.readNullable<String>('detector_identifier'),
    confidence: row.readNullable<double>('confidence'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at'),
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('updated_at'),
      isUtc: true,
    ),
  );
}
