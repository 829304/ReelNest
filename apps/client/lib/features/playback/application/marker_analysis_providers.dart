import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/runtime_observations.dart';
import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../data/marker_analysis_repository.dart';
import 'playback_marker_analysis_controller.dart';
import 'playback_providers.dart';

export '../domain/marker_analysis_task.dart';
export 'playback_marker_analysis_controller.dart';

final markerAnalysisRepositoryProvider = Provider<MarkerAnalysisRepository>(
  (ref) => MarkerAnalysisRepository(ref.watch(sourceRepositoryProvider)),
);
final markerAnalysisEligibilityProvider = FutureProvider.autoDispose
    .family<bool, MediaIdentity>((ref, root) {
      ref.watch(sourceChangesProvider);
      return ref.watch(markerAnalysisRepositoryProvider).canAnalyze(root);
    });
final markerAnalysisProvider = Provider<PlaybackMarkerAnalysisController>((
  ref,
) {
  final controller = PlaybackMarkerAnalysisController(
    ref.watch(markerAnalysisRepositoryProvider),
    onMarkersChanged: notifyPlayerMarkerChanges,
    onTasks: (tasks) {
      if (!ref.mounted) return;
      ref.read(observedTasksProvider.notifier).replace('markerAnalysis', [
        for (final task in tasks)
          RuntimeTask(
            id: task.id,
            group: 'markerAnalysis',
            sourceId: task.root.sourceId,
            title: task.title,
            detail: task.detail,
            stateTitle: task.stateTitle,
            active: task.active,
            startedAt: task.startedAt,
            finishedAt: task.finishedAt,
            progress: task.progress,
            hidesDetail: task.hidesDetail,
          ),
      ]);
    },
  );
  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});
