import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/runtime_observations.dart';
import '../../sources/application/source_providers.dart';
import '../domain/home_runtime.dart';
import '../../../domain/source_media_type.dart';
import '../../health/domain/health_score.dart';

/// Never watch health/reachability futures here: observing the overview is not
/// permission to probe a NAS or authenticate every remote server.
final homeRuntimeHealthProvider = Provider<HomeRuntimeHealth>((ref) {
  final sources = (ref.watch(sidebarSourcesProvider).value ?? [])
      .where(HomeRuntimePolicy.visible)
      .toList();
  final reachability = ref.watch(observedReachabilityProvider);
  final checks = sources.where((s) => s.options.includeInHealthCheck).toList();
  final allKnown =
      sources.isNotEmpty &&
      checks.every((s) => HomeRuntimePolicy.online(s, reachability) != null);
  final health = ref.watch(observedHealthProvider);
  final revision = ref.watch(sourceChangesProvider).value ?? 0;
  final snapshot = health?.revision == revision ? health?.snapshot : null;
  final scope = sources
      .where(
        (s) => !{
          SourceMediaType.music,
          SourceMediaType.photo,
        }.contains(s.mediaType),
      )
      .toList();
  final checked = {for (final s in snapshot?.inventory.sources ?? []) s.id: s};
  final complete =
      snapshot?.evaluationComplete == true &&
      scope.isNotEmpty &&
      checked.length == scope.length &&
      scope.every(
        (s) =>
            checked[s.id] != null &&
            runtimeSourceKey(checked[s.id]!) == runtimeSourceKey(s) &&
            checked[s.id]!.lastScan == s.lastScan,
      );
  if (complete) {
    final scores = HealthScore.fromSnapshot(snapshot!);
    return HomeRuntimeHealth(
      sourcePercent: scores.source,
      metadataPercent: scores.metadata,
      totalScore: scores.overall,
      partialIndex: snapshot.partialIndex,
    );
  }
  return HomeRuntimeHealth(
    sourcePercent: allKnown
        ? HomeRuntimePolicy.sourceHealth(
            sources.length,
            checks
                .where(
                  (s) => HomeRuntimePolicy.online(s, reachability) == false,
                )
                .length,
            sources.length - checks.length,
          )
        : null,
    metadataPercent: HomeRuntimePolicy.basicMetadata(
      health?.revision == revision ? health?.snapshot : null,
      sources,
    ),
  );
});

final homeRuntimeTasksProvider = Provider<List<RuntimeTask>>(
  (ref) => HomeRuntimePolicy.tasks(
    ref.watch(observedTasksProvider),
    ref.watch(sidebarSourcesProvider).value ?? [],
  ),
);
