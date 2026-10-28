import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/metadata/application/automatic_tmdb_matcher.dart';

void main() {
  AutomaticTmdbMatcher create({
    required Future<void> Function(ScanCancellation) run,
    bool Function()? matching,
    bool Function()? scanning,
    void Function(Object, StackTrace)? onError,
  }) => AutomaticTmdbMatcher(
    run: run,
    isMatching: matching ?? () => false,
    isScanning: scanning ?? () => false,
    onError: onError ?? (error, stack) => fail('$error'),
  );

  testWidgets('disabled scheduler never starts background work', (
    tester,
  ) async {
    var runs = 0;
    final matcher = create(
      run: (_) async {
        runs++;
      },
    );
    try {
      await tester.pump(const Duration(days: 3));
      await matcher.tick();
      expect(runs, 0);
    } finally {
      await matcher.dispose();
    }
  });
  for (final interval in AutomaticScanInterval.values.where(
    (e) => e.duration != null,
  )) {
    testWidgets(
      '${interval.name} waits one complete interval before its first run',
      (tester) async {
        var runs = 0;
        final matcher = create(
          run: (_) async {
            runs++;
          },
        );
        try {
          matcher.setInterval(interval);
          expect(runs, 0);
          await tester.pump(
            interval.duration! - const Duration(milliseconds: 1),
          );
          expect(runs, 0);
          await tester.pump(const Duration(milliseconds: 1));
          expect(runs, 1);
          await tester.pump(interval.duration!);
          expect(runs, 2);
        } finally {
          await matcher.dispose();
        }
      },
    );
  }
  testWidgets(
    'busy scans and manual matches skip a tick without queuing a catch-up',
    (tester) async {
      var scanning = true, matching = false, runs = 0;
      final matcher = create(
        run: (_) async {
          runs++;
        },
        matching: () => matching,
        scanning: () => scanning,
      );
      try {
        matcher.setInterval(AutomaticScanInterval.fifteenMinutes);
        await tester.pump(const Duration(minutes: 15));
        expect(runs, 0);
        scanning = false;
        matching = true;
        await tester.pump(const Duration(minutes: 15));
        expect(runs, 0);
        matching = false;
        await tester.pump(const Duration(minutes: 14));
        expect(runs, 0);
        await tester.pump(const Duration(minutes: 1));
        expect(runs, 1);
      } finally {
        await matcher.dispose();
      }
    },
  );
  testWidgets(
    'cycle changes restart the clock; saving the same cycle does not',
    (tester) async {
      var runs = 0;
      final matcher = create(
        run: (_) async {
          runs++;
        },
      );
      try {
        matcher.setInterval(AutomaticScanInterval.fifteenMinutes);
        await tester.pump(const Duration(minutes: 10));
        matcher.setInterval(AutomaticScanInterval.hourly);
        await tester.pump(const Duration(minutes: 30));
        expect(runs, 0);
        matcher.setInterval(AutomaticScanInterval.hourly);
        await tester.pump(const Duration(minutes: 30));
        expect(runs, 1);
      } finally {
        await matcher.dispose();
      }
    },
  );
  testWidgets(
    'in-flight automatic work cannot overlap and interval changes do not cancel it',
    (tester) async {
      var runs = 0, cancels = 0;
      final gate = Completer<void>();
      final matcher = create(
        run: (token) {
          runs++;
          token.listen(() => cancels++);
          return gate.future;
        },
      );
      try {
        matcher.setInterval(AutomaticScanInterval.fifteenMinutes);
        final pending = matcher.tick();
        await matcher.tick();
        await tester.pump(const Duration(minutes: 30));
        expect(runs, 1);
        matcher.setInterval(AutomaticScanInterval.hourly);
        expect(cancels, 0);
        gate.complete();
        await pending;
        expect(cancels, 0);
      } finally {
        await matcher.dispose();
      }
    },
  );
  testWidgets('disable cancels its own token and stops future ticks', (
    tester,
  ) async {
    var runs = 0, cancels = 0;
    final gate = Completer<void>();
    final matcher = create(
      run: (token) {
        runs++;
        token.listen(() => cancels++);
        return gate.future;
      },
    );
    try {
      matcher.setInterval(AutomaticScanInterval.hourly);
      final pending = matcher.tick();
      matcher.setInterval(AutomaticScanInterval.disabled);
      await pending;
      expect(cancels, 1);
      await tester.pump(const Duration(days: 2));
      expect(runs, 1);
      gate.complete();
      await tester.pump();
    } finally {
      await matcher.dispose();
    }
  });
  testWidgets('dispose cancels waiting promptly and ignores late completion', (
    tester,
  ) async {
    final gate = Completer<void>();
    var cancels = 0, runs = 0;
    final matcher = create(
      run: (token) {
        runs++;
        token.listen(() => cancels++);
        return gate.future;
      },
    );
    matcher.setInterval(AutomaticScanInterval.hourly);
    final pending = matcher.tick();
    await matcher.dispose();
    await matcher.dispose();
    await pending;
    expect(cancels, 1);
    gate.complete();
    await tester.pump(const Duration(days: 2));
    matcher.setInterval(AutomaticScanInterval.daily);
    await matcher.tick();
    expect(runs, 1);
  });
  testWidgets('one background failure is caught and a later tick can retry', (
    tester,
  ) async {
    final errors = <Object>[];
    var runs = 0;
    final matcher = create(
      run: (_) async {
        if (++runs == 1) throw const SourceFailure('fixture');
      },
      onError: (error, stack) => errors.add(error),
    );
    try {
      matcher.setInterval(AutomaticScanInterval.hourly);
      await matcher.tick();
      expect(errors, hasLength(1));
      await matcher.tick();
      expect(runs, 2);
    } finally {
      await matcher.dispose();
    }
  });
}
