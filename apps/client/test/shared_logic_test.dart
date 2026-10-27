import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/application/async_tasks.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/preference_store.dart';

void main() {
  test(
    'raw preferences preserve empty/whitespace, delete null and roll back',
    () async {
      final db = LibraryDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.writePreference('key', ' ');
      expect(await db.preferenceValue('key'), ' ');
      await db.writePreference('key', '');
      expect(await db.preferenceValue('key'), '');
      await expectLater(
        db.transaction(() async {
          await db.writePreference('key', 'replacement');
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await db.preferenceValue('key'), '');
      await db.writePreference('key', null);
      expect(await db.preferenceValue('key'), isNull);
    },
  );

  test('serialized work preserves order and continues after failure', () async {
    final queue = SerialTaskQueue();
    final gate = Completer<void>();
    final order = <int>[];
    final first = queue.run(() async {
      order.add(1);
      await gate.future;
      throw StateError('first');
    });
    final failure = expectLater(first, throwsStateError);
    final second = queue.run(() async {
      order.add(2);
      return 42;
    });
    await Future<void>.delayed(Duration.zero);
    expect(order, [1]);
    gate.complete();
    await failure;
    expect(await second, 42);
    expect(order, [1, 2]);
  });

  test(
    'cancel before start, cancel active work, and detach completed listeners',
    () async {
      final cancelled = ScanCancellation()..cancel();
      var started = false;
      await expectLater(
        awaitWithCancellation(cancelled, () async {
          started = true;
        }),
        throwsA(isA<ScanCancelled>()),
      );
      expect(started, isFalse);
      final token = ScanCancellation();
      final gate = Completer<int>();
      var aborted = 0;
      final result = awaitWithCancellation(
        token,
        () => gate.future,
        onCancel: () => aborted++,
      );
      final check = expectLater(result, throwsA(isA<ScanCancelled>()));
      token.cancel();
      await check;
      expect(aborted, 1);
      gate.completeError(StateError('late failure'));
      await Future<void>.delayed(Duration.zero);
      final complete = ScanCancellation();
      expect(
        await awaitWithCancellation(
          complete,
          () async => 3,
          onCancel: () => aborted++,
        ),
        3,
      );
      complete.cancel();
      expect(aborted, 1);
      await expectLater(
        awaitWithCancellation(
          ScanCancellation(),
          () => throw StateError('sync'),
        ),
        throwsStateError,
      );
    },
  );
}
