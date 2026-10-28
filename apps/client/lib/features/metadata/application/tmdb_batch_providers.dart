import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/playback_diagnostics.dart';

import '../domain/tmdb_batch_state.dart';
import '../../sources/application/source_providers.dart';
import 'tmdb_batch_service.dart';
import 'tmdb_providers.dart';

export '../domain/tmdb_batch_state.dart';

final tmdbBatchServiceProvider = Provider<TmdbBatchService>((ref) {
  final scans = ref.read(sourceScansProvider.notifier);
  final service = TmdbBatchService(
    sources: ref.watch(sourceRepositoryProvider),
    settings: ref.watch(tmdbSettingsRepositoryProvider),
    series: ref.watch(tmdbSeriesServiceProvider),
    isScanning: () => scans.isBusy,
    onFailure: (stage, error, stack) =>
        PlaybackDiagnostics().begin().failure(stage, error, stack),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
final tmdbBatchProvider = NotifierProvider<TmdbBatchController, TmdbBatchState>(
  TmdbBatchController.new,
);

class TmdbBatchController extends Notifier<TmdbBatchState> {
  @override
  TmdbBatchState build() {
    final service = ref.read(tmdbBatchServiceProvider);
    void changed() {
      if (ref.mounted) state = service.state.value;
    }

    service.state.addListener(changed);
    ref.onDispose(() => service.state.removeListener(changed));
    return service.state.value;
  }

  Future<void> start() => ref.read(tmdbBatchServiceProvider).start();
  void cancel() => ref.read(tmdbBatchServiceProvider).cancel();
}
