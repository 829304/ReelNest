import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/player/coalesced_refresh.dart';

void main() {
  test('one event-turn burst uses one read', () async {
    var calls = 0;
    final refresh = CoalescedRefresh(() async {
      calls++;
    });
    await Future.wait(List.generate(100, (_) => refresh.request()));
    expect(calls, 1);
    await refresh.close();
  });

  test(
    'in-flight changes require a trailing read before controls return',
    () async {
      final started = Completer<void>(), gate = Completer<void>();
      var calls = 0, state = 1, published = 0;
      final refresh = CoalescedRefresh(() async {
        final captured = state;
        if (++calls == 1) {
          started.complete();
          await gate.future;
        }
        published = captured;
      });
      final first = refresh.request();
      await started.future;
      state = 2;
      var returned = false;
      final selection = refresh.request().then((_) {
        returned = true;
      });
      final burst = List.generate(100, (_) => refresh.request());
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
      gate.complete();
      await Future.wait([first, selection, ...burst]);
      expect(calls, 2);
      expect(published, 2);
      await refresh.close();
    },
  );

  test('failures reach callers and a subsequent request can recover', () async {
    var fail = true;
    final refresh = CoalescedRefresh(() async {
      if (fail) throw StateError('fixture');
    });
    await expectLater(refresh.request(), throwsStateError);
    fail = false;
    await refresh.request();
    await refresh.close();
  });

  test('close waits for the active read and discards pending work', () async {
    final started = Completer<void>(), gate = Completer<void>();
    var calls = 0;
    final refresh = CoalescedRefresh(() async {
      calls++;
      started.complete();
      await gate.future;
    });
    final first = refresh.request();
    await started.future;
    final trailing = refresh.request();
    var closed = false;
    final closing = refresh.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete();
    await Future.wait([first, trailing, closing]);
    await refresh.request();
    expect(calls, 1);
  });
}
