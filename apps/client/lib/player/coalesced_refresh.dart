import 'dart:async';

/// Collapse a burst into one read, plus one trailing read if state changes
/// during an in-flight read. Each caller waits for a read that began after its
/// request, so explicit track selection cannot return an earlier snapshot.
class CoalescedRefresh {
  CoalescedRefresh(this.read);
  final Future<void> Function() read;
  Future<void>? _running;
  bool _dirty = false;
  bool _closed = false;

  Future<void> request() {
    if (_closed) return Future.value();
    _dirty = true;
    if (_running != null) return _running!;
    final done = Completer<void>();
    _running = done.future;
    // Defer the first read so events in the same turn share its snapshot.
    scheduleMicrotask(() async {
      Object? failure;
      StackTrace? stack;
      while (_dirty && !_closed) {
        _dirty = false;
        try {
          await read();
          failure = null;
          stack = null;
        } catch (error, trace) {
          failure = error;
          stack = trace;
        }
      }
      _running = null;
      if (failure == null) {
        done.complete();
      } else {
        done.completeError(failure, stack);
      }
    });
    return done.future;
  }

  Future<void> close() async {
    _closed = true;
    _dirty = false;
    try {
      await _running;
    } catch (_) {
      // Callers retain the read failure; disposal still releases the engine.
    }
  }
}
