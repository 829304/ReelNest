import 'dart:math' as math;

import '../../../domain/library_health.dart';
import '../../../domain/source_media_type.dart';

/// HomeView dashboard formulas; LibraryHealthCenterView intentionally has a
/// different aggregate formula. Do not substitute one for the other.
class HealthScore {
  const HealthScore(this.source, this.metadata, this.overall);
  final int source, metadata, overall;
  static int sourcePercent(int total, int offline, int excluded) =>
      (100 - math.min(offline, math.max(total, 1)) * 22 - excluded * 4).clamp(
        35,
        100,
      );
  static int metadataPercent(int total, int issues) {
    final ratio = (issues / math.max(total, 1) * 100).round();
    return (100 - math.min(55, math.max(ratio, math.min(issues, 12) * 3)))
        .clamp(45, 100)
        .toInt();
  }

  static HealthScore fromSnapshot(LibraryHealthSnapshot value) {
    final sources = value.inventory.sources
        .where((s) => s.mediaType != SourceMediaType.privateCollection)
        .toList();
    final publicIDs = sources.map((s) => s.id).toSet();
    final total = value.inventory.items
        .where(
          (item) =>
              item.parentId == null &&
              item.type != 'episode' &&
              publicIDs.contains(item.identity.sourceId),
        )
        .length;
    final source = sourcePercent(
      sources.length,
      value.offline.where(publicIDs.contains).length,
      sources.where((s) => !s.options.includeInHealthCheck).length,
    );
    final metadata = metadataPercent(
      total,
      value.metadataGaps.length +
          value.detailGaps.length +
          value.unhealthyURLs.length,
    );
    final overall =
        ((source * .55 + metadata * .45).round() -
                math.min(value.missing.length + value.duplicates.length, 8) * 2)
            .clamp(42, 100);
    return HealthScore(source, metadata, overall);
  }

  static int dashboardHealth(LibraryHealthSnapshot value) =>
      100 -
      math.min(
        (value.offline.length +
                value.missing.length +
                value.duplicates.length +
                value.metadataGaps.length +
                value.detailGaps.length +
                value.unhealthyURLs.length) *
            7,
        82,
      );
  static int dashboardMetadata(LibraryHealthSnapshot value) =>
      100 -
      math.min((value.metadataGaps.length + value.detailGaps.length) * 6, 80);
}
