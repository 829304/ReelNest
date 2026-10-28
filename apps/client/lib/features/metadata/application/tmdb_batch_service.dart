import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/media_source.dart';
import '../../sources/data/source_repository.dart';
import '../data/tmdb_settings_repository.dart';
import '../domain/tmdb_batch_state.dart';
import '../domain/tmdb_models.dart';
import 'tmdb_video_service.dart';
import 'tmdb_video_match_finder.dart';

/// Manual AppState.startTMDBMatchForTVSeries. No timer or media-file writes.
class TmdbBatchService {
  TmdbBatchService({
    required this.sources,
    required this.settings,
    required this.series,
    required this.isScanning,
    this.onFailure,
  });
  final SourceRepository sources;
  final TmdbSettingsRepository settings;
  final TmdbVideoService series;
  final bool Function() isScanning;
  final void Function(String, Object, StackTrace)? onFailure;
  final state = ValueNotifier(const TmdbBatchState());
  ScanCancellation? _token;
  Future<void>? _pending;
  bool _closed = false;

  bool get isRunning => _pending != null;

  Future<void> start() => _start(ScanCancellation(), automatic: false);

  /// Quiet preflight for the timer. A timer must never join and then cancel a
  /// manual task; ownership of this token is retained by the scheduler.
  Future<void> startAutomatic(ScanCancellation cancellation) {
    if (isRunning || isScanning()) return Future.value();
    return _start(cancellation, automatic: true);
  }

  Future<void> _start(ScanCancellation token, {required bool automatic}) {
    if (_closed) return Future.error(const SourceFailure('应用正在关闭。'));
    return _pending ??= _run(
      token,
      automatic: automatic,
    ).whenComplete(() => _pending = null);
  }

  void cancel() => _token?.cancel();
  void _publish(TmdbBatchState value) {
    if (!_closed) state.value = value;
  }

