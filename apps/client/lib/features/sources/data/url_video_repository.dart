import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_options.dart';
import '../domain/url_video.dart';
import 'source_repository.dart';

/// A virtual library, not a filesystem scanner or a media-server connector.
class UrlVideoRepository {
  UrlVideoRepository(this.sources, {this.onAdded});
  static const sourceId = 'url-video-source',
      sourceLocation = 'urlsource://local';
  final SourceRepository sources;
  final void Function(List<MediaIdentity>)? onAdded;
  Future<List<UrlVideo>> list() async {
    final rows = await sources.database.customSelect('''
      SELECT u.*,m.title FROM url_video_entries u JOIN media m USING(source_id,local_id)
      JOIN sources s ON s.id=u.source_id WHERE s.kind='url'
      ORDER BY u.created_at DESC,u.local_id''').get();
    return List.unmodifiable(
      rows.map(
        (r) => UrlVideo(
          identity: (
            sourceId: r.read<String>('source_id'),
            localId: r.read<String>('local_id'),
          ),
          title: r.read<String>('title'),
          url: r.read<String>('url'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('created_at'),
            isUtc: true,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('updated_at'),
            isUtc: true,
          ),
        ),
      ),
    );
  }

  Future<String> location(MediaIdentity identity) async {
    final row = await sources.database
        .customSelect(
          '''
      SELECT u.url FROM url_video_entries u JOIN sources s ON s.id=u.source_id
      WHERE u.source_id=? AND u.local_id=? AND s.kind='url' ''',
          variables: [Variable(identity.sourceId), Variable(identity.localId)],
        )
        .getSingleOrNull();
    final value = row?.read<String>('url');
    if (value == null || UrlVideoPolicy.normalize(value) == null) {
      throw const SourceFailure('此视频地址已移除或无效，请重新添加。');
    }
    return value;
  }

