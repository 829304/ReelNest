import '../../../domain/runtime_status.dart';
import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../health/domain/health_score.dart';

class HomeRuntimeHealth {
  const HomeRuntimeHealth({
    this.sourcePercent,
    this.metadataPercent,
    this.totalScore,
    this.partialIndex = false,
  });
  final int? sourcePercent, metadataPercent;
  final int? totalScore;
  final bool partialIndex;
  String get label => totalScore != null
      ? (partialIndex ? '已载入内容' : '健康度')
      : metadataPercent == null
      ? '待检测'
      : '基础检测';
}

abstract final class HomeRuntimePolicy {
  static bool visible(MediaSource source) =>
      source.mediaType != SourceMediaType.privateCollection;

  static bool? online(
    MediaSource source,
    Map<String, ReachabilityObservation> observations,
  ) {
    final value = observations[source.id];
    return value?.sourceKey == runtimeSourceKey(source) ? value?.online : null;
  }

  // HomeView.dashboardSourceHealthPercent, preserving the original penalties.
  static int sourceHealth(int total, int offline, int excluded) =>
      HealthScore.sourcePercent(total, offline, excluded);

  static int metadataHealth(int total, int issueCount) {
    return HealthScore.metadataPercent(total, issueCount);
  }

  static List<RuntimeTask> tasks(
    List<RuntimeTask> tasks,
    List<MediaSource> sources,
  ) {
    final byId = {for (final source in sources) source.id: source};
    final result = <RuntimeTask>[];
    for (final task in tasks) {
      final source = byId[task.sourceId];
      if (source == null) continue;
      final private = !visible(source) || task.hidesDetail;
      final kind = task.isCache
          ? '视频缓存'
          : source.kind.isRemoteVideoSource
          ? '${source.kind.label} 同步'
          : '完整扫描';
      result.add(
        RuntimeTask(
          id: task.id,
          group: task.group,
          sourceId: task.sourceId,
          title: private
              ? kind
              : task.isCache
              ? task.title
              : '$kind · ${source.name}',
          detail: private ? '任务正在后台处理。' : task.detail,
          stateTitle: task.stateTitle,
          active: task.active,
          startedAt: task.startedAt,
          finishedAt: task.finishedAt,
          progress: task.progress,
          isCache: task.isCache,
          hidesDetail: task.hidesDetail,
        ),
      );
    }
    result.sort((a, b) {
      final active = (b.active ? 1 : 0).compareTo(a.active ? 1 : 0);
      if (active != 0) return active;
      final date = b.sortDate.compareTo(a.sortDate);
      return date != 0 ? date : a.id.compareTo(b.id);
    });
    return result;
  }

  static int? basicMetadata(
    LibraryHealthSnapshot? snapshot,
    List<MediaSource> sources,
  ) {
    if (snapshot == null ||
        sources.isEmpty ||
        sources.any(
          (s) =>
              !s.kind.isFileSource ||
              s.mediaType == SourceMediaType.music ||
              s.mediaType == SourceMediaType.photo,
        )) {
      return null;
    }
    final checked = {for (final s in snapshot.inventory.sources) s.id: s};
    if (sources.any(
      (s) =>
          checked[s.id] == null ||
          runtimeSourceKey(checked[s.id]!) != runtimeSourceKey(s) ||
          checked[s.id]!.lastScan != s.lastScan,
    )) {
      return null;
    }
    final ids = sources
        .where((s) => s.options.includeInHealthCheck)
        .map((s) => s.id)
        .toSet();
    if (ids.isEmpty) return null;
    final total = snapshot.inventory.items
        .where(
          (item) =>
              ids.contains(item.identity.sourceId) &&
              item.parentId == null &&
              !{
                'music',
                'photo',
                'private',
                'privateCollection',
                'homeVideo',
              }.contains(item.type),
        )
        .length;
    if (total == 0) return null;
    return metadataHealth(
      total,
      snapshot.metadataGaps.keys
          .where((id) => ids.contains(id.sourceId))
          .length,
    );
  }
}