  Future<void> _run(ScanCancellation token, {required bool automatic}) async {
    _token = token;
    var total = 0, processed = 0, matched = 0, low = 0, failed = 0;
    void publish({
      bool running = true,
      bool cancelled = false,
      String? message,
    }) => _publish(
      TmdbBatchState(
        running: running,
        total: total,
        processed: processed,
        matched: matched,
        lowConfidence: low,
        failed: failed,
        cancelled: cancelled,
        message: message,
      ),
    );
    try {
      if (!automatic) publish();
      if (isScanning()) {
        if (automatic) return;
        throw const SourceFailure('媒体库正在扫描，请扫描完成后再匹配。');
      }
      final config = await settings.read();
      final credential = await settings.credential();
      token.check();
      if (credential.isEmpty) {
        if (automatic) return;
        throw const SourceFailure('请先在设置中填写 TMDB API Key 或 Read Access Token。');
      }
      final targets = await _targets(config, token);
      total = targets.length;
      if (total == 0) {
        if (automatic) return;
        publish();
        throw const SourceFailure('无需匹配：所有电视剧 / 动漫都已匹配过 TMDB 信息。');
      }
      token.check();
      // Scans can start while candidate discovery waits for SQLite.
      if (automatic && isScanning()) return;
      publish();
      for (final target in targets) {
        token.check();
        try {
          final revision = sources.sourceContentRevision(target.source.id);
          Future<void> validateConfiguration() async {
            token.check();
            final current = await sources.source(
              target.source.id,
              includeCounts: false,
            );
            final latest = await settings.read();
            if (isScanning() ||
                sources.isScanning(target.source.id) ||
                sources.sourceContentRevision(target.source.id) != revision ||
                !current.kind.isFileSource ||
                !current.options.includeInMetadataFetch ||
                current.location != target.source.location ||
                current.accessIdentity != target.source.accessIdentity ||
                current.updatedAt != target.source.updatedAt ||
                current.lastScan != target.source.lastScan ||
                latest.language != config.language) {
              throw const SourceFailure('来源、索引或匹配设置已改变，已保留现有资料。');
            }
            token.check();
          }

          Future<void> validate() async {
            await validateConfiguration();
            final current = await sources.media(target.item.identity);
            if (_stamp(current) != _stamp(target.item) ||
                _metadataStamp(await _metadataValue(target.item.identity)) !=
                    target.metadata) {
              throw const SourceFailure('影视资料已改变，已保留最新资料。');
            }
            token.check();
          }

          await validate();
          final children = await sources.indexedChildren(target.item.identity);
          final best = await findTmdbVideoMatch(
            client: series.client,
            source: target.source,
            item: target.item,
            children: children,
            kind: TmdbMediaKind.tv,
            settings: config,
            credential: credential,
            cancellation: token,
            onFailure: (error, stack) =>
                onFailure?.call('tmdb_batch_query_failed', error, stack),
          );
          if (best == null ||
              best.confidence < config.matchTolerance.videoThreshold) {
            low++;
          } else {
            await series.apply(
              target.item.identity,
              best.candidate,
              cancellation: token,
              validate: validate,
              validateCommit: validateConfiguration,
            );
            matched++;
          }
        } on ScanCancelled {
          rethrow;
        } catch (error, stack) {
          token.check();
          onFailure?.call('tmdb_batch_item_failed', error, stack);
          failed++;
        }
        processed++;
        publish();
      }
      publish(
        running: false,
        message:
            '已为 $matched/$total 部电视剧 / 动漫匹配 TMDB 信息；低置信跳过 $low 部，失败 $failed 部。',
      );
    } on ScanCancelled {
      if (!automatic || total > 0) {
        publish(running: false, cancelled: true, message: '匹配已取消，已完成的资料保留。');
      }
    } catch (error, stack) {
      // Cancellation wins over an I/O error delivered while preflight waits.
      try {
        token.check();
      } on ScanCancelled {
        if (!automatic || total > 0) {
          publish(running: false, cancelled: true, message: '匹配已取消，已完成的资料保留。');
        }
        return;
      }
      onFailure?.call('tmdb_batch_failed', error, stack);
      if (automatic && total == 0) return;
      publish(
        running: false,
        message: error is SourceFailure ? error.message : 'TMDB 批量匹配失败，请稍后重试。',
      );
      rethrow;
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  Future<String?> _metadataValue(MediaIdentity id) async =>
      (await sources.database
              .customSelect(
                'SELECT value FROM local_series_metadata WHERE source_id=? AND local_id=?',
                variables: [Variable(id.sourceId), Variable(id.localId)],
              )
              .getSingleOrNull())
          ?.read<String>('value');

  Future<List<_Target>> _targets(
    TmdbSettings config,
    ScanCancellation token,
  ) async {
    final result = <_Target>[], bySource = <String, MediaSource>{};
    // Page metadata rows: never enumerate media folders or retain full episode
    // snapshots for the whole library before starting the first match.
    for (var offset = 0; ; offset += 200) {
      final rows = await sources.database
          .customSelect(
            '''SELECT m.source_id,m.local_id,l.value
        FROM media m JOIN sources s ON s.id=m.source_id
        LEFT JOIN local_series_metadata l ON l.source_id=m.source_id AND l.local_id=m.local_id
        WHERE s.kind IN ('localFolder','removableDrive','mountedNas')
          AND m.is_series=1 AND m.parent_id IS NULL AND m.type IN ('tvShow','anime')
        ORDER BY m.source_id,m.local_id LIMIT 200 OFFSET ?''',
            variables: [Variable(offset)],
          )
          .get();
      token.check();
      for (final row in rows) {
        token.check();
        final raw = row.readNullable<String>('value');
        if (!_needsRefresh(raw, config.language)) continue;
        try {
          final sourceID = row.read<String>('source_id');
          final source = bySource[sourceID] ??= await sources.source(
            sourceID,
            includeCounts: false,
          );
          if (!source.options.includeInMetadataFetch) continue;
          final item = await sources.media((
            sourceId: sourceID,
            localId: row.read<String>('local_id'),
          ));
          result.add(_Target(source, item, _metadataStamp(raw)));
        } on SourceFailure {
          // A removed/reclassified source during candidate discovery must not
          // prevent remaining sources from entering the batch.
          token.check();
        }
      }
      if (rows.length < 200) break;
    }
    return result;
  }

  String? _metadataStamp(String? value) =>
      value == null ? null : sha256.convert(utf8.encode(value)).toString();

  bool _needsRefresh(String? raw, String language) {
    if (raw == null) return true;
    try {
      final metadata = TmdbMetadata.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return metadata.candidate.kind != TmdbMediaKind.tv ||
          metadata.candidate.id <= 0 ||
          metadata.candidate.provider != 'TMDB[$language]';
    } catch (_) {
      return true;
    }
  }

  Object _stamp(IndexedMedia m) => (
    m.title,
    m.originalTitle,
    m.year,
    m.overview,
    m.posterPath,
    m.backdropPath,
    m.type,
    m.bytes,
    m.modified,
    m.isSeries,
    m.parentId,
    m.seriesDirectory,
    m.remote,
  );

  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    cancel();
    try {
      await _pending;
    } catch (_) {}
    state.dispose();
  }
}

class _Target {
  const _Target(this.source, this.item, this.metadata);
  final MediaSource source;
  final IndexedMedia item;
  final String? metadata;
}
