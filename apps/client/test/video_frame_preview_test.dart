import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/application/video_frame_preview_cache.dart';
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';

const _duration = Duration(minutes: 100);
VideoPreviewResource _resource({
  String id = 'film',
  Duration offset = Duration.zero,
}) => VideoPreviewResource(
  identity: (sourceId: 'source', localId: id),
  location: '/test/$id.mkv',
  offset: offset,
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('original bucket midpoints, clamps, minimums and extreme cap', () {
    expect(
      VideoPreviewBuckets.interval(_duration, coarse: true),
      closeTo(6000 / 84, .001),
    );
    expect(VideoPreviewBuckets.interval(_duration, coarse: false), 62.5);
    expect(
      VideoPreviewBuckets.interval(const Duration(seconds: 60), coarse: true),
      12,
    );
    expect(
      VideoPreviewBuckets.interval(const Duration(seconds: 60), coarse: false),
      8,
    );
    expect(VideoPreviewBuckets.interval(Duration.zero, coarse: false), 12);
    expect(
      VideoPreviewBuckets.interval(const Duration(hours: 100), coarse: true),
      300,
    );
    expect(
      VideoPreviewBuckets.sample(
        time: const Duration(seconds: -10),
        duration: _duration,
        coarse: false,
      ),
      const Duration(seconds: 31),
    );
    expect(
      VideoPreviewBuckets.sample(
        time: const Duration(hours: 2),
        duration: _duration,
        coarse: false,
      ),
      _duration,
    );
  });

  test(
    'same sampled time deduplicates callers and caches immutable bytes',
    () async {
      var calls = 0;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = Completer<Uint8List?>();
      final cache = VideoFramePreviewCache(
        generate: (_, time, cancellation) {
          calls++;
          return result.future;
        },
      )..attach(_resource());
      addTearDown(cache.dispose);
      final a = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
      );
      final b = cache.request(
        time: const Duration(seconds: 1),
        duration: _duration,
        coarse: false,
      );
      expect(calls, 1);
      result.complete(bytes);
      final frame = await a;
      expect(await b, same(frame));
      bytes[0] = 9;
      expect(frame!.bytes[0], 1);
      expect(() => frame.bytes[0] = 9, throwsUnsupportedError);
      expect(
        await cache.request(
          time: Duration.zero,
          duration: _duration,
          coarse: false,
        ),
        same(frame),
      );
      expect(calls, 1);
    },
  );

  test(
    'canceling one deduplicated subscriber preserves other caller',
    () async {
      final result = Completer<Uint8List?>();
      VideoPreviewCancellation? generatorToken;
      final cache = VideoFramePreviewCache(
        generate: (_, _, c) {
          generatorToken = c;
          return result.future;
        },
      )..attach(_resource());
      addTearDown(cache.dispose);
      final cancellation = VideoPreviewCancellation();
      final a = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
        cancellation: cancellation,
      );
      final b = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
      );
      cancellation.cancel();
      expect(await a, isNull);
      expect(generatorToken!.isCancelled, isFalse);
      result.complete(Uint8List.fromList([1]));
      expect(await b, isNotNull);
    },
  );

  test(
    'canceled decoder retains gate; pending cancellation never starts',
    () async {
      final first = Completer<Uint8List?>();
      var calls = 0;
      VideoPreviewCancellation? active;
      final cache = VideoFramePreviewCache(
        generate: (_, _, c) {
          calls++;
          active = c;
          return calls == 1 ? first.future : Future.value(Uint8List(1));
        },
      )..attach(_resource());
      addTearDown(cache.dispose);
      final aToken = VideoPreviewCancellation();
      final bToken = VideoPreviewCancellation();
      final a = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
        cancellation: aToken,
      );
      final b = cache.request(
        time: const Duration(seconds: 70),
        duration: _duration,
        coarse: false,
        cancellation: bToken,
      );
      bToken.cancel();
      aToken.cancel();
      expect(await b, isNull);
      expect(await a, isNull);
      expect(active!.isCancelled, isTrue);
      final c = cache.request(
        time: const Duration(seconds: 140),
        duration: _duration,
        coarse: false,
      );
      expect(calls, 1);
      first.complete(Uint8List(1));
      expect(await c, isNotNull);
      expect(calls, 2);
    },
  );

  test(
    'resource revision invalidates same film, cached and delayed frames',
    () async {
      final first = Completer<Uint8List?>();
      var calls = 0;
      final cache = VideoFramePreviewCache(
        generate: (_, _, _) =>
            ++calls == 1 ? first.future : Future.value(Uint8List.fromList([2])),
      )..attach(_resource());
      addTearDown(cache.dispose);
      final old = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
      );
      cache.attach(
        _resource(),
      ); // Same identity, new quality/decoder generation.
      expect(await old, isNull);
      final next = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
      );
      expect(calls, 1);
      first.complete(Uint8List.fromList([1]));
      expect((await next)!.bytes, [2]);
      expect(cache.cachedCount, 1);
    },
  );

  test(
    'timeouts include queue time and do not allow overlapping decoders',
    () async {
      final first = Completer<Uint8List?>();
      var calls = 0;
      final cache = VideoFramePreviewCache(
        requestTimeout: const Duration(milliseconds: 20),
        generate: (_, _, _) {
          calls++;
          return first.future;
        },
      )..attach(_resource());
      addTearDown(cache.dispose);
      final a = cache.request(
        time: Duration.zero,
        duration: _duration,
        coarse: false,
      );
      final b = cache.request(
        time: const Duration(seconds: 70),
        duration: _duration,
        coarse: false,
      );
      expect(await a, isNull);
      expect(await b, isNull);
      expect(calls, 1);
      first.complete(null);
      await _tick();
      expect(cache.cachedCount, 0);
    },
  );

  test('LRU and decoded-byte cost obey both limits', () async {
    final cache = VideoFramePreviewCache(
      maxEntries: 2,
      maxBytes: 312 * 176 * 4 * 2,
      generate: (_, _, _) async => Uint8List(1),
    )..attach(_resource());
    addTearDown(cache.dispose);
    for (final time in [0, 70]) {
      await cache.request(
        time: Duration(seconds: time),
        duration: _duration,
        coarse: false,
      );
    }
    cache.cached(time: Duration.zero, duration: _duration, coarse: false);
    await cache.request(
      time: const Duration(seconds: 140),
      duration: _duration,
      coarse: false,
    );
    expect(cache.cachedCount, 2);
    expect(cache.cachedBytes, 312 * 176 * 4 * 2);
    expect(
      cache.cached(
        time: const Duration(seconds: 70),
        duration: _duration,
        coarse: false,
      ),
      isNull,
    );
    expect(
      cache.cached(time: Duration.zero, duration: _duration, coarse: false),
      isNotNull,
    );
  });

  test(
    'errors and oversized output return empty without poisoning retries',
    () async {
      var calls = 0;
      final cache = VideoFramePreviewCache(
        generate: (_, _, _) async {
          if (++calls == 1) throw StateError('decoder failure');
          return calls == 2 ? Uint8List(1024 * 1024 + 1) : Uint8List(1);
        },
      )..attach(_resource());
      addTearDown(cache.dispose);
      for (var i = 0; i < 2; i++) {
        expect(
          await cache.request(
            time: Duration.zero,
            duration: _duration,
            coarse: false,
          ),
          isNull,
        );
      }
      expect(
        await cache.request(
          time: Duration.zero,
          duration: _duration,
          coarse: false,
        ),
        isNotNull,
      );
    },
  );

  test(
    'transcode suffix skips missing absolute buckets and preserves sample time',
    () async {
      Duration? sampled;
      final cache = VideoFramePreviewCache(
        generate: (_, time, _) async {
          sampled = time;
          return Uint8List(1);
        },
      )..attach(_resource(offset: const Duration(seconds: 100)));
      addTearDown(cache.dispose);
      expect(
        await cache.request(
          time: Duration.zero,
          duration: _duration,
          coarse: false,
        ),
        isNull,
      );
      final frame = await cache.request(
        time: const Duration(seconds: 140),
        duration: _duration,
        coarse: false,
      );
      expect(frame!.sampleTime, sampled);
      expect(sampled, const Duration(seconds: 156));
    },
  );

  test(
    'balanced prefetch uses neighboring buckets after delay; detach cancels it',
    () async {
      final samples = <Duration>[];
      final cache = VideoFramePreviewCache(
        prefetchDelay: const Duration(milliseconds: 5),
        generate: (_, time, _) async {
          samples.add(time);
          return Uint8List(1);
        },
      )..attach(_resource());
      addTearDown(cache.dispose);
      await cache.request(
        time: const Duration(seconds: 140),
        duration: _duration,
        coarse: false,
        prefetch: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(samples, [
        const Duration(seconds: 156),
        const Duration(seconds: 219),
        const Duration(seconds: 94),
      ]);
      await cache.request(
        time: const Duration(seconds: 300),
        duration: _duration,
        coarse: false,
        prefetch: true,
      );
      cache.attach(null);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(samples.length, 4);
    },
  );

  test('bounded pending queue and disposal abandon stale work', () async {
    final first = Completer<Uint8List?>();
    var calls = 0;
    final cache = VideoFramePreviewCache(
      generate: (_, _, _) {
        calls++;
        return first.future;
      },
    )..attach(_resource());
    final futures = [
      for (var i = 0; i < 7; i++)
        cache.request(
          time: Duration(seconds: i * 70),
          duration: _duration,
          coarse: false,
        ),
    ];
    expect(await futures.last, isNull);
    cache.dispose();
    expect(await Future.wait(futures), everyElement(isNull));
    first.complete(Uint8List(1));
    await _tick();
    expect(calls, 1);
    expect(cache.cachedCount, 0);
  });
}
