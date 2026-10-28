import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/playback_diagnostics.dart';
import '../../sources/application/source_providers.dart';
import '../domain/tmdb_models.dart';
import 'automatic_tmdb_matcher.dart';
import 'tmdb_batch_providers.dart';
import 'tmdb_providers.dart';

final automaticTmdbMatcherProvider = Provider<AutomaticTmdbMatcher>((ref) {
  final matcher = AutomaticTmdbMatcher(
    // Do not instantiate unused batch/HTTP services when the default is off.
    run: (token) => ref.read(tmdbBatchServiceProvider).startAutomatic(token),
    isMatching: () =>
        ref.exists(tmdbBatchServiceProvider) &&
        ref.read(tmdbBatchServiceProvider).isRunning,
    isScanning: () => ref.read(sourceScansProvider.notifier).isBusy,
    onError: (error, stack) => PlaybackDiagnostics().begin().failure(
      'automatic_tmdb_match_failed',
      error,
      stack,
    ),
  );
  ref.listen<AsyncValue<TmdbSettings>>(tmdbSettingsProvider, (_, next) {
    final settings = next.value;
    if (settings != null) matcher.setInterval(settings.automaticMatchInterval);
  }, fireImmediately: true);
  ref.onDispose(() => unawaited(matcher.dispose()));
  return matcher;
});
