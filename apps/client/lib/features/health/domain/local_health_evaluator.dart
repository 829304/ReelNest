import 'package:path/path.dart' as p;

import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';

/// Local branch of FileHealthEvaluator / SourcePathPolicy and
/// AppState.rebuildDerivedItemCaches. Remote evaluation belongs to its connector.
class LocalHealthEvaluator {
  LocalHealthEvaluator({
    required this.exists,
    required this.paths,
    this.sourceAvailable,
  });
  final Future<bool> Function(String) exists;
  final p.Context paths;
  final Future<bool> Function(MediaSource)? sourceAvailable;

  String _key(String path) {
    final key = paths.normalize(path);
    return paths.style == p.Style.windows ? key.toLowerCase() : key;
  }

  bool inside(String candidate, String root) {
    if (candidate.trim().isEmpty || root.trim().isEmpty) return false;
    final a = _key(candidate), b = _key(root);
    return a == b || paths.isWithin(b, a);
  }

  String itemPath(IndexedMedia item, MediaSource source) => paths.normalize(
    paths.join(
      source.location,
      item.isSeries ? item.seriesDirectory ?? '' : item.identity.localId,
    ),
  );

  Future<LibraryHealthSnapshot> evaluate(
    LibraryInventory inventory, {
    required ScanCancellation cancellation,
  }) async {
    final sources = inventory.sources.where((s) => s.kind.isFileSource).toList()
      ..sort((a, b) => b.location.length.compareTo(a.location.length));
    final byId = {for (final source in sources) source.id: source};
    final excluded = sources
        .where((s) => !s.options.includeInHealthCheck)
        .toList();
    final private = sources
        .where((s) => s.mediaType == SourceMediaType.privateCollection)
        .toList();
    final albums = sources
        .where((s) => s.mediaType == SourceMediaType.photo)
        .toList();
    final offline = <String>{};
    final missing = <MediaIdentity>{};
    final safe = <MediaIdentity>{};
    final gaps = <MediaIdentity, List<String>>{};
    final probes = <String, bool>{};
    Future<bool> probe(String path) async {
      cancellation.check();
      final key = _key(path);
      final cached = probes[key];
      if (cached != null) return cached;
      final result = await exists(path);
      cancellation.check();
      probes[key] = result;
      return result;
    }

    for (final source in sources) {
      if (source.options.includeInHealthCheck &&
          (!await probe(source.location) ||
              (sourceAvailable != null && !await sourceAvailable!(source)))) {
        offline.add(source.id);
      }
      cancellation.check();
    }
    var processed = 0;
    for (final item in inventory.items) {
      cancellation.check();
      // Metadata-only runs also yield; never monopolize the UI isolate.
      if (++processed % 128 == 0) await Future<void>.delayed(Duration.zero);
      final owner = byId[item.identity.sourceId];
      if (owner == null || !owner.options.includeInHealthCheck) continue;
      final path = itemPath(item, owner);
      if (!inside(path, owner.location)) continue;
      if (item.type == 'private' ||
          private.any((s) => inside(path, s.location)) ||
          excluded.any((s) => inside(path, s.location))) {
        continue;
      }
      final source = sources.where((s) => inside(path, s.location)).firstOrNull;
      if (source == null) continue;
      // Original file evaluator skips music and series without a file path;
      // photos are excluded from metadata gaps, not from missing-file checks.
      if (!item.isSeries && item.type != 'music' && !await probe(path)) {
        missing.add(item.identity);
        if (!offline.contains(source.id)) safe.add(item.identity);
      }
      // Music tag fields are not yet indexed; do not invent missing values.
      if (item.parentId != null ||
          item.type == 'music' ||
          item.type == 'photo' ||
          item.type == 'homeVideo' ||
          albums.any((s) => inside(path, s.location))) {
        continue;
      }
      final fields = <String>[
        if (item.posterPath == null) '封面',
        if (item.year == null) '年份',
        if (item.overview?.trim().isNotEmpty != true) '简介',
      ];
      if (fields.isNotEmpty) gaps[item.identity] = fields;
    }
    cancellation.check();
    return LibraryHealthSnapshot(
      inventory: inventory,
      missing: missing,
      safeMissing: safe,
      offline: offline,
      metadataGaps: gaps,
    );
  }
}
