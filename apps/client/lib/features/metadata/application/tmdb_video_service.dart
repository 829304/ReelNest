import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../sources/data/source_repository.dart';
import '../data/tmdb_artwork_store.dart';
import '../data/tmdb_client.dart';
import '../data/tmdb_settings_repository.dart';
import '../domain/tmdb_models.dart';
import '../domain/nfo_metadata_update.dart';
import '../domain/supplemental_tmdb_metadata.dart';
import '../data/video_nfo_policy.dart';
import '../data/video_nfo_writer.dart';

class TmdbVideoService {
  TmdbVideoService({
    required this.sources,
    required this.settings,
    required this.client,
    required this.artwork,
    this.kind = TmdbMediaKind.movie,
    this.onWriteFailure,
    VideoNfoWriter? nfoWriter,
  }) : nfoWriter = nfoWriter ?? VideoNfoWriter();
  final VideoNfoWriter nfoWriter;
  final void Function(Object, StackTrace)? onWriteFailure;

  final SourceRepository sources;
  final TmdbSettingsRepository settings;
  final TmdbClient client;
  final TmdbArtworkStore artwork;
  final TmdbMediaKind kind;
  bool get _tv => kind == TmdbMediaKind.tv;
  String get _table => _tv ? 'local_series_metadata' : 'local_movie_metadata';
  final _active = <MediaIdentity, ScanCancellation>{};
  final _pending = <Future<TmdbApplyResult>>{};
  final _searchTokens = <ScanCancellation>{};
  final _searches = <Future<List<TmdbCandidate>>>{};
  bool _closed = false;

