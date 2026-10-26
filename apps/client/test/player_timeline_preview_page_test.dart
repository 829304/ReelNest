import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_scrubber_preview_mode.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full player dock hover reaches and displays a decoded preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Directory directory;
    late SourceRepository sources;
    late MediaSource source;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp(
        'reelnest-preview-page-',
      );
      final video = File(p.join(directory.path, 'Film.mkv'));
      await video.writeAsString('fake decoder fixture');
      sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Fixture',
        location: directory.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
    });
    final identity = (sourceId: source.id, localId: 'Film.mkv');
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    var previewCalls = 0;
    final engines = <FakeVideoEngine>[];
    final session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      previewGenerator: (_, _, cancellation) async {
        previewCalls++;
        return cancellation.isCancelled ? null : png;
      },
      createEngine: () {
        final engine = FakeVideoEngine();
        engines.add(engine);
        return engine;
      },
    );

    Future<void> waitUntil(bool Function() done) async {
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        if (done()) return;
      }
      fail('Player preview UI did not settle');
    }

    Future<void> finish(Future<void> operation) async {
      var done = false;
      Object? failure;
      StackTrace? failureStack;
      operation.then(
        (_) => done = true,
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          done = true;
        },
      );
      await waitUntil(() => done);
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
    }

    TestGesture? mouse;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: identity,
            session: session,
            closeWindow: () async {},
            setFullscreen: (_) async {},
          ),
        ),
      );
      await waitUntil(
        () => !session.loading && session.clock.duration > Duration.zero,
      );
      engines.single.emit();
      await tester.pump();
      expect(
        session.options.videoScrubberPreviewMode,
        VideoScrubberPreviewMode.performance,
      );

      final region = find.byKey(const ValueKey('player-timeline-hover-region'));
      expect(region, findsOneWidget);
      expect(tester.getSize(region).height, 24);
      final center = tester.getCenter(region);
      mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: center);
      await tester.pump();
      await mouse.moveTo(center + const Offset(.5, 0));
      await tester.pump(const Duration(milliseconds: 120));
      await waitUntil(
        () => find
            .byKey(const ValueKey('player-timeline-preview-image'))
            .evaluate()
            .isNotEmpty,
      );

      expect(previewCalls, 1);
      final page = tester.getRect(find.byType(VideoPlayerPage));
      final bubble = tester.getRect(
        find.byKey(const ValueKey('player-timeline-preview-position')),
      );
      expect(bubble.top, greaterThanOrEqualTo(page.top));
      expect(bubble.bottom, lessThanOrEqualTo(page.bottom));
      expect(tester.takeException(), isNull);
    } finally {
      if (mouse != null) await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
      expect(p.basename(directory.path), startsWith('reelnest-preview-page-'));
      await finish(session.close(discardProgress: true));
      session.dispose();
      await tester.runAsync(() async {
        await sources.close();
        await directory.delete(recursive: true);
      });
    }
  });
}
