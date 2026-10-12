import 'dart:convert';

import 'media_source.dart';

HealthIssueKey duplicateIssueKey(List<IndexedMedia> group) {
  final identities =
      group
          .map((item) => [item.identity.sourceId, item.identity.localId])
          .toList()
        ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  return (
    kind: HealthIssueKind.duplicateGroup,
    sourceId: '',
    localId: jsonEncode(identities),
  );
}

typedef LibraryInventory = ({
  List<MediaSource> sources,
  List<IndexedMedia> items,
});

enum HealthIssueKind {
  missingFile('missing-file'),
  missingMetadata('missing-metadata'),
  detailMetadata('detail-metadata'),
  duplicateGroup('duplicate-group'),
  unhealthyURL('unhealthy-url'),
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
    Map<MediaIdentity, List<String>> detailGaps = const {},
    List<List<IndexedMedia>> duplicates = const [],
    Map<MediaIdentity, String> unhealthyURLs = const {},
    this.evaluationComplete = false,
    this.partialIndex = false,
    List<MediaSource>? configurationSources,
  }) : configurationSources = List.unmodifiable(
         configurationSources ?? inventory.sources,
       ),
       missing = Set.unmodifiable(missing),
       safeMissing = Set.unmodifiable(safeMissing),
       offline = Set.unmodifiable(offline),
       metadataGaps = Map.unmodifiable(
         metadataGaps.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
         ),
       ),
       detailGaps = Map.unmodifiable(
         detailGaps.map(
           (id, fields) => MapEntry(id, List<String>.unmodifiable(fields)),
         ),
       ),
       duplicates = List.unmodifiable(
         duplicates.map((group) => List<IndexedMedia>.unmodifiable(group)),
       ),
       unhealthyURLs = Map.unmodifiable(unhealthyURLs),
       localSources = List.unmodifiable(
         inventory.sources.where((s) => s.kind.isFileSource),
       ),
       missingItems = List.unmodifiable(
         inventory.items.where((item) => missing.contains(item.identity)),
       ),
       detailGapItems = List.unmodifiable(
         inventory.items.where((item) => detailGaps.containsKey(item.identity)),
       ),
       duplicateRows = _duplicateRows(duplicates),
       metadataGapItems = List.unmodifiable(
         inventory.items.where(
           (item) => metadataGaps.containsKey(item.identity),
         ),
       );
  final LibraryInventory inventory;

  /// Original complete configuration, retained for cleanup revalidation even
  /// when the score deliberately scopes out music/photos/private libraries.
  final List<MediaSource> configurationSources;
  final Set<MediaIdentity> missing;

  /// A detection result, never authorization to delete files or stale indexes.
  final Set<MediaIdentity> safeMissing;
  final Set<String> offline;
  final Map<MediaIdentity, List<String>> metadataGaps;
  final Map<MediaIdentity, List<String>> detailGaps;
  final List<List<IndexedMedia>> duplicates;
  final Map<MediaIdentity, String> unhealthyURLs;
  final bool evaluationComplete, partialIndex;
  // Derived once per refresh, never by the widget render path.
  final List<MediaSource> localSources;
  final List<IndexedMedia> missingItems;
  final List<IndexedMedia> metadataGapItems;
  final List<IndexedMedia> detailGapItems;
  final List<({IndexedMedia item, List<IndexedMedia> group, bool header})>
  duplicateRows;

  static List<({IndexedMedia item, List<IndexedMedia> group, bool header})>
  _duplicateRows(List<List<IndexedMedia>> groups) => List.unmodifiable([
    for (final input in groups.where((group) => group.length > 1))
      ..._groupRows(List<IndexedMedia>.unmodifiable(input)),
  ]);

  static Iterable<({IndexedMedia item, List<IndexedMedia> group, bool header})>
  _groupRows(List<IndexedMedia> group) sync* {
    yield (item: group.first, group: group, header: true);
    for (final item in group) {
      yield (item: item, group: group, header: false);
    }
  }

  LibraryHealthSnapshot excluding(Set<HealthIssueKey> ignored) =>
      LibraryHealthSnapshot(
        inventory: inventory,
        configurationSources: configurationSources,
        evaluationComplete: evaluationComplete,
        partialIndex: partialIndex,
        detailGaps: Map.fromEntries(
          detailGaps.entries.where(
            (entry) => !ignored.contains((
              kind: HealthIssueKind.detailMetadata,
              sourceId: entry.key.sourceId,
              localId: entry.key.localId,
            )),
          ),
        ),
        duplicates: duplicates
            .where((group) => !ignored.contains(duplicateIssueKey(group)))
            .toList(),
        unhealthyURLs: Map.fromEntries(
          unhealthyURLs.entries.where(
            (entry) => !ignored.contains((
              kind: HealthIssueKind.unhealthyURL,
              sourceId: entry.key.sourceId,
              localId: entry.key.localId,
            )),
          ),
        ),
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
