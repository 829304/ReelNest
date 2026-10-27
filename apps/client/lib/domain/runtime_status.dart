import 'dart:convert';

import 'library_health.dart';
import 'media_source.dart';

String runtimeSourceKey(MediaSource source) => jsonEncode([
  source.id,
  source.kind.name,
  source.location,
  source.accessIdentity,
  source.updatedAt.millisecondsSinceEpoch,
  source.mediaType.name,
  source.options.toJson(),
]);

typedef ReachabilityObservation = ({String sourceKey, bool online});
typedef HealthObservation = ({LibraryHealthSnapshot snapshot, int revision});
typedef VideoCacheStorageObservation = ({int count, int bytes, double limit});

class RuntimeTask {
  const RuntimeTask({
    required this.id,
    required this.group,
    required this.sourceId,
    required this.title,
    required this.detail,
    required this.stateTitle,
    required this.active,
    required this.startedAt,
    this.finishedAt,
    this.progress,
    this.isCache = false,
    this.hidesDetail = false,
  });
  final String id, group, sourceId, title, detail, stateTitle;
  final bool active, isCache, hidesDetail;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final double? progress;
  DateTime get sortDate => finishedAt ?? startedAt;
}
