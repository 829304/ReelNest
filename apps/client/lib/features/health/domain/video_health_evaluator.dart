import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import 'local_health_evaluator.dart';

/// AppState core metadata/duplicate projections and MediaDetailRepository's
/// four detail-presence categories. Only current public video scope is checked.
class VideoHealthEvaluator {
  const VideoHealthEvaluator(this.local);
  final LocalHealthEvaluator local;
  static final _nonAlphanumeric = RegExp(r'[^\p{L}\p{N}\p{M}]', unicode: true);
  static String duplicateKey(IndexedMedia item) =>
      '${item.type}-${item.title.toLowerCase().replaceAll(_nonAlphanumeric, '')}-${item.year ?? 'unknown'}';

  Future<LibraryHealthSnapshot> evaluate(
    LibraryInventory inventory, {
    required ScanCancellation cancellation,
    Map<MediaIdentity, String> unhealthyURLs = const {},
  }) async {
    final sources = inventory.sources
        .where(
          (s) => !{
            SourceMediaType.music,
            SourceMediaType.photo,
            SourceMediaType.privateCollection,
          }.contains(s.mediaType),
        )
        .toList();
    final byId = {for (final s in sources) s.id: s};
    final children = <MediaIdentity, List<IndexedMedia>>{};
    final blocked = <MediaIdentity>{};
    var processed = 0;
    for (final item in inventory.items) {
      cancellation.check();
      if (++processed % 128 == 0) await Future<void>.delayed(Duration.zero);
      if ({
        'private',
        'privateCollection',
        'music',
        'photo',
      }.contains(item.type)) {
        blocked.add(item.identity);
      }
      if (item.parentId != null) {
        (children[(
                  sourceId: item.identity.sourceId,
                  localId: item.parentId!,
                )] ??=
                [])
            .add(item);
      }
    }
    final queue = blocked.toList();
    for (var i = 0; i < queue.length; i++) {
      cancellation.check();
      if (i % 128 == 0) await Future<void>.delayed(Duration.zero);
      for (final child in children[queue[i]] ?? <IndexedMedia>[]) {
        if (blocked.add(child.identity)) queue.add(child.identity);
      }
    }
    final items = <IndexedMedia>[];
    for (final item in inventory.items) {
      cancellation.check();
      if (++processed % 128 == 0) await Future<void>.delayed(Duration.zero);
      final source = byId[item.identity.sourceId];
      if (source == null || blocked.contains(item.identity)) continue;
      if (source.kind.isFileSource) {
        final path = local.itemPath(item, source);
        if (!local.inside(path, source.location) ||
            inventory.sources.any(
              (s) =>
                  s.kind.isFileSource &&
                  {
                    SourceMediaType.privateCollection,
                    SourceMediaType.photo,
                    SourceMediaType.music,
                  }.contains(s.mediaType) &&
                  local.inside(path, s.location),
            )) {
          continue;
        }
      }
      if (!source.kind.isFileSource) {
        if (item.remote?.collectionType?.toLowerCase() == 'photos' ||
            item.displayType == 'music') {
          continue;
        }
        final selected = source.options.selectedEmbyLibraryIDs;
        if (selected.isNotEmpty && !selected.contains(item.remote?.libraryId)) {
          continue;
        }
      }
      items.add(item);
    }
    final scoped = (sources: sources, items: items);
    final base = await local.evaluate(
      (sources: inventory.sources, items: items),
      cancellation: cancellation,
      sourceScope: byId.keys.toSet(),
    );
    final core = <MediaIdentity, List<String>>{...base.metadataGaps};
    final detail = <MediaIdentity, List<String>>{};
    final groups = <String, List<IndexedMedia>>{};
    final remoteMissing = <MediaIdentity>{};
    var n = 0;
    for (final item in items) {
      cancellation.check();
      if (++n % 128 == 0) await Future<void>.delayed(Duration.zero);
      final source = byId[item.identity.sourceId]!;
      if (source.kind.isRemoteVideoSource &&
          source.options.includeInHealthCheck &&
          !item.isSeries &&
          item.remote?.externalId.trim().isNotEmpty != true) {
        remoteMissing.add(item.identity);
      }
      if (!source.options.includeInHealthCheck ||
          item.parentId != null ||
          item.type == 'episode') {
        continue;
      }
      if (!source.kind.isFileSource) {
        if (item.displayType == 'homeVideo') continue;
        final fields = [
          if (item.posterPath == null) '封面',
          if (item.year == null) '年份',
          if (item.overview?.trim().isNotEmpty != true) '简介',
        ];
        if (fields.isNotEmpty) core[item.identity] = fields;
        // Remote playback URLs are prepared on demand from this external ID.
        // Missing MediaSources in a browsing response is not a broken path.
        continue;
      }
      final path = local.itemPath(item, source);
      if (!local.inside(path, source.location) ||
          sources.any(
            (s) =>
                s.kind.isFileSource &&
                !s.options.includeInHealthCheck &&
                local.inside(path, s.location),
          ) ||
          inventory.sources.any(
            (s) =>
                s.kind.isFileSource &&
                {
                  SourceMediaType.privateCollection,
                  SourceMediaType.photo,
                }.contains(s.mediaType) &&
                local.inside(path, s.location),
          )) {
        continue;
      }
      (groups[duplicateKey(item)] ??= []).add(item);
      if (item.type == 'homeVideo') continue;
      // Current local index stores only core/NFO fields and artwork references.
      // No external ID, credits or related-title records have been migrated;
      // these are real missing data, never implicitly successful checks.
      detail[item.identity] = ['外部 ID', '人物', '艺术照', '推荐'];
    }
    cancellation.check();
    final duplicates = groups.values.where((group) => group.length > 1).toList()
      ..sort(
        (a, b) =>
            a.first.title.toLowerCase().compareTo(b.first.title.toLowerCase()),
      );
    return LibraryHealthSnapshot(
      inventory: scoped,
      configurationSources: inventory.sources,
      missing: {...base.missing, ...remoteMissing},
      safeMissing: base.safeMissing,
      offline: base.offline.intersection(byId.keys.toSet()),
      metadataGaps: core,
      detailGaps: detail,
      duplicates: duplicates,
      unhealthyURLs: {
        for (final item in items)
          if (byId[item.identity.sourceId]?.kind == MediaSourceKind.url &&
              byId[item.identity.sourceId]!.options.includeInHealthCheck &&
              unhealthyURLs.containsKey(item.identity))
            item.identity: unhealthyURLs[item.identity]!,
      },
      evaluationComplete: true,
      // Emby lastScan certifies the current selection: settings invalidate it
      // on expansion, and only a complete snapshot commit can restore it.
      partialIndex: sources.any(
        (s) => s.kind.isRemoteVideoSource && s.lastScan == null,
      ),
    );
  }
}
