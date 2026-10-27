import 'dart:async';

import '../domain/media_source.dart';

/// Serializes operations; a failed operation does not poison later submissions.
class SerialTaskQueue {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Cancels waiting, not arbitrary work. The caller must pass cancellation to
/// the underlying operation or use onCancel to abort its owned child operation.
Future<T> awaitWithCancellation<T>(
  ScanCancellation? cancellation,
  Future<T> Function() work, {
  void Function()? onCancel,
}) async {
  if (cancellation == null) return work();
  cancellation.check();
  final cancelled = Completer<T>();
  final unlisten = cancellation.listen(() {
    onCancel?.call();
    cancelled.completeError(const ScanCancelled());
  });
  try {
    return await Future.any([Future.sync(work), cancelled.future]);
  } finally {
    unlisten();
  }
}
