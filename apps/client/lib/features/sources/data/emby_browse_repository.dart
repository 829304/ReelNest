import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_client.dart';

import '../../../domain/media_source.dart';
import '../../../sources/emby/emby_item_mapper.dart';
import 'emby_connection_repository.dart';
import 'emby_library_repository.dart';
import 'source_repository.dart';

/// A foreground page cache is independent of the complete background snapshot.
/// It only adds missing rows: no pruning, no last_scan, no overwrite of old trace.
class EmbyBrowseRepository {
  const EmbyBrowseRepository(this.sources, this.connections);
  final SourceRepository sources;
  final EmbyConnectionRepository connections;

  Future<List<EmbyLibrary>> catalog(
    String sourceId,
    ScanCancellation cancellation,
  ) async {
    final source = await sources.source(sourceId, includeCounts: false);
    final rows = await sources.database
        .customSelect(
          'SELECT * FROM remote_library_views WHERE source_id = ?',
          variables: [Variable(sourceId)],
        )
        .get();
    cancellation.check();
    if (rows.isNotEmpty || source.lastScan != null) {
      return rows
          .map(
            (r) => EmbyLibrary(
              id: r.read<String>('library_id'),
              name: r.read<String>('name'),
              collectionType: r.readNullable<String>('collection_type'),
            ),
          )
          .toList();
    }
    final views = await connections.browseLibraries(
      sourceId,
      cancellation: cancellation,
    );
    cancellation.check();
    await sources.database.transaction(() async {
      final latest = await sources.source(sourceId, includeCounts: false);
      if (jsonEncode(latest.options.toJson()) !=
          jsonEncode(source.options.toJson())) {
        throw const SourceFailure('媒体库范围已改变，请重新打开。');
      }
      // Another foreground request or sync may already have populated Views.
      final present = await sources.database
          .customSelect(
            'SELECT 1 FROM remote_library_views WHERE source_id = ? LIMIT 1',
            variables: [Variable(sourceId)],
          )
          .getSingleOrNull();
      if (present == null && latest.lastScan == null) {
        await EmbyLibraryRepository(sources).replaceViews(sourceId, views);
      }
      cancellation.check();
    });
    sources.traceChanged();
    return views;
  }

  /// A series opened from the first video page must not wait for unrelated
  /// libraries/episodes to finish indexing before its own episode list appears.
  Future<void> loadEpisodes(
    MediaIdentity identity,
    ScanCancellation cancellation,
  ) async {
    final source = await sources.source(
      identity.sourceId,
      includeCounts: false,
    );
    if (source.lastScan != null) return;
    final series = await sources.media(identity);
    if (!series.isSeries || series.remote == null) return;
    final remote = series.remote!;
    final library = remote.libraryId == null
        ? null
        : EmbyLibrary(
            id: remote.libraryId!,
            name: remote.libraryName ?? '',
            collectionType: remote.collectionType,
          );
    final mapper = EmbyItemMapper(source.id, DateTime.now().toUtc());
    var start = 0;
    int? total;
    final seen = <String>{};
    for (var n = 0; n < 10000; n++) {
      cancellation.check();
      final page = await connections.browsePage(
        source.id,
        parentId: remote.externalId,
        episodesOnly: true,
        start: start,
        limit: 100,
        cancellation: cancellation,
      );
      cancellation.check();
      if (total != null && page.total != null && total != page.total) {
        throw const SourceFailure('Emby 剧集在分页期间发生变化，请重试。');
      }
      total ??= page.total;
      final ids = page.items.map((i) => i.id).toSet();
      if (page.items.isNotEmpty && ids.difference(seen).isEmpty) {
        throw const SourceFailure('Emby 剧集分页没有返回新条目，请重试。');
      }
      final items = <IndexedMedia>[];
      for (final dto in page.items) {
        final item = mapper.map(dto, library);
        if (item == null ||
            item.type != 'episode' ||
            item.parentId != identity.localId) {
          throw const SourceFailure('Emby 返回了其他系列的剧集，请重试。');
        }
        items.add(item);
      }
      final next = start + page.items.length;
      final done = page.items.isEmpty || (total != null && next >= total);
      if (done && total != null && {...seen, ...ids}.length < total) {
        throw const SourceFailure('Emby 剧集分页不完整，请重试。');
      }
      await sources.cacheRemoteItems(source, items, cancellation: cancellation);
      seen.addAll(ids);
      if (done) return;
      start = next;
    }
    throw const SourceFailure('Emby 剧集分页次数超出上限，请重试。');
  }

