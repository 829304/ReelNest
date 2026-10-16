import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/app/window_close_request.dart';

void main() {
  test('native disappearance completes without a retired IPC reply', () async {
    final reply = Completer<Object?>();
    var exists = true;
    var calls = 0;
    final closing = requestChildWindowClose(
      request: () {
        calls++;
        return reply.future;
      },
      exists: () async => exists,
      pollInterval: const Duration(milliseconds: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    exists = false;
    expect(await closing.timeout(const Duration(milliseconds: 200)), isTrue);
    expect(reply.isCompleted, isFalse);
    expect(calls, 1);
    reply.completeError(StateError('Retired channel'));
    await Future<void>.delayed(Duration.zero);
  });
  test('save failure or user decision preserves the main window', () async {
    expect(
      await requestChildWindowClose(
        request: () async => false,
        exists: () async => true,
        pollInterval: const Duration(milliseconds: 1),
      ),
      isFalse,
    );
  });
  test('positive reply still waits for the child to disappear', () async {
    var probes = 0;
    expect(
      await requestChildWindowClose(
        request: () async => true,
        exists: () async => ++probes < 3,
        pollInterval: const Duration(milliseconds: 1),
      ),
      isTrue,
    );
    expect(probes, 3);
  });
  test('an unresponsive existing child is never forcibly destroyed', () async {
    final reply = Completer<Object?>();
    expect(
      await requestChildWindowClose(
        request: () => reply.future,
        exists: () async => true,
        budget: const Duration(milliseconds: 10),
        pollInterval: const Duration(milliseconds: 1),
      ),
      isFalse,
    );
    reply.complete(null);
  });
}
