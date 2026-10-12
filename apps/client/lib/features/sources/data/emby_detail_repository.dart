import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../api/emby/emby_detail.dart';
import '../../../domain/media_source.dart';
import 'emby_connection_repository.dart';
import 'source_repository.dart';
import 'emby_browse_repository.dart';

class EmbyDetailSnapshot {
  const EmbyDetailSnapshot(this.detail, this.fetchedAt, {this.refreshError});
  final EmbyDetail detail;
  final DateTime fetchedAt;
  final String? refreshError;
}

/// Original loadDetailSnapshot's 30-day cache, with source-scoped identities.
/// Failed refreshes preserve the last complete snapshot and never import UserData.
class EmbyDetailRepository {
  EmbyDetailRepository({
    required this.sources,
    required this.connections,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 15),
  }) : now = now ?? DateTime.now;
  final SourceRepository sources;
  final EmbyConnectionRepository connections;
  final DateTime Function() now;
  final Duration timeout;
  // Session-only first paint; every visit still refreshes from the server.
  final _personSnapshots =
      <
        ({String sourceId, String personKey}),
        ({String scope, List<IndexedMedia> items})
      >{};
  String _scope(MediaSource source) => jsonEncode([
    source.options.toJson(),
    source.lastScan?.millisecondsSinceEpoch,
  ]);
  Future<EmbyDetailSnapshot?> read(MediaIdentity id) async {
    final row = await sources.database
        .customSelect(
          'SELECT value, fetched_at FROM remote_media_details WHERE source_id = ? AND local_id = ?',
          variables: [Variable(id.sourceId), Variable(id.localId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return EmbyDetailSnapshot(
      EmbyDetail.fromJson(
        jsonDecode(row.read<String>('value')) as Map<String, dynamic>,
      ),
      DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('fetched_at'),
        isUtc: true,
      ),
    );
  }

  bool isFresh(EmbyDetailSnapshot value) =>
      now().difference(value.fetchedAt) < const Duration(days: 30);

  Future<EmbyDetailSnapshot> load(
    MediaIdentity id, {
    bool force = false,
    ScanCancellation? cancellation,
  }) async {
    final token = cancellation ?? ScanCancellation();
    token.check();
    final item = await sources.media(id);
    if ((await sources.source(id.sourceId, includeCounts: false)).kind !=
        MediaSourceKind.emby) {
      throw const SourceFailure('此来源不支持 Emby 详情。');
    }
    final cached = await read(id);
    token.check();
    if (!force && cached != null && isFresh(cached)) return cached;
    final cancelled = Completer<EmbyDetail>();
    final unlisten = token.listen(
      () => cancelled.completeError(const ScanCancelled()),
    );
    var expired = false;
    try {
      final detail =
          await Future.any([
            connections.detail(item, cancellation: token),
            cancelled.future,
          ]).timeout(
            timeout,
            onTimeout: () {
              expired = true;
              token.cancel();
              throw const SourceFailure('Emby 详情读取超时，请重试。');
            },
          );
      token.check();
      final fetchedAt = now().toUtc();
      await sources.database.transaction(() async {
        token.check();
        // Recheck existence after the network wait; never resurrect a removed
        // item or replace its library/UserData using this detail-only response.
        await sources.media(id);
        await sources.database.customStatement(
          '''
          INSERT INTO remote_media_details(source_id, local_id, value, fetched_at)
          VALUES (?, ?, ?, ?) ON CONFLICT(source_id, local_id) DO UPDATE SET
            value = excluded.value, fetched_at = excluded.fetched_at
        ''',
          [
            id.sourceId,
            id.localId,
            jsonEncode(detail.toJson()),
            fetchedAt.millisecondsSinceEpoch,
          ],
        );
        token.check();
      });
      return EmbyDetailSnapshot(detail, fetchedAt);
    } on ScanCancelled {
      rethrow;
    } catch (_) {
      if (!expired) token.check();
      if (cached != null) {
        return EmbyDetailSnapshot(
          cached.detail,
          cached.fetchedAt,
          refreshError: '详情更新失败，正在显示本机缓存。',
        );
      }
      throw const SourceFailure('Emby 详情读取失败，基础信息和播放仍可使用。');
    } finally {
      unlisten();
    }
  }

  /// Query the server, not just the credits of previously opened details.
  Future<List<IndexedMedia>> personWorks(
    String sourceId,
    String personKey, {
    ScanCancellation? cancellation,
  }) => personWorkPages(sourceId, personKey, cancellation: cancellation).last;

  /// Publish each validated page without waiting for unrelated libraries. Each
  /// emission is a new, sorted snapshot; later failures never erase prior pages.
  Stream<List<IndexedMedia>> personWorkPages(
    String sourceId,
    String personKey, {
    ScanCancellation? cancellation,
  }) async* {
    final token = cancellation ?? ScanCancellation();
    final cursor = await EmbyBrowseRepository(
      sources,
      connections,
    ).open(sourceId, personKey: personKey, cancellation: token);
    final items = <String, IndexedMedia>{};
    List<IndexedMedia> sorted() => items.values.toList()
      ..sort((a, b) {
        final year = (b.year ?? 0).compareTo(a.year ?? 0);
        return year != 0 ? year : a.title.compareTo(b.title);
      });
    var emitted = false;
    while (cursor.hasMore) {
      for (final item in await cursor.next()) {
        items[item.identity.localId] = item;
      }
      token.check();
      if (items.isNotEmpty) {
        emitted = true;
        yield sorted();
      }
    }
    token.check();
    if (items.length <= 1000) {
      final key = (sourceId: sourceId, personKey: personKey);
      _personSnapshots.remove(key);
      _personSnapshots[key] = (scope: _scope(cursor.source), items: sorted());
      if (_personSnapshots.length > 16) {
        _personSnapshots.remove(_personSnapshots.keys.first);
      }
    }
    if (!emitted) yield [];
  }

  /// Server identities cannot be joined across unrelated accounts. A person
  /// without an ID uses the same stable name key within this source.
  Future<List<IndexedMedia>> cachedPersonWorks(
    String sourceId,
    String personKey,
  ) async {
    final source = await sources.source(sourceId, includeCounts: false);
    final key = (sourceId: sourceId, personKey: personKey);
    final recent = _personSnapshots.remove(key);
    if (recent != null && recent.scope == _scope(source)) {
      _personSnapshots[key] = recent;
      return List.of(recent.items);
    }
    final rows = await sources.database
        .customSelect(
          '''SELECT local_id FROM remote_media_details d
             WHERE source_id = ? AND EXISTS (
               SELECT 1 FROM json_each(d.value, '\$.people') p
               WHERE json_extract(p.value, '\$.key') = ?
             )''',
          variables: [Variable(sourceId), Variable(personKey)],
        )
        .get();
    final selected = source.options.selectedEmbyLibraryIDs;
    final result = <IndexedMedia>[];
    final seen = <String>{};
    for (final row in rows) {
      var item = await sources.media((
        sourceId: sourceId,
        localId: row.read<String>('local_id'),
      ));
      if (item.parentId != null) {
        item = await sources.media((
          sourceId: sourceId,
          localId: item.parentId!,
        ));
      }
      if (item.type != 'music' &&
          (selected.isEmpty || selected.contains(item.remote?.libraryId)) &&
          seen.add(item.identity.localId)) {
        result.add(item);
      }
    }
    result.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    return result;
  }
}
