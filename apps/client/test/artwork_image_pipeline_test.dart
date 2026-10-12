import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/sources/data/artwork_decode_queue.dart';
import 'package:reelnest/features/sources/data/artwork_image_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  ArtworkImageKey key(
    String item, {
    String source = 'source',
    int revision = 0,
    int width = 512,
  }) => (
    sourceId: source,
    itemId: item,
    backdrop: false,
    index: 0,
    width: width,
    height: width * 3 ~/ 2,
    revision: revision,
  );
  Future<void> resolve(
    ImageProvider provider, {
    void Function(ImageInfo)? inspect,
  }) async {
    final stream = provider.resolve(ImageConfiguration.empty);
    final done = Completer<void>();
    final listener = ImageStreamListener(
      (image, _) {
        inspect?.call(image);
        image.dispose();
        if (!done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    try {
      await done.future;
    } finally {
      stream.removeListener(listener);
    }
  }

  test(
    'decode permits are FIFO and never exceed the original limit of three',
    () async {
      final queue = ArtworkDecodeQueue();
      final gates = List.generate(7, (_) => Completer<void>());
      final started = <int>[];
      var active = 0, maximum = 0;
      final tasks = [
        for (var i = 0; i < gates.length; i++)
          queue.run(() async {
            started.add(i);
            active++;
            if (active > maximum) maximum = active;
            await gates[i].future;
            active--;
          }),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(started, [0, 1, 2]);
      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, [0, 1, 2, 3]);
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await Future.wait(tasks);
      expect(maximum, 3);
      expect(started, [0, 1, 2, 3, 4, 5, 6]);
      queue.dispose();
    },
  );
  test('closing decoder rejects waiting work without running it', () async {
    final queue = ArtworkDecodeQueue(maximum: 1);
    final gate = Completer<void>();
    final active = queue.run(() => gate.future);
    var ran = false;
    final queued = queue.run(() async {
      ran = true;
    });
    final failed = expectLater(queued, throwsStateError);
    queue.dispose();
    gate.complete();
    await active;
    await failed;
    expect(ran, isFalse);
    await expectLater(queue.run(() async {}), throwsStateError);
  });
  test('stable image identity coalesces work and reuses decoded pixels across byte loaders', () async {
    final queue = ArtworkDecodeQueue();
    final pipeline = ArtworkImagePipeline(decodes: queue);
    addTearDown(() {
      pipeline.dispose();
      queue.dispose();
    });
    expect(pipeline.cache.maximumSizeBytes, 512 * 1024 * 1024);
    expect(pipeline.cache.maximumSize, 1800);
    var reads = 0;
    final provider = pipeline.image(key('poster'), () async {
      reads++;
      return png;
    });
    await Future.wait([resolve(provider), resolve(provider)]);
    await resolve(
      pipeline.image(key('poster'), () async {
        reads++;
        return png;
      }),
    );
    expect(reads, 1);
    expect(pipeline.cache.currentSize, 1);
    expect(pipeline.cache.currentSizeBytes, 4);
  });
  test(
    'size preview reuses pixels but never another source or generation',
    () async {
      final queue = ArtworkDecodeQueue();
      final pipeline = ArtworkImagePipeline(decodes: queue);
      addTearDown(() {
        pipeline.dispose();
        queue.dispose();
      });
      await resolve(pipeline.image(key('poster', width: 192), () async => png));
      final preview = pipeline.preview(key('poster', width: 512));
      expect(preview, isNotNull);
      var synchronous = false;
      final stream = preview!.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener((image, sync) {
        synchronous = sync;
        image.dispose();
      });
      stream.addListener(listener);
      expect(synchronous, isTrue);
      stream.removeListener(listener);
      expect(pipeline.preview(key('poster', source: 'other')), isNull);
      expect(pipeline.preview(key('poster', revision: 1)), isNull);
      expect(pipeline.preview(key('other-poster')), isNull);
      pipeline.didHaveMemoryPressure();
      expect(pipeline.preview(key('poster')), isNull);
    },
  );

  test(
    'source, revision and decode size each isolate their cached image',
    () async {
      final queue = ArtworkDecodeQueue();
      final pipeline = ArtworkImagePipeline(decodes: queue);
      addTearDown(() {
        pipeline.dispose();
        queue.dispose();
      });
      var reads = 0;
      for (final request in [
        key('poster'),
        key('poster', source: 'other'),
        key('poster', revision: 1),
        key('poster', width: 1024),
      ]) {
        await resolve(
          pipeline.image(request, () async {
            reads++;
            return png;
          }),
        );
      }
      expect(reads, 4);
      expect(pipeline.cache.currentSize, 4);
    },
  );
  test(
    'LRU honors image and byte budgets and releases cache on memory pressure',
    () async {
      final queue = ArtworkDecodeQueue();
      final pipeline = ArtworkImagePipeline(
        decodes: queue,
        maximumBytes: 8,
        maximumImages: 2,
      );
      addTearDown(() {
        pipeline.dispose();
        queue.dispose();
      });
      var reads = 0;
      Future<void> load(String id) => resolve(
        pipeline.image(key(id), () async {
          reads++;
          return png;
        }),
      );
      await load('a');
      await load('b');
      await load('a');
      await load('c');
      expect(pipeline.cache.currentSize, 2);
      expect(pipeline.cache.currentSizeBytes, lessThanOrEqualTo(8));
      await load('b');
      expect(reads, 4);
      pipeline.didHaveMemoryPressure();
      expect(pipeline.cache.currentSize, 0);
      expect(pipeline.cache.currentSizeBytes, 0);
      await load('a');
      expect(reads, 5);
    },
  );
  test(
    'a replacement prewarm window stops enqueueing old offscreen images',
    () async {
      final queue = ArtworkDecodeQueue();
      final pipeline = ArtworkImagePipeline(decodes: queue);
      addTearDown(() {
        pipeline.dispose();
        queue.dispose();
      });
      final gates = List.generate(4, (_) => Completer<void>());
      var oldReads = 0, newReads = 0;
      final old = pipeline.prewarm([
        for (var i = 0; i < 10; i++)
          (
            key: key('old$i'),
            bytes: () async {
              oldReads++;
              if (i < 4) await gates[i].future;
              return png;
            },
          ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(oldReads, 4);
      final latest = pipeline.prewarm([
        (
          key: key('latest'),
          bytes: () async {
            newReads++;
            return png;
          },
        ),
      ]);
      for (final gate in gates) {
        gate.complete();
      }
      await Future.wait([old, latest]);
      expect(oldReads, 4);
      expect(newReads, 1);
      var additional = 0;
      await resolve(
        pipeline.image(key('latest'), () async {
          additional++;
          return png;
        }),
      );
      expect(additional, 0);
    },
  );
  test(
    'decoded posters preserve aspect ratio and never upscale small originals',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xFF00AACC), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final original = await picture.toImage(16, 8);
      final bytes = (await original.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      original.dispose();
      picture.dispose();
      final queue = ArtworkDecodeQueue();
      final pipeline = ArtworkImagePipeline(decodes: queue);
      addTearDown(() {
        pipeline.dispose();
        queue.dispose();
      });
      await resolve(
        pipeline.image(key('wide', width: 4), () async => bytes),
        inspect: (image) {
          expect(image.image.width, 4);
          expect(image.image.height, 2);
        },
      );
      await resolve(
        pipeline.image(key('wide', width: 32), () async => bytes),
        inspect: (image) {
          expect(image.image.width, 16);
          expect(image.image.height, 8);
        },
      );
    },
  );
  test('disposed cache discards late image and leaves no decoded or pending entries', () async {
    final queue = ArtworkDecodeQueue();
    final pipeline = ArtworkImagePipeline(decodes: queue);
    final gate = Completer<void>();
    final work = resolve(
      pipeline.image(key('late'), () async {
        await gate.future;
        return png;
      }),
    );
    final error = expectLater(work, throwsStateError);
    pipeline.dispose();
    gate.complete();
    await error;
    expect(pipeline.cache.currentSize, 0);
    expect(pipeline.cache.pendingImageCount, 0);
    expect(pipeline.cache.liveImageCount, 0);
    queue.dispose();
  });
}
