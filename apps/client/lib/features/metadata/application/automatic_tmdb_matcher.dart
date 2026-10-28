import 'dart:async';

import '../../../application/async_tasks.dart';
import '../../../domain/automatic_scan_interval.dart';
import '../../../domain/media_source.dart';

/// AppState.configureAutomaticTMDBMatch: no immediate run; busy ticks are
/// skipped rather than queued. The batch service owns candidate/credential checks.
class AutomaticTmdbMatcher {
  AutomaticTmdbMatcher({
    required this.run,
    required this.isMatching,
    required this.isScanning,
    required this.onError,
  });
  final Future<void> Function(ScanCancellation) run;
  final bool Function() isMatching, isScanning;
  final void Function(Object, StackTrace) onError;
  AutomaticScanInterval _interval = AutomaticScanInterval.disabled;
  Timer? _timer;
  ScanCancellation? _token;
  Future<void>? _pending;
  bool _closed = false;

  void setInterval(AutomaticScanInterval value) {
    if (_closed || value == _interval) return;
    _interval = value;
    _timer?.cancel();
    _timer = null;
    final duration = value.duration;
    if (duration == null) {
      // Cancel only a run started here, never a manual batch sharing the service.
      _token?.cancel();
    } else {
      _timer = Timer.periodic(duration, (_) => unawaited(tick()));
    }
  }

  Future<void> tick() {
    if (_closed ||
        _interval.duration == null ||
        _pending != null ||
        isMatching() ||
        isScanning()) {
      return Future.value();
    }
    final token = ScanCancellation();
    _token = token;
    return _pending = _run(token).whenComplete(() {
      if (identical(_token, token)) _token = null;
      _pending = null;
    });
  }

  Future<void> _run(ScanCancellation token) async {
    try {
      await awaitWithCancellation(token, () => run(token));
    } on ScanCancelled {
      // Disabling the cycle and app shutdown are ordinary cancellation.
    } catch (error, stack) {
      if (!_closed) onError(error, stack);
    }
  }

  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _token?.cancel();
    await _pending;
  }
}
