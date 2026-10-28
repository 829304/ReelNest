import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/async_tasks.dart';
import '../../../domain/automatic_scan_interval.dart';
import '../../../player/playback_diagnostics.dart';
import '../../../storage/preference_store.dart';
import 'automatic_source_scanner.dart';
import 'source_providers.dart';

final automaticSourceScannerProvider = Provider<AutomaticSourceScanner>((ref) {
  final repository = ref.watch(sourceRepositoryProvider);
  final scans = ref.read(sourceScansProvider.notifier);
  final scanner = AutomaticSourceScanner(
    sources: () => repository.sources(includeCounts: false),
    isReachable: repository.isReachable,
    schedule: scans.scanChanges,
    isBusy: () => scans.isBusy,
    changes: repository.changes,
    configurationRevision: () => repository.configurationRevision,
    onError: (error, stack) => PlaybackDiagnostics().begin().failure(
      'automatic_source_monitor_failed',
      error,
      stack,
    ),
  );
  ref.onDispose(() => unawaited(scanner.dispose()));
  return scanner;
});

final automaticScanIntervalProvider =
    NotifierProvider<AutomaticScanSettings, AutomaticScanInterval>(
      AutomaticScanSettings.new,
    );

class AutomaticScanSettings extends Notifier<AutomaticScanInterval> {
  static const preferenceKey = 'automaticScanInterval';
  final _operations = SerialTaskQueue();

  @override
  AutomaticScanInterval build() {
    // Reading settings is asynchronous and never delays the first paint. The
    // disabled default performs no directory discovery and installs no timer.
    unawaited(
      _operations.run(() async {
        try {
          final value = await ref
              .read(sourceRepositoryProvider)
              .database
              .preferenceValue(preferenceKey);
          if (!ref.mounted) return;
          state = AutomaticScanInterval.parse(value);
          await ref.read(automaticSourceScannerProvider).setInterval(state);
        } catch (error, stack) {
          if (ref.mounted) {
            PlaybackDiagnostics().begin().failure(
              'automatic_scan_settings_load_failed',
              error,
              stack,
            );
          }
        }
      }),
    );
    return AutomaticScanInterval.disabled;
  }

  Future<void> setInterval(AutomaticScanInterval value) =>
      _operations.run(() async {
        if (!ref.mounted) return;
        await ref
            .read(sourceRepositoryProvider)
            .database
            .writePreference(preferenceKey, value.name);
        if (!ref.mounted) return;
        state = value;
        await ref.read(automaticSourceScannerProvider).setInterval(value);
      });
}