  Future<List<TmdbCandidate>> search(
    String query, {
    ScanCancellation? cancellation,
  }) {
    if (_closed) return Future.error(const SourceFailure('应用正在关闭。'));
    final token = cancellation ?? ScanCancellation();
    _searchTokens.add(token);
    final work = _search(query, token);
    _searches.add(work);
    unawaited(
      work
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            _searchTokens.remove(token);
            _searches.remove(work);
          }),
    );
    return work;
  }

  Future<List<TmdbCandidate>> _search(
    String query,
    ScanCancellation token,
  ) async {
    try {
      final config = await settings.read();
      return await client.search(
        query,
        credential: await settings.credential(),
        language: config.language,
        cancellation: token,
        kind: kind,
      );
    } on ScanCancelled {
      rethrow;
    } on SourceFailure {
      rethrow;
    } catch (_) {
      throw const SourceFailure('TMDB 搜索失败，请稍后重试。');
    }
  }

  Future<TmdbMetadata?> metadata(MediaIdentity identity) async {
    final row = await sources.database
        .customSelect(
          'SELECT value FROM $_table WHERE source_id=? AND local_id=?',
          variables: [Variable(identity.sourceId), Variable(identity.localId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    try {
      return TmdbMetadata.fromJson(
        jsonDecode(row.read<String>('value')) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const SourceFailure('本地影视资料读取失败，请重新匹配。');
    }
  }

  Future<TmdbEpisodeMetadata?> episodeMetadata(MediaIdentity identity) async {
    final row = await sources.database
        .customSelect(
          'SELECT value FROM local_episode_metadata WHERE source_id=? AND local_id=?',
          variables: [Variable(identity.sourceId), Variable(identity.localId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    try {
      return TmdbEpisodeMetadata.fromJson(
        jsonDecode(row.read<String>('value')) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const SourceFailure('本地单集资料读取失败，请重新匹配系列。');
    }
  }

  /// Batch callers may supply cancellation and optimistic snapshot guards.
  /// The final guard runs inside the transaction after all awaited writes so a
  /// newly started scan rolls the entire metadata update back.
  Future<TmdbApplyResult> apply(
    MediaIdentity identity,
    TmdbCandidate selected, {
    ScanCancellation? cancellation,
    Future<void> Function()? validate,
    Future<void> Function()? validateCommit,
    bool supplementOnly = false,
  }) {
    if (_closed) return Future.error(const SourceFailure('应用正在关闭。'));
    if (_active.containsKey(identity)) {
      return Future.error(const SourceFailure('此影视正在应用资料，请稍候。'));
    }
    final token = cancellation ?? ScanCancellation();
    _active[identity] = token;
    final operation = _apply(
      identity,
      selected,
      token,
      validate,
      validateCommit,
      supplementOnly,
    );
    _pending.add(operation);
    unawaited(
      operation
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            _active.remove(identity);
            _pending.remove(operation);
          }),
    );
    return operation;
  }

  Future<TmdbApplyResult> _apply(
    MediaIdentity identity,
    TmdbCandidate selected,
    ScanCancellation token,
    Future<void> Function()? validate,
    Future<void> Function()? validateCommit,
    bool supplementOnly,
  ) async {
    try {
      token.check();
      await validate?.call();
      if (selected.id <= 0 || selected.kind != kind) {
        throw const SourceFailure('请选择对应类型的 TMDB 影视资料。');
      }
      final source = await sources.source(
        identity.sourceId,
        includeCounts: false,
      );
      if (supplementOnly && !source.options.includeInMetadataFetch) {
        throw const SourceFailure('该来源未参与元数据补充。');
      }
      final before = await sources.media(identity);
      if (!source.kind.isFileSource ||
          (_tv
              ? !before.isSeries
              : before.type != 'movie' || before.isSeries) ||
          before.parentId != null ||
          before.remote != null) {
        throw SourceFailure(_tv ? '仅支持本地系列的 TMDB 匹配。' : '本轮仅支持本地电影的 TMDB 匹配。');
      }
      final children = _tv
          ? await sources.indexedChildren(identity)
          : <IndexedMedia>[];
      final previous = (_tv || supplementOnly)
          ? await metadata(identity)
          : null;
      final config = await settings.read();
      final credential = await settings.credential();
      if (credential.isEmpty) {
        throw const SourceFailure('请先在设置中填写 TMDB API Key 或 Read Access Token。');
      }
      final warnings = <String>[];
      TmdbMetadata detail;
      try {
        detail = await (_tv ? client.series : client.movie)(
          selected.id,
          credential: credential,
          language: config.language,
          cancellation: token,
          fallback: selected,
        );
      } on ScanCancelled {
        rethrow;
      } catch (_) {
        detail = TmdbMetadata(candidate: selected, genres: selected.genres);
        warnings.add('TMDB 详情暂不可用，已使用所选搜索资料。');
      }
      if (_tv && !supplementOnly) {
        detail = await _loadSeasons(
          detail,
          children,
          credential,
          config.language,
          token,
          warnings,
          previous?.candidate.id == selected.id ? previous : null,
        );
      }
      NfoMetadataUpdate? sidecar;
      if (supplementOnly) {
        final patch = supplementalTmdbMetadata(before, detail, previous);
        detail = patch.metadata;
        sidecar = patch.sidecar;
      }
      String? poster, backdrop;
      Future<String?> materialize(String? url, String label) async {
        if (url == null) return null;
        try {
          final data = await client.artwork(url, token);
          token.check();
          final reference = await artwork.save(data);
          token.check();
          return reference;
        } on ScanCancelled {
          rethrow;
        } catch (_) {
          warnings.add('$label下载失败，已保留现有图片。');
          return null;
        }
      }

      // Fetch outside SQLite transactions. Partial/failed downloads never
      // overwrite artwork references already used by the library.
      final images = await Future.wait([
        supplementOnly && before.posterPath?.isNotEmpty == true
            ? Future<String?>.value()
            : materialize(detail.candidate.posterUrl, '海报'),
        supplementOnly && before.backdropPath?.isNotEmpty == true
            ? Future<String?>.value()
            : materialize(detail.candidate.backdropUrl, '背景图'),
      ]);
      poster = images[0];
      backdrop = images[1];
      token.check();
      await sources.database.transaction(() async {
        token.check();
        await validate?.call();
        final currentSource = await sources.source(
          identity.sourceId,
          includeCounts: false,
        );
        final current = await sources.media(identity);
        if (supplementOnly &&
            (!currentSource.options.includeInMetadataFetch ||
                currentSource.updatedAt != source.updatedAt)) {
          throw const SourceFailure('来源参与策略已改变，请重新补充。');
        }
        if (currentSource.kind != source.kind ||
            currentSource.location != source.location ||
            currentSource.accessIdentity != source.accessIdentity ||
            current.type != before.type ||
            current.modified != before.modified ||
            current.bytes != before.bytes ||
            current.isSeries != before.isSeries ||
            current.remote != null ||
            current.parentId != null) {
          throw const SourceFailure('媒体源或文件已更改，请重新打开后匹配。');
        }
        if (_tv) {
          final currentChildren = await sources.indexedChildren(identity);
          final byId = {for (final child in children) child.identity: child};
          if (currentChildren.length != children.length ||
              currentChildren.any((child) {
                final old = byId[child.identity];
                return old == null ||
                    child.modified != old.modified ||
                    child.bytes != old.bytes ||
                    child.type != old.type ||
                    child.parentId != old.parentId ||
                    child.seasonNumber != old.seasonNumber ||
                    child.episodeNumber != old.episodeNumber ||
                    child.remote != null;
              })) {
            throw const SourceFailure('系列中的文件或季集编号已更改，请重新匹配。');
          }
        }
        final candidate = detail.candidate;
        await sources.database.customStatement(
          '''UPDATE media SET title=?,
          year=COALESCE(?,year),original_title=COALESCE(?,original_title),
          overview=COALESCE(?,overview),poster_path=COALESCE(?,poster_path),
          backdrop_path=COALESCE(?,backdrop_path) WHERE source_id=? AND local_id=?''',
          [
            candidate.title,
            candidate.year,
            candidate.originalTitle,
            candidate.overview,
            poster,
            backdrop,
            identity.sourceId,
            identity.localId,
          ],
        );
        await sources.database.customStatement(
          '''INSERT INTO $_table(source_id,local_id,value) VALUES(?,?,?)
          ON CONFLICT(source_id,local_id) DO UPDATE SET value=excluded.value''',
          [identity.sourceId, identity.localId, jsonEncode(detail.toJson())],
        );
        if (_tv && !supplementOnly) {
          await _saveEpisodes(identity, detail, children, token, warnings);
        }
        await sources.database.customStatement(
          '''INSERT INTO media_activity(source_id,local_id,updated_at) VALUES(?,?,?)
          ON CONFLICT(source_id,local_id) DO UPDATE SET updated_at=excluded.updated_at''',
          [
            identity.sourceId,
            identity.localId,
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ],
        );
        token.check();
        await validateCommit?.call();
      });
      if (supplementOnly && source.options.preferMetadataWriteToSource) {
        try {
          final expected = jsonEncode(detail.toJson());
          Future<void> validateWrite() async {
            token.check();
            await validateCommit?.call();
            final currentSource = await sources.source(
              identity.sourceId,
              includeCounts: false,
            );
            if (currentSource.updatedAt != source.updatedAt ||
                currentSource.location != source.location ||
                !currentSource.options.preferMetadataWriteToSource ||
                !currentSource.options.includeInMetadataFetch ||
                sources.isScanning(identity.sourceId) ||
                !await sources.isSafeDirectory(currentSource) ||
                jsonEncode((await metadata(identity))?.toJson()) != expected) {
              throw const SourceFailure('媒体源或资料已改变，已跳过 NFO 写回。');
            }
          }

          await validateWrite();
          final target = await VideoNfoPolicy.resolve(source, before, children);
          if (target == null) {
            warnings.add('无法确认 NFO 归属，资料仅保存到 ReelNest 索引。');
          } else {
            final result = await nfoWriter.write(
              root: source.location,
              target: target,
              rootTag: _tv ? 'tvshow' : 'movie',
              fallbackTitle: before.title,
              update: sidecar!,
              cancellation: token,
              validate: validateWrite,
            );
            if (result.warning != null) warnings.add(result.warning!);
          }
        } catch (error, stack) {
          onWriteFailure?.call(error, stack);
          warnings.add('NFO 写回未完成，资料已保存到 ReelNest 索引；原文件和安全副本已保留。');
        }
      }
      sources.traceChanged(sourceIds: [identity.sourceId]);
      return TmdbApplyResult(warnings: List.unmodifiable(warnings));
    } on ScanCancelled {
      throw const SourceFailure('应用正在关闭，已取消资料更新。');
    } on SourceFailure {
      rethrow;
    } catch (_) {
      throw const SourceFailure('影视资料保存失败，已有资料未更改，请重试。');
    }
  }

  Future<TmdbMetadata> _loadSeasons(
    TmdbMetadata detail,
    List<IndexedMedia> children,
    String credential,
    String language,
    ScanCancellation token,
    List<String> warnings,
    TmdbMetadata? previous,
  ) async {
    final numbers =
        children
            .where(
              (c) =>
                  c.seasonNumber != null &&
                  c.seasonNumber! >= 0 &&
                  c.episodeNumber != null &&
                  c.episodeNumber! > 0,
            )
            .map((c) => c.seasonNumber!)
            .toSet()
            .toList()
          ..sort();
    final seasons = {
      for (final season in detail.seasons) season.number: season,
    };
    var index = 0;
    Future<void> worker() async {
      while (index < numbers.length) {
        token.check();
        final number = numbers[index++];
        try {
          seasons[number] = await client.season(
            detail.candidate.id,
            number,
            credential: credential,
            language: language,
            cancellation: token,
          );
        } on ScanCancelled {
          rethrow;
        } catch (_) {
          final old = previous?.seasons
              .where((s) => s.number == number)
              .firstOrNull;
          if (old != null) seasons[number] = old;
          warnings.add('第 $number 季资料暂不可用，已保留现有单集资料。');
        }
      }
    }

    // Only seasons present locally, two requests at most; no per-episode fanout.
    await Future.wait([worker(), worker()]);
    final ordered = seasons.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return detail.withSeasons(ordered);
  }

  Future<void> _saveEpisodes(
    MediaIdentity parent,
    TmdbMetadata detail,
    List<IndexedMedia> children,
    ScanCancellation token,
    List<String> warnings,
  ) async {
    final episodes = {
      for (final season in detail.seasons)
        for (final episode in season.episodes)
          (episode.seasonNumber, episode.episodeNumber): episode,
    };
    var unmatched = 0;
    for (final child in children) {
      token.check();
      final episode = episodes[(child.seasonNumber, child.episodeNumber)];
      if (episode == null ||
          child.remote != null ||
          child.isSeries ||
          child.type != 'episode') {
        unmatched++;
        continue;
      }
      await sources.database.customStatement(
        '''
        UPDATE media SET title=COALESCE(NULLIF(?,''),title),
          overview=COALESCE(?,overview),year=COALESCE(?,year)
        WHERE source_id=? AND local_id=?
      ''',
        [
          episode.title,
          episode.overview,
          episode.airDate != null && episode.airDate!.length >= 4
              ? int.tryParse(episode.airDate!.substring(0, 4))
              : null,
          child.identity.sourceId,
          child.identity.localId,
        ],
      );
      await sources.database.customStatement(
        '''
        INSERT INTO local_episode_metadata(source_id,local_id,series_local_id,value) VALUES(?,?,?,?)
        ON CONFLICT(source_id,local_id) DO UPDATE SET series_local_id=excluded.series_local_id,value=excluded.value
      ''',
        [
          child.identity.sourceId,
          child.identity.localId,
          parent.localId,
          jsonEncode(episode.toJson()),
        ],
      );
    }
    if (unmatched > 0) warnings.add('$unmatched 个本地单集未取得对应资料，已保留现有内容。');
  }

  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    for (final token in _active.values) {
      token.cancel();
    }
    for (final token in _searchTokens) {
      token.cancel();
    }
    await Future.wait(
      _searches.toList().map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
    await Future.wait(
      _pending.toList().map((f) async {
        try {
          await f;
        } catch (_) {}
      }),
    );
  }
}
