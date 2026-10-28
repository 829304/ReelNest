import 'dart:async';

import 'package:path/path.dart' as p;

import '../../../domain/automatic_scan_interval.dart';
import '../../../domain/media_source.dart';
import '../../../sources/filesystem/local_file_monitor.dart';

typedef ScheduleSourceScan = Future<void> Function(
  String id, {
  Set<String>? paths,
});

/// AppState's automatic scan timer, longest-root routing and 1.2s event debounce.
/// Does not own a separate scanner: manual and automatic work share one queue.
class AutomaticSourceScanner {
  AutomaticSourceScanner({
    required this.sources,
    required this.isReachable,
    required this.schedule,
    required this.isBusy,
    required Stream<void> changes,
    required this.configurationRevision,
    required this.onError,
    FileChangeMonitorFactory? watch,
    this.debounce = const Duration(milliseconds: 1200),
  }) : watch = watch ?? LocalFileMonitor.start {
    _revision = configurationRevision();
    _changes = changes.listen((_) {
      final latest = configurationRevision();
      if (latest == _revision) return;
      _revision = latest;
      _generation++;
      unawaited(refreshSources());
    });
  }

  final Future<List<MediaSource>> Function() sources;
  final Future<bool> Function(MediaSource) isReachable;
  final ScheduleSourceScan schedule;
  final bool Function() isBusy;
  final int Function() configurationRevision;
  final void Function(Object, StackTrace) onError;
  final FileChangeMonitorFactory watch;
  final Duration debounce;
  late final StreamSubscription<void> _changes;
  final _monitors = <String, FileChangeMonitor>{};
  final _current = <String, MediaSource>{};
  final _pending = <String, Set<String>?>{};
  AutomaticScanInterval _interval = AutomaticScanInterval.disabled;
  Timer? _timer, _debounceTimer;
  int _revision = 0, _generation = 0;
  bool _closed = false, _refreshAgain = false, _ticking = false;
  Future<void>? _refreshWork;

  Future<void> setInterval(AutomaticScanInterval interval) async {
    if (_closed || interval == _interval) return;
    _interval = interval;
    _generation++;
    _timer?.cancel();
    _debounceTimer?.cancel();
    _pending.clear();
    final duration = interval.duration;
    if (duration != null) {
      // Original timer waits a complete interval before its first scan.
      _timer = Timer.periodic(duration, (_) => unawaited(tick()));
    }
    await refreshSources();
  }

  Future<void> refreshSources() {
    if (_closed) return Future.value();
    _refreshAgain = true;
    return _refreshWork ??= _refresh().whenComplete(() => _refreshWork = null);
  }

  Future<void> _refresh() async {
    try {
      while (_refreshAgain && !_closed) {
        _refreshAgain = false;
        final generation = _generation;
        final candidates = _interval.duration == null
            ? <MediaSource>[]
            : (await sources())
                  .where((s) => s.kind.isFileSource && s.options.autoScan)
                  .toList();
        if (_closed) return;
        if (generation != _generation) {
          _refreshAgain = true;
          continue;
        }
        final byID = {for (final source in candidates) source.id: source};
        for (final id in _current.keys.toList()) {
          final next = byID[id];
          if (next == null || _signature(next) != _signature(_current[id]!)) {
            await _monitors.remove(id)?.close();
            _current.remove(id);
            _pending.remove(id);
          }
        }
        for (final source in candidates) {
          try {
            final reachable = await isReachable(source);
            if (_closed) return;
            if (generation != _generation) {
              _refreshAgain = true;
              break;
            }
            if (!reachable) {
              await _monitors.remove(source.id)?.close();
              _current.remove(source.id);
              _pending.remove(source.id);
              continue;
            }
            _current[source.id] = source;
            final existing = _monitors[source.id];
            if (existing?.isActive == true) continue;
            await _monitors.remove(source.id)?.close();
            final monitor = await watch(source, receive);
            if (_closed || generation != _generation) {
              await monitor.close();
              _refreshAgain = !_closed;
              break;
            }
            _monitors[source.id] = monitor;
          } catch (error, stack) {
            // A platform watch limit or inaccessible folder must not prevent
            // other sources from being monitored. The timer still scans this
            // reachable root and retries its native monitor on the next tick.
            if (!_closed) onError(error, stack);
          }
        }
      }
    } catch (error, stack) {
      if (!_closed) onError(error, stack);
    }
  }

  String _signature(MediaSource s) =>
      '${s.location}|${s.recursive}|${s.ignoreHidden}|${s.accessIdentity}|${s.updatedAt.microsecondsSinceEpoch}';

  void receive(LocalFileChange change) {
    if (_closed || _interval.duration == null || !p.isAbsolute(change.path)) {
      return;
    }
    if (change.error != null) {
      onError(change.error!, change.stack ?? StackTrace.current);
    }
    final path = p.normalize(change.path);
    // Nested roots belong to the most specific source, as in AppState.
    final matching =
        _current.values
            .where(
              (s) => p.equals(path, s.location) || p.isWithin(s.location, path),
            )
            .toList()
          ..sort((a, b) => b.location.length.compareTo(a.location.length));
    if (matching.isEmpty) return;
    final source = matching.first;
    if (change.fullScan || p.equals(path, source.location)) {
      _pending[source.id] = null;
    } else if (!_pending.containsKey(source.id)) {
      _pending[source.id] = {path};
    } else {
      _pending[source.id]?.add(path);
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, flush);
  }

  void flush() {
    if (_closed || _interval.duration == null) return;
    final pending = Map<String, Set<String>?>.of(_pending);
    _pending.clear();
    for (final entry in pending.entries) {
      if (!_current.containsKey(entry.key)) continue;
      unawaited(
        schedule(entry.key, paths: entry.value).catchError((
          Object e,
          StackTrace s,
        ) {
          if (!_closed) onError(e, s);
        }),
      );
    }
  }

  /// Timer fallback also recovers watches after a disk/NAS is mounted again.
  Future<void> tick() async {
    if (_closed || _interval.duration == null || _ticking) return;
    _ticking = true;
    try {
      await refreshSources();
      if (_closed || _interval.duration == null || isBusy()) return;
      final futures = [
        for (final source in _current.values) schedule(source.id),
      ];
      await Future.wait(futures);
    } catch (error, stack) {
      if (!_closed) onError(error, stack);
    } finally {
      _ticking = false;
    }
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    _timer?.cancel();
    _debounceTimer?.cancel();
    _pending.clear();
    _current.clear();
    await _changes.cancel();
    final monitors = _monitors.values.toList();
    _monitors.clear();
    await Future.wait(monitors.map((monitor) => monitor.close()));
  }
}
