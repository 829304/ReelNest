import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native player page paints hover frame in the complete dock', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final temporary = await RuntimeStoragePaths.current.temporary();
    await temporary.create(recursive: true);
    final sandbox = await temporary.createTemp('reelnest-timeline-native-');
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture',
    );
    final session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      createEngine: MediaKitVideoEngine.new,
    );
    Future<void> waitUntil(bool Function() condition) async {
      for (var n = 0; n < 800 && !condition(); n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(condition(), isTrue);
    }

    Future<void> finish(Future<void> future) async {
      var done = false;
      Object? failure;
      future.then(
        (_) => done = true,
        onError: (Object error) {
          failure = error;
          done = true;
        },
      );
      await waitUntil(() => done);
      if (failure != null) throw failure!;
    }

    final boundary = GlobalKey();
    TestGesture? pointer;
    try {
      await createTrackVideoFixture(p.join(sandbox.path, 'Film.mkv'));
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Fixture',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: VideoPlayerPage(
              identity: (sourceId: source.id, localId: 'Film.mkv'),
              session: session,
              closeWindow: () async {},
              setFullscreen: (_) async {},
            ),
          ),
        ),
      );
      await waitUntil(
        () => !session.loading && session.clock.duration > Duration.zero,
      );
      await finish(session.engine!.pause());
      final before = session.clock.position;
      final timeline = find.byKey(const ValueKey('video-timeline'));
      final center = tester.getCenter(timeline);
      pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: center);
      await pointer.moveTo(center);
      // Simulate the small continual movements of a real mouse in one bucket.
      for (var n = 0; n < 12; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 130)),
        );
        await pointer.moveTo(center + Offset((n % 3).toDouble(), 0));
        await tester.pump();
      }
      await waitUntil(
        () => find
            .byKey(const ValueKey('player-timeline-preview-image'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      final image = tester.renderObject<RenderImage>(
        find.descendant(
          of: find.byKey(const ValueKey('player-timeline-preview-image')),
          matching: find.byType(RawImage),
        ),
      );
      expect(image.image, isNotNull);
      expect((image.image!.width, image.image!.height), (312, 176));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-timeline-preview')),
            )
            .opacity,
        1,
      );
      final frame = tester.getRect(
        find.byKey(const ValueKey('player-timeline-preview-image')),
      );
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.bottom, lessThan(tester.getRect(timeline).top));
      expect(
        (session.clock.position - before).abs(),
        lessThan(const Duration(milliseconds: 500)),
      );
      expect(session.clock.playing, isFalse);
      final shot =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      try {
        final rgba = (await shot.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var lit = 0;
        for (
          var y = frame.top.ceil() + 5;
          y < frame.bottom.floor() - 5;
          y += 3
        ) {
          for (
            var x = frame.left.ceil() + 5;
            x < frame.right.floor() - 5;
            x += 3
          ) {
            final at = (y * shot.width + x) * 4;
            if (rgba.getUint8(at) +
                    rgba.getUint8(at + 1) +
                    rgba.getUint8(at + 2) >
                120) {
              lit++;
            }
          }
        }
        expect(
          lit,
          greaterThan(100),
          reason: 'Preview must be painted, not merely present outside a clip',
        );
      } finally {
        shot.dispose();
      }
      debugPrint(
        'timeline preview: complete VideoPlayerPage hover, native decoded PNG and visible pixels passed',
      );
    } finally {
      await pointer?.removePointer();
      await tester.pumpWidget(const SizedBox());
      await finish(session.close(discardProgress: true));
      session.dispose();
      await sources.close();
      expect(p.isWithin(temporary.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-timeline-native-'));
      await sandbox.delete(recursive: true);
    }
  });
}
