import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../../domain/app_failure.dart';
import '../../servers/data/server_repository.dart';

/// Session-scoped byte cache. Neither tokens nor authenticated URLs are keys.
class ArtworkRepository {
  ArtworkRepository(this._server, this._scope);
  final ServerRepository _server;
  final int _scope;
  final _cache = <String, Uint8List>{};
  final _inFlight = <String, Future<Uint8List>>{};
  final _queue = Queue<({String id, Completer<Uint8List> result})>();
  int _cacheBytes = 0;
  int _active = 0;
  bool _closed = false;

  Future<Uint8List> load(String id) {
    if (_closed || _scope != _server.generation) {
      return Future.error(AppFailure.sessionExpired);
    }
    final cached = _cache.remove(id);
    if (cached != null) {
      _cache[id] = cached;
      return Future.value(cached);
    }
    if (_inFlight[id] case final pending?) return pending;
    final result = Completer<Uint8List>();
    late final Future<Uint8List> future;
    future = result.future.whenComplete(() {
      if (identical(_inFlight[id], future)) _inFlight.remove(id);
    });
    _inFlight[id] = future;
    _queue.add((id: id, result: result));
    _drain();
    return future;
  }

  void evict(String id) {
    final value = _cache.remove(id);
    if (value != null) _cacheBytes -= value.length;
  }

  void cancelQueued(String id) {
    final jobs = _queue.where((job) => job.id == id).toList();
    _queue.removeWhere((job) => job.id == id);
    if (jobs.isEmpty) {
      return; // A sent request may still fill this session's cache.
    }
    _inFlight.remove(id);
    for (final job in jobs) {
      job.result.completeError(
        const AppFailure(FailureKind.cancelled, '图片请求已取消。'),
      );
    }
  }

  void _drain() {
    while (!_closed && _active < 4 && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _active++;
      unawaited(_run(job.id, job.result));
    }
  }

  Future<void> _run(String id, Completer<Uint8List> result) async {
    try {
      final bytes = await _server.artwork(_scope, id);
      if (_closed || _scope != _server.generation) {
        throw AppFailure.sessionExpired;
      }
      evict(id);
      _cache[id] = bytes;
      _cacheBytes += bytes.length;
      while (_cacheBytes > 16 * 1024 * 1024 || _cache.length > 64) {
        evict(_cache.keys.first);
      }
      result.complete(bytes);
    } catch (error) {
      result.completeError(AppFailure.from(error));
    } finally {
      _active--;
      _drain();
    }
  }

  void dispose() {
    _closed = true;
    _cache.clear();
    _cacheBytes = 0;
    while (_queue.isNotEmpty) {
      _queue.removeFirst().result.completeError(AppFailure.sessionExpired);
    }
  }
}
