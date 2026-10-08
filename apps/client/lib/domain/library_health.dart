import 'media_source.dart';

typedef LibraryInventory = ({
  List<MediaSource> sources,
  List<IndexedMedia> items,
});

enum HealthIssueKind {
  missingFile('missing-file'),
  missingMetadata('missing-metadata'),
  offlineSource('offline-source');

  const HealthIssueKind(this.storageValue);
  final String storageValue;
}

/// Composite identities keep equal relative paths on different sources apart.
typedef HealthIssueKey = ({
  HealthIssueKind kind,
  String sourceId,
  String localId,
});

class LibraryHealthSnapshot {
  LibraryHealthSnapshot({
    required this.inventory,
    required Set<MediaIdentity> missing,
    required Set<MediaIdentity> safeMissing,
    required Set<String> offline,
    required Map<MediaIdentity, List<String>> metadataGaps,
  }) : missing = Set.unmodifiable(missing),
       safeMissing = Set.unmodifiable(safeMissing),
       offline = Set.unmodifiable(offline),
       metadataGaps = Map.unmodifiable(
         metadataGaps.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       ),
       localSources = List.unmodifiable(
         inventory.sources.where((s) => s.kind.isFileSource),
       ),
       missingItems = List.unmodifiable(
         inventory.items.where((item) => missing.contains(item.identity)),
       ),
       metadataGapItems = List.unmodifiable(
         inventory.items.where(
           (item) => metadataGaps.containsKey(item.identity),
         ),
       );
  final LibraryInventory inventory;
  final Set<MediaIdentity> missing;

  /// A detection result, never authorization to delete files or stale indexes.
  final Set<MediaIdentity> safeMissing;
  final Set<String> offline;
  final Map<MediaIdentity, List<String>> metadataGaps;
  // Derived once per refresh, never by the widget render path.
  final List<MediaSource> localSources;
  final List<IndexedMedia> missingItems;
  final List<IndexedMedia> metadataGapItems;

  LibraryHealthSnapshot excluding(Set<HealthIssueKey> ignored) =>
      LibraryHealthSnapshot(
        inventory: inventory,
        missing: missing
            .where(
              (id) => !ignored.contains((
                kind: HealthIssueKind.missingFile,
                sourceId: id.sourceId,
                localId: id.localId,
              )),
            )
            .toSet(),
        safeMissing: safeMissing
            .where(
              (id) => !ignored.contains((
                kind: HealthIssueKind.missingFile,
                sourceId: id.sourceId,
                localId: id.localId,
              )),
            )
            .toSet(),
        offline: offline
            .where(
              (id) => !ignored.contains((
                kind: HealthIssueKind.offlineSource,
                sourceId: id,
                localId: '',
              )),
            )
            .toSet(),
        metadataGaps: Map.fromEntries(
          metadataGaps.entries.where(
            (entry) => !ignored.contains((
              kind: HealthIssueKind.missingMetadata,
              sourceId: entry.key.sourceId,
              localId: entry.key.localId,
            )),
          ),
        ),
      );
}
