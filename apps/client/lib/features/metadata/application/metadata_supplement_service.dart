import 'dart:async';
import 'dart:convert';

import '../../../application/async_tasks.dart';
import '../../../domain/media_source.dart';
import '../../sources/data/source_repository.dart';
import '../data/tmdb_settings_repository.dart';
import '../domain/metadata_supplement_state.dart';
import '../domain/tmdb_models.dart';
import 'tmdb_video_match_finder.dart';
import 'tmdb_video_service.dart';

class MetadataSupplementService {
  MetadataSupplementService({
    required this.sources,
    required this.settings,
    required this.movie,
    required this.series,
    required this.loadCandidates,
    required this.isScanning,
    required this.onState,
    this.onFailure,
  });
  final SourceRepository sources;
  final TmdbSettingsRepository settings;
  final TmdbVideoService movie, series;
  final Future<List<IndexedMedia>> Function() loadCandidates;
  final bool Function() isScanning;
  final void Function(MetadataSupplementState) onState;
  final void Function(Object, StackTrace)? onFailure;
  Future<void>? _pending;
  ScanCancellation? _token;
  bool _closed = false;
  bool get isRunning => _pending != null;
  Future<void> start() {
    if (_closed) return Future.error(const SourceFailure('应用正在关闭。'));
    return _pending ??= _run().whenComplete(() => _pending = null);
  }

  void cancel() => _token?.cancel();
  Future<void> _run() async {
    final token = ScanCancellation();
    _token = token;
    var total = 0,
        processed = 0,
        updated = 0,
        skipped = 0,
        failed = 0,
        warnings = 0;
    void publish({bool running = true, String? message}) {
      if (!_closed) {
        onState(
          MetadataSupplementState(
            running: running,
            total: total,
            processed: processed,
            updated: updated,
            skipped: skipped,
            failed: failed,
            warningCount: warnings,
            message: message,
          ),
        );
      }
    }

    try {
      publish();
      if (isScanning()) throw const SourceFailure('媒体库正在扫描，请扫描完成后再补充。');
      final config = await settings.read(),
          credential = await settings.credential();
      token.check();
      if (credential.isEmpty) {
        throw const SourceFailure('请先在设置中填写 TMDB API Key 或 Read Access Token。');
      }
      final all = await awaitWithCancellation(token, loadCandidates);
      final candidates = <IndexedMedia>[];
      for (final item in all) {
        token.check();
        if (item.parentId != null ||
            item.remote != null ||
            !(item.type == 'movie' && !item.isSeries ||
                item.isSeries &&
                    const {'tvShow', 'anime'}.contains(item.type))) {
          continue;
        }
        try {
          final source = await sources.source(
            item.identity.sourceId,
            includeCounts: false,
          );
          if (source.kind.isFileSource &&
              source.options.includeInMetadataFetch) {
            candidates.add(item);
          }
        } on SourceFailure {
          token.check();
        }
      }
      total = candidates.length;
      publish();
      if (total == 0) throw const SourceFailure('当前参与元数据拉取的来源中没有可补充的本地影视。');
      for (final expected in candidates) {
        token.check();
        try {
          final source = await sources.source(
            expected.identity.sourceId,
            includeCounts: false,
          );
          final revision = sources.sourceContentRevision(source.id);
          final service = expected.isSeries ? series : movie;
          final before = jsonEncode(
            (await service.metadata(expected.identity))?.toJson(),
          );
          Future<void> validateCommit() async {
            token.check();
            final current = await sources.source(
              source.id,
              includeCounts: false,
            );
            if (isScanning() ||
                sources.isScanning(source.id) ||
                !current.options.includeInMetadataFetch ||
                sources.sourceContentRevision(source.id) != revision ||
                current.updatedAt != source.updatedAt ||
                current.location != source.location ||
                current.accessIdentity != source.accessIdentity ||
                current.lastScan != source.lastScan ||
                (await settings.read()).language != config.language) {
              throw const SourceFailure('来源、索引或匹配配置已改变，已保留现有资料。');
            }
          }

          Future<void> validate() async {
            await validateCommit();
            final current = await sources.media(expected.identity);
            if ((
                      current.title,
                      current.originalTitle,
                      current.year,
                      current.overview,
                      current.posterPath,
                      current.backdropPath,
                      current.type,
                      current.isSeries,
                      current.modified,
                      current.bytes,
                      current.parentId,
                    ) !=
                    (
                      expected.title,
                      expected.originalTitle,
                      expected.year,
                      expected.overview,
                      expected.posterPath,
                      expected.backdropPath,
                      expected.type,
                      expected.isSeries,
                      expected.modified,
                      expected.bytes,
                      expected.parentId,
                    ) ||
                jsonEncode(
                      (await service.metadata(expected.identity))?.toJson(),
                    ) !=
                    before) {
              throw const SourceFailure('影视资料已改变，已保留最新资料。');
            }
          }

          await validate();
          final best = await findTmdbVideoMatch(
            client: service.client,
            source: source,
            item: expected,
            children: expected.isSeries
                ? await sources.indexedChildren(expected.identity)
                : const [],
            kind: expected.isSeries ? TmdbMediaKind.tv : TmdbMediaKind.movie,
            settings: config,
            credential: credential,
            cancellation: token,
            onFailure: onFailure,
          );
          if (best == null ||
              best.confidence < config.matchTolerance.videoThreshold) {
            skipped++;
          } else {
            final result = await service.apply(
              expected.identity,
              best.candidate,
              cancellation: token,
              validate: validate,
              validateCommit: validateCommit,
              supplementOnly: true,
            );
            updated++;
            warnings += result.warnings.length;
          }
        } on ScanCancelled {
          rethrow;
        } catch (error, stack) {
          token.check();
          onFailure?.call(error, stack);
          failed++;
        }
        processed++;
        publish();
      }
      publish(
        running: false,
        message: '已补充 $updated 项，跳过 $skipped 项，失败 $failed 项，警告 $warnings 项。',
      );
    } on ScanCancelled {
      publish(running: false, message: '补充已取消，已完成的资料保留。');
    } catch (error, stack) {
      onFailure?.call(error, stack);
      publish(
        running: false,
        message: error is SourceFailure ? error.message : '元数据补充失败，请稍后重试。',
      );
      rethrow;
    } finally {
      if (identical(_token, token)) _token = null;
    }
  }

  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    cancel();
    try {
      await _pending;
    } catch (_) {}
  }
}