  Future<UrlAddResult> add(String raw, {String title = ''}) async {
    final lines = UrlVideoPolicy.lines(raw);
    if (lines.length <= 1 &&
        UrlVideoPolicy.normalize(lines.firstOrNull ?? raw) == null) {
      throw const SourceFailure('链接无效，请输入 http(s)、rtsp、rtmp 等视频地址。');
    }
    final added = <MediaIdentity>[];
    var skipped = 0;
    await sources.database.transaction(() async {
      sources.requireMutationAllowed(sourceId);
      final existing = (await list()).map((e) => e.url).toSet();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final line in lines) {
        final url = UrlVideoPolicy.normalize(line);
        if (url == null || !existing.add(url)) {
          skipped++;
          continue;
        }
        if (added.isEmpty) {
          await sources.database.customStatement(
            '''INSERT OR IGNORE INTO sources
            (id,kind,name,location,location_key,recursive,ignore_hidden,media_type,
             minimum_file_size,options,created_at,updated_at)
            VALUES(?,?,?,?,?,0,1,'homeVideo',0,?,?,?)''',
            [
              sourceId,
              'url',
              'URL媒体源',
              sourceLocation,
              sourceLocation,
              jsonEncode(
                SourceOptions(
                  autoScan: false,
                  includeInMetadataFetch: false,
                ).toJson(),
              ),
              now,
              now,
            ],
          );
          final source = await sources.source(sourceId, includeCounts: false);
          if (source.kind != MediaSourceKind.url ||
              source.location != sourceLocation) {
            throw const SourceFailure('URL 媒体源容器冲突，未保存地址。');
          }
        }
        final id = UrlVideoPolicy.id(url);
        final name = lines.length == 1 && title.trim().isNotEmpty
            ? title.trim()
            : UrlVideoPolicy.title(url);
        await sources.database.customStatement(
          '''INSERT INTO media
          (source_id,local_id,title,type,bytes,modified,identity_kind)
          VALUES(?,?,?,'homeVideo',0,?,'url')''',
          [sourceId, id, name, now],
        );
        await sources.database.customStatement(
          'INSERT INTO url_video_entries VALUES(?,?,?,?,?)',
          [sourceId, id, url, now, now],
        );
        await sources.database.customStatement(
          'INSERT INTO media_activity VALUES(?,?,?)',
          [sourceId, id, now],
        );
        added.add((sourceId: sourceId, localId: id));
      }
      if (added.isEmpty) throw const SourceFailure('未添加任何链接：地址无效或已存在。');
    });
    sources.configurationChanged([sourceId]);
    // Extraction is optional background work and must never undo a saved URL.
    try {
      onAdded?.call(List.unmodifiable(added));
    } catch (_) {}
    return UrlAddResult(added: added.length, skipped: skipped);
  }

  Future<MediaIdentity> update(
    MediaIdentity identity, {
    required String url,
    required String title,
  }) async {
    final normalized = UrlVideoPolicy.normalize(url);
    if (normalized == null) throw const SourceFailure('链接无效，请输入有效的视频地址。');
    final next = (
      sourceId: identity.sourceId,
      localId: UrlVideoPolicy.id(normalized),
    );
    await sources.database.transaction(() async {
      sources.requireMutationAllowed(identity.sourceId);
      await location(identity);
      final name = title.trim().isEmpty
          ? UrlVideoPolicy.title(normalized)
          : title.trim();
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (next != identity) {
        final duplicate = await sources.database
            .customSelect(
              'SELECT 1 FROM url_video_entries WHERE url=?',
              variables: [Variable(normalized)],
            )
            .getSingleOrNull();
        if (duplicate != null) throw const SourceFailure('链接已存在，已有相同地址的条目。');
        // Copy item fields exactly as the original; records for the old stable
        // identity are deleted, never reassigned to a different URL.
        await sources.database.customStatement(
          '''INSERT INTO media
          SELECT source_id,?, ?,type,bytes,modified,missing,year,season_number,
          episode_number,series_directory,is_series,identity_kind,parent_id,
          original_title,overview,poster_path,backdrop_path FROM media
          WHERE source_id=? AND local_id=?''',
          [next.localId, name, identity.sourceId, identity.localId],
        );
        await sources.database.customStatement(
          '''INSERT INTO url_video_entries
          SELECT source_id,?,?,created_at,? FROM url_video_entries WHERE source_id=? AND local_id=?''',
          [next.localId, normalized, now, identity.sourceId, identity.localId],
        );
        await sources.database.customStatement(
          'DELETE FROM media WHERE source_id=? AND local_id=?',
          [identity.sourceId, identity.localId],
        );
      } else {
        await sources.database.customStatement(
          'UPDATE media SET title=? WHERE source_id=? AND local_id=?',
          [name, identity.sourceId, identity.localId],
        );
        await sources.database.customStatement(
          'UPDATE url_video_entries SET updated_at=? WHERE source_id=? AND local_id=?',
          [now, identity.sourceId, identity.localId],
        );
      }
      await sources.database.customStatement(
        'INSERT INTO media_activity VALUES(?,?,?) ON CONFLICT(source_id,local_id) DO UPDATE SET updated_at=excluded.updated_at',
        [next.sourceId, next.localId, now],
      );
    });
    sources.traceChanged(sourceIds: [identity.sourceId]);
    return next;
  }

  Future<void> remove(Set<MediaIdentity> identities) async {
    if (identities.isEmpty) return;
    await sources.database.transaction(() async {
      sources.requireMutationAllowed(sourceId);
      for (final id in identities) {
        // Do not allow this URL action to delete arbitrary file/server items.
        await location(id);
        await sources.database.customStatement(
          'DELETE FROM media WHERE source_id=? AND local_id=?',
          [id.sourceId, id.localId],
        );
      }
      await sources.database.customStatement(
        '''DELETE FROM sources WHERE kind='url'
        AND NOT EXISTS(SELECT 1 FROM media WHERE source_id=sources.id)''',
      );
    });
    sources.configurationChanged(identities.map((e) => e.sourceId));
  }
}
