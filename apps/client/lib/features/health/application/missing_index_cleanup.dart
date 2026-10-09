import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../../platform/directory_safety.dart';
import '../../sources/data/source_repository.dart';
import '../domain/local_health_evaluator.dart';

class MissingIndexCleanup {
  MissingIndexCleanup(
    this.repository, {
    this.missingProbe = fileDefinitelyMissing,
  });
  final SourceRepository repository;
  final Future<bool> Function(String root, String path) missingProbe;

  Future<({int removed, int retained})> remove(
    LibraryHealthSnapshot displayed,
    Set<MediaIdentity> requested,
  ) => repository.removeRevalidatedMissing(requested, (inventory) async {
    // A confirmation for the old location/settings cannot authorize a new one.
    if (_sourcesKey(inventory.sources) !=
        _sourcesKey(displayed.inventory.sources)) {
      throw const SourceFailure('媒体源状态已变化，请重新检测后再清理。');
    }
    final evaluator = LocalHealthEvaluator(
      paths: p.context,
      exists: (path) async =>
          await FileSystemEntity.type(path) != FileSystemEntityType.notFound,
      sourceAvailable: repository.isSafeDirectory,
    );
    final wanted = requested.intersection(displayed.safeMissing);
    final selected = inventory.items
        .where((item) => wanted.contains(item.identity))
        .toList();
    final fresh = await evaluator.evaluate((
      sources: inventory.sources,
      items: selected,
    ), cancellation: ScanCancellation());
    final sources =
        inventory.sources.where((source) => source.kind.isFileSource).toList()
          ..sort((a, b) => b.location.length.compareTo(a.location.length));
    final previous = {
      for (final item in displayed.inventory.items) item.identity: item,
    };
    final safe = <MediaIdentity>{};
    final usedSources = <String, MediaSource>{};
    for (final item in selected) {
      if (!fresh.safeMissing.contains(item.identity) || item.isSeries) continue;
      final old = previous[item.identity];
      if (old == null || _itemKey(old) != _itemKey(item)) continue;
      final owner = sources
          .where((s) => s.id == item.identity.sourceId)
          .firstOrNull;
      if (owner == null || !await repository.isSafeDirectory(owner)) continue;
      final path = evaluator.itemPath(item, owner);
      final nearest = sources
          .where((s) => evaluator.inside(path, s.location))
          .firstOrNull;
      if (nearest == null || !await repository.isSafeDirectory(nearest)) {
        continue;
      }
      try {
        if (await missingProbe(nearest.location, path)) {
          safe.add(item.identity);
          usedSources[owner.id] = owner;
          usedSources[nearest.id] = nearest;
        }
      } on FileSystemException {
        // A denied parent listing is not proof of absence.
      }
    }
    // Retire all candidates if a used mount changes during the file probes.
    for (final source in usedSources.values) {
      if (!await repository.isSafeDirectory(source)) return <MediaIdentity>{};
    }
    return safe;
  });

  String _sourcesKey(List<MediaSource> sources) {
    final sorted = sources.toList()..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode(
      sorted
          .map(
            (s) => [
              s.id,
              s.kind.name,
              s.location,
              s.accessIdentity,
              s.updatedAt.millisecondsSinceEpoch,
              s.mediaType.storageValue,
              s.recursive,
              s.ignoreHidden,
              s.minimumFileSize,
              s.options.toJson(),
            ],
          )
          .toList(),
    );
  }

  String _itemKey(IndexedMedia item) => jsonEncode([
    item.type,
    item.bytes,
    item.modified.millisecondsSinceEpoch,
    item.isSeries,
    item.parentId,
    item.seriesDirectory,
    item.title,
    item.year,
    item.seasonNumber,
    item.episodeNumber,
    item.originalTitle,
    item.overview,
    item.posterPath,
    item.backdropPath,
  ]);
}
