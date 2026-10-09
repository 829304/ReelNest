import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../data/health_repository.dart';
import '../domain/local_health_evaluator.dart';
import 'missing_index_cleanup.dart';

final missingIndexCleanupProvider = Provider<MissingIndexCleanup>(
  (ref) => MissingIndexCleanup(ref.watch(sourceRepositoryProvider)),
);

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  final repository = HealthRepository(
    ref.watch(sourceRepositoryProvider).database,
  );
  ref.onDispose(() => unawaited(repository.close()));
  return repository;
});
final localHealthEvaluatorProvider = Provider<LocalHealthEvaluator>(
  (ref) => LocalHealthEvaluator(
    paths: p.context,
    exists: (path) async =>
        await FileSystemEntity.type(path) != FileSystemEntityType.notFound,
    sourceAvailable: ref.watch(sourceRepositoryProvider).isSafeDirectory,
  ),
);

final rawLibraryHealthProvider = FutureProvider<LibraryHealthSnapshot>((
  ref,
) async {
  final repository = ref.watch(sourceRepositoryProvider);
  final evaluator = ref.watch(localHealthEvaluatorProvider);
  final cancellation = ScanCancellation();
  // Library reloads (including save/delete/relocate/scan completion) retire old
  // results. A disposed generation cannot publish even if NAS I/O finishes late.
  final changes = repository.changes.listen((_) {
    cancellation.cancel();
    ref.invalidateSelf();
  });
  ref.onDispose(() {
    cancellation.cancel();
    unawaited(changes.cancel());
  });
  final inventory = await repository.inventory();
  cancellation.check();
  return evaluator.evaluate(inventory, cancellation: cancellation);
});

final ignoredHealthIssuesProvider = FutureProvider<Set<HealthIssueKey>>((ref) {
  final repository = ref.watch(healthRepositoryProvider);
  final changes = repository.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(changes.cancel()));
  return repository.ignored();
});

final libraryHealthProvider = FutureProvider<LibraryHealthSnapshot>((
  ref,
) async {
  final raw = ref.watch(rawLibraryHealthProvider.future);
  final ignored = ref.watch(ignoredHealthIssuesProvider.future);
  // Attach error handlers to both futures immediately: a settings read can
  // fail while a slow NAS probe is still pending.
  final results = await Future.wait<Object>([raw, ignored], eagerError: true);
  return (results[0] as LibraryHealthSnapshot).excluding(
    results[1] as Set<HealthIssueKey>,
  );
});
