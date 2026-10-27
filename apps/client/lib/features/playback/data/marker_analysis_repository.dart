import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/runtime_status.dart';
import '../../sources/data/source_repository.dart';
import 'playback_marker_repository.dart';

class MarkerAnalysisTarget {
  MarkerAnalysisTarget(
    this.identity,
    this.duration,
    this.revision,
    this.private,
  );
  final MediaIdentity identity;
  final Duration duration;
  final Object revision;
  final bool private;
}

class MarkerAnalysisPlan {
  MarkerAnalysisPlan({
    required this.root,
    required this.title,
    required this.hidesDetail,
    required this.sourceKey,
    required this.targets,
  });
  final MediaIdentity root;
  final String title, sourceKey;
  final bool hidesDetail;
  final List<MarkerAnalysisTarget> targets;
}

/// AppState.playbackMarkerAnalysisItems: analyze indexed direct children, or the
/// item itself, with a known duration > 60s. Never probe media or fetch episodes.
class MarkerAnalysisRepository {
  MarkerAnalysisRepository(this.sources, {PlaybackMarkerRepository? markers})
    : markers = markers ?? PlaybackMarkerRepository(sources.database);
  final SourceRepository sources;
  final PlaybackMarkerRepository markers;

  Future<bool> canAnalyze(MediaIdentity root) async {
    try {
      return (await _plan(root, limit: 1)).targets.isNotEmpty;
    } on SourceFailure {
      return false;
    }
  }

  Future<MarkerAnalysisPlan> plan(MediaIdentity root) => _plan(root);

  Future<MarkerAnalysisPlan> _plan(
    MediaIdentity root, {
    int? limit,
  }) => sources.database.transaction(() async {
    final source = await sources.source(root.sourceId, includeCounts: false);
    final item = await sources.media(root);
    if ((!source.kind.isFileSource && !source.kind.isRemoteVideoSource) ||
        {
          SourceMediaType.music,
          SourceMediaType.photo,
        }.contains(source.mediaType)) {
      throw const SourceFailure('这个条目没有可分析的视频。');
    }
    final children = await sources.database
        .customSelect(
          'SELECT 1 FROM media WHERE source_id=? AND parent_id=? LIMIT 1',
          variables: [Variable(root.sourceId), Variable(root.localId)],
        )
        .getSingleOrNull();
    final selected = source.options.selectedEmbyLibraryIDs;
    final scoped = source.kind.isRemoteVideoSource && selected.isNotEmpty;
    final rows = await sources.database
        .customSelect(
          '$_projection WHERE m.source_id=? AND m.${children == null ? 'local_id' : 'parent_id'}=? '
          "AND m.is_series=0 AND m.type NOT IN ('music','photo','album','albumvideo') "
          'AND $_duration > 60000 '
          '${scoped ? "AND json_extract(r.value, '\$.libraryId') IN (SELECT value FROM json_each(?)) " : ''}'
          'ORDER BY m.season_number, m.episode_number, m.title COLLATE NOCASE, m.local_id '
          '${limit == null ? '' : 'LIMIT $limit'}',
          variables: [
            Variable(root.sourceId),
            Variable(root.localId),
            if (scoped) Variable(jsonEncode(selected)),
          ],
        )
        .get();
    final targets = rows.map(_target).toList(growable: false);
    return MarkerAnalysisPlan(
      root: root,
      title: '片头片尾检测 · ${item.title}',
      hidesDetail:
          source.mediaType == SourceMediaType.privateCollection ||
          {'private', 'privateCollection'}.contains(item.type) ||
          targets.any((t) => t.private),
      sourceKey: runtimeSourceKey(source),
      targets: List.unmodifiable(targets),
    );
  });

  static const _remoteDuration = "json_extract(r.value, '\$.durationMs')";
  static const _duration =
      'CASE WHEN $_remoteDuration > 0 THEN $_remoteDuration '
      'ELSE COALESCE(p.duration_ms,0) END';
  static const _projection =
      'SELECT m.source_id, m.local_id, m.type, m.bytes, '
      "m.modified, m.parent_id, m.is_series, json_extract(r.value, '\$.mediaSourceId') AS media_source_id, "
      "json_extract(r.value, '\$.libraryId') AS library_id, "
      '$_duration AS duration_ms FROM media m '
      'LEFT JOIN remote_media_metadata r ON r.source_id=m.source_id AND r.local_id=m.local_id '
      'LEFT JOIN playback_states p ON p.source_id=m.source_id AND p.local_id=m.local_id';

  MarkerAnalysisTarget _target(QueryRow row) {
    final duration = Duration(milliseconds: row.read<int>('duration_ms'));
    return MarkerAnalysisTarget(
      (
        sourceId: row.read<String>('source_id'),
        localId: row.read<String>('local_id'),
      ),
      duration,
      (
        row.read<String>('type'),
        row.read<int>('bytes'),
        row.read<int>('modified'),
        row.readNullable<String>('parent_id'),
        row.read<int>('is_series'),
        row.readNullable<String>('media_source_id'),
        row.readNullable<String>('library_id'),
        duration,
      ),
      {'private', 'privateCollection'}.contains(row.read<String>('type')),
    );
  }

  /// Validate scope and the media revision in the same transaction as insertion.
  /// Removal, remount/account changes or replaced content cannot commit stale
  /// candidates using a previously captured duration/hierarchy snapshot.
  Future<int> analyze(
    MarkerAnalysisPlan plan,
    MarkerAnalysisTarget target,
    ScanCancellation cancellation,
  ) => sources.database.transaction(() async {
    cancellation.check();
    final current = await sources.source(
      plan.root.sourceId,
      includeCounts: false,
    );
    if (runtimeSourceKey(current) != plan.sourceKey) {
      throw const SourceFailure('媒体源配置已变化，请重新检测。');
    }
    final row = await sources.database
        .customSelect(
          '$_projection WHERE m.source_id=? AND m.local_id=?',
          variables: [
            Variable(target.identity.sourceId),
            Variable(target.identity.localId),
          ],
        )
        .getSingleOrNull();
    if (row == null || _target(row).revision != target.revision) {
      throw const SourceFailure('待分析媒体已变化或移除，请重新检测。');
    }
    cancellation.check();
    final count = await markers.generateIntroOutroCandidates(
      target.identity,
      duration: target.duration,
      cancellation: cancellation,
    );
    cancellation.check();
    return count;
  });
}
