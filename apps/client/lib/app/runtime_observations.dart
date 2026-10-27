import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/library_health.dart';
import '../domain/media_source.dart';
import '../domain/runtime_status.dart';

export '../domain/runtime_status.dart';

/// Passive observations only. Reading these providers must never start I/O.
final observedReachabilityProvider =
    NotifierProvider<
      ObservedReachability,
      Map<String, ReachabilityObservation>
    >(ObservedReachability.new);

class ObservedReachability
    extends Notifier<Map<String, ReachabilityObservation>> {
  @override
  Map<String, ReachabilityObservation> build() => {};
  void record(MediaSource source, bool online) => state = {
    ...state,
    source.id: (sourceKey: runtimeSourceKey(source), online: online),
  };

  void recordAll(Map<MediaSource, bool> values) => state = {
    ...state,
    for (final entry in values.entries)
      entry.key.id: (
        sourceKey: runtimeSourceKey(entry.key),
        online: entry.value,
      ),
  };
}

final observedHealthProvider =
    NotifierProvider<ObservedHealth, HealthObservation?>(ObservedHealth.new);

class ObservedHealth extends Notifier<HealthObservation?> {
  @override
  HealthObservation? build() => null;
  void record(LibraryHealthSnapshot snapshot, int revision) =>
      state = (snapshot: snapshot, revision: revision);
}

final observedTasksProvider =
    NotifierProvider<ObservedTasks, List<RuntimeTask>>(ObservedTasks.new);

final observedVideoCacheStorageProvider =
    NotifierProvider<ObservedVideoCacheStorage, VideoCacheStorageObservation?>(
      ObservedVideoCacheStorage.new,
    );

class ObservedVideoCacheStorage
    extends Notifier<VideoCacheStorageObservation?> {
  @override
  VideoCacheStorageObservation? build() => null;
  void record(VideoCacheStorageObservation value) => state = value;
}

class ObservedTasks extends Notifier<List<RuntimeTask>> {
  @override
  List<RuntimeTask> build() => const [];

  /// Replace one owner's snapshots, leaving the other task producers intact.
  /// A stable ID preserves start/finish time across progress notifications.
  void replace(String group, List<RuntimeTask> tasks) {
    final previous = {for (final task in state) task.id: task};
    final now = DateTime.now();
    state = [
      ...state.where((task) => task.group != group),
      for (final task in tasks)
        RuntimeTask(
          id: task.id,
          group: group,
          sourceId: task.sourceId,
          title: task.title,
          detail: task.detail,
          stateTitle: task.stateTitle,
          active: task.active,
          progress: task.progress,
          isCache: task.isCache,
          hidesDetail: task.hidesDetail,
          startedAt: previous[task.id]?.startedAt ?? task.startedAt,
          finishedAt: task.active ? null : previous[task.id]?.finishedAt ?? now,
        ),
    ];
  }
}
