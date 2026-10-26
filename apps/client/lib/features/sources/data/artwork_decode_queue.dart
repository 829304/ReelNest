import 'dart:async';
import 'dart:collection';

import '../../../domain/media_source.dart';

/// Original ArtworkDecodeCoordinator: FIFO permits, three native decodes.
class ArtworkDecodeQueue {
  ArtworkDecodeQueue({this.maximum = 3}) : assert(maximum > 0);
  final int maximum;
  int _active = 0;
  bool _closed = false;
  final _waiting = Queue<Completer<void>>();
  Future<T> run<T>(
    Future<T> Function() work, {
    ScanCancellation? cancellation,
  }) async {
    cancellation?.check();
    if (_closed) throw StateError('Artwork decoder closed');
    if (_active < maximum) {
      _active++;
    } else {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      final unlisten = cancellation?.listen(() {
        if (_waiting.remove(waiter)) {
          waiter.completeError(const ScanCancelled());
        }
      });
      try {
        await waiter.future;
      } finally {
        unlisten?.call();
      }
    }
    try {
      cancellation?.check();
      if (_closed) throw StateError('Artwork decoder closed');
      return await work();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }

  void dispose() {
    _closed = true;
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().completeError(
        StateError('Artwork decoder closed'),
      );
    }
  }
}
