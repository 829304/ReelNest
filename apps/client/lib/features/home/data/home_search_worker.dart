import 'dart:async';
import 'dart:isolate';

import '../../../domain/media_source.dart';

/// Superseded keystrokes must stop consuming CPU as well as lose permission to
/// publish. A worker owns only immutable snapshot data, never the live database.
Future<T> runHomeSearchWorker<T>(
  T Function() work,
  ScanCancellation cancellation,
) async {
  cancellation.check();
  final output = ReceivePort();
  final done = Completer<T>();
  // A spawn failure/cancellation can arrive before the await below is reached.
  unawaited(
    done.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  );
  final subscription = output.listen((message) {
    if (done.isCompleted) return;
    if (message is (bool, Object?)) {
      done.complete(message.$2 as T);
    } else if (message is List && message.length == 2) {
      done.completeError(RemoteError('${message[0]}', '${message[1]}'));
    } else {
      done.completeError(const SourceFailure('搜索任务意外结束，请重试。'));
    }
  });
  Isolate? worker;
  void Function()? unlisten;
  try {
    worker = await Isolate.spawn(
      _run<T>,
      (output.sendPort, work),
      onError: output.sendPort,
      onExit: output.sendPort,
    );
    unlisten = cancellation.listen(() {
      worker?.kill(priority: Isolate.immediate);
      if (!done.isCompleted) done.completeError(const ScanCancelled());
    });
    final value = await done.future;
    cancellation.check();
    return value;
  } finally {
    unlisten?.call();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    output.close();
  }
}

void _run<T>((SendPort, T Function()) request) =>
    Isolate.exit(request.$1, (true, request.$2()));