  Future<EmbyBrowseCursor> open(
    String sourceId, {
    String? libraryId,
    String? personKey,
    required ScanCancellation cancellation,
  }) async {
    final source = await sources.source(sourceId, includeCounts: false);
    if (source.kind != MediaSourceKind.emby) {
      throw const SourceFailure('此来源不是 Emby。');
    }
    final views = await catalog(sourceId, cancellation);
    final selected = source.options.selectedEmbyLibraryIDs.toSet();
    final scope = views
        .where(
          (view) =>
              (selected.isEmpty || selected.contains(view.id)) &&
              view.collectionType?.toLowerCase() != 'music' &&
              (libraryId == null || view.id == libraryId),
        )
        .toList();
    if (libraryId != null && scope.isEmpty) {
      throw const SourceFailure('此媒体库已移除或未在同步范围内。');
    }
    return EmbyBrowseCursor._(
      this,
      source,
      [
        ...scope,
        if (views.isEmpty && selected.isEmpty && libraryId == null) null,
      ],
      cancellation,
      personKey,
    );
  }
}

class EmbyBrowseCursor {
  EmbyBrowseCursor._(
    this.repository,
    this.source,
    this.libraries,
    this.cancellation,
    this.personKey,
  );
  final EmbyBrowseRepository repository;
  final MediaSource source;
  final List<EmbyLibrary?> libraries;
  final ScanCancellation cancellation;
  final String? personKey;
  int _library = 0, _start = 0, _pages = 0;
  final _seen = <String>{};
  final _pageSeen = <String>{};
  int? _total;
  bool get hasMore => _library < libraries.length;

  /// One page per call, except genuinely empty libraries. Offsets and identities
  /// advance only after the page has been validated and safely cached.
  Future<List<IndexedMedia>> next() async {
    while (hasMore) {
      cancellation.check();
      if (_pages >= 10000) throw const SourceFailure('Emby 分页次数超出上限，请重试。');
      final library = libraries[_library];
      final page = await repository.connections.browsePage(
        source.id,
        parentId: library?.id,
        personKey: personKey,
        start: _start,
        cancellation: cancellation,
      );
      cancellation.check();
      if (_total != null && page.total != null && _total != page.total) {
        throw const SourceFailure('Emby 媒体库在分页期间发生变化，请刷新后重试。');
      }
      final ids = page.items.map((i) => i.id).toSet();
      if (page.items.isNotEmpty && ids.difference(_pageSeen).isEmpty) {
        throw const SourceFailure('Emby 分页没有返回新条目，请重试。');
      }
      final expected = page.total ?? _total;
      final nextOffset = _start + page.items.length;
      if (page.items.isEmpty &&
          expected != null &&
          _pageSeen.length < expected) {
        throw const SourceFailure('Emby 分页提前结束，请重试。');
      }
      final mapper = EmbyItemMapper(source.id, DateTime.now().toUtc());
      final mapped = <String, IndexedMedia>{};
      for (final dto in page.items) {
        final item = mapper.map(dto, library);
        if (item == null || item.type == 'music') continue;
        mapped[item.identity.localId] = item;
        if (dto.type == 'episode' &&
            dto.text('SeriesId') != null &&
            dto.text('SeriesName')?.isNotEmpty == true) {
          mapped.putIfAbsent(
            dto.text('SeriesId')!,
            () => mapper.syntheticSeries(dto, library),
          );
        }
      }
      final done =
          page.items.isEmpty || (expected != null && nextOffset >= expected);
      if (done &&
          expected != null &&
          {..._pageSeen, ...ids}.length < expected) {
        throw const SourceFailure('Emby 分页条目重复或缺失，请刷新后重试。');
      }
      final values = mapped.values.toList()
        ..sort(
          (a, b) => a.isSeries == b.isSeries
              ? 0
              : a.isSeries
              ? -1
              : 1,
        );
      await repository.sources.cacheRemoteItems(
        source,
        values,
        cancellation: cancellation,
      );
      cancellation.check();
      _pages++;
      _pageSeen.addAll(ids);
      _total = expected;
      if (done) {
        _library++;
        _start = 0;
        _total = null;
        _pageSeen.clear();
      } else {
        _start = nextOffset;
      }
      final visible = values
          .where((i) => i.parentId == null && _seen.add(i.identity.localId))
          .toList();
      if (visible.isNotEmpty || !hasMore || page.items.isNotEmpty) {
        return visible;
      }
    }
    return [];
  }
}
