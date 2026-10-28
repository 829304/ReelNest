import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/playback_diagnostics.dart';
import '../../health/application/health_providers.dart';
import '../../sources/application/source_providers.dart';
import '../domain/metadata_supplement_state.dart';
import 'metadata_supplement_service.dart';
import 'tmdb_providers.dart';

export '../domain/metadata_supplement_state.dart';

final metadataSupplementServiceProvider = Provider<MetadataSupplementService>((
  ref,
) {
  final service = MetadataSupplementService(
    sources: ref.watch(sourceRepositoryProvider),
    settings: ref.watch(tmdbSettingsRepositoryProvider),
    movie: ref.watch(tmdbMovieServiceProvider),
    series: ref.watch(tmdbSeriesServiceProvider),
    loadCandidates: () async =>
        (await ref.read(libraryHealthProvider.future)).metadataGapItems,
    isScanning: () => ref.read(sourceScansProvider.notifier).isBusy,
    onState: (value) {
      if (ref.mounted) {
        ref.read(metadataSupplementProvider.notifier).publish(value);
      }
    },
    onFailure: (error, stack) => PlaybackDiagnostics().begin().failure(
      'metadata_supplement_failed',
      error,
      stack,
    ),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
final metadataSupplementProvider =
    NotifierProvider<MetadataSupplementController, MetadataSupplementState>(
      MetadataSupplementController.new,
    );

class MetadataSupplementController extends Notifier<MetadataSupplementState> {
  @override
  MetadataSupplementState build() => const MetadataSupplementState();
  void publish(MetadataSupplementState value) {
    if (ref.mounted) state = value;
  }

  Future<void> start() => ref.read(metadataSupplementServiceProvider).start();
  void cancel() => ref.read(metadataSupplementServiceProvider).cancel();
}
