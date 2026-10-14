import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/playback/presentation/player_basic_settings.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackSession session;
  late MediaIdentity film;
  var resourcesClosed = false;
  final engines = <FakeVideoEngine>[];

  setUp(() async {
    resourcesClosed = false;
    engines.clear();
    sandbox = await Directory.systemTemp.createTemp('reelnest-marker-skip-ui-');
    await File(p.join(sandbox.path, 'Film.mkv'))
        .writeAsString('marker skip fixture');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    final source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    film = (sourceId: source.id, localId: 'Film.mkv');
    session = PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final engine = FakeVideoEngine();
        engines.add(engine);
        return engine;
      },
    );
  });

  tearDown(() async {
    if (!resourcesClosed) {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
    }
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-marker-skip-ui-'));
    await sandbox.delete(recursive: true);
  });

  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() done, {
    String reason = 'Marker skip UI did not settle',
  }) async {
    for (var i = 0; i < 180; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (done()) return;
    }
    fail(reason);
  }

  Future<void> finish(WidgetTester tester, Future<void> future) async {
    var done = false;
    Object? failure;
    StackTrace? failureStack;
    future.then<void>(
      (_) => done = true,
      onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        done = true;
      },
    );
    await waitUntil(tester, () => done, reason: 'Async cleanup did not finish');
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  Future<void> closeHarness(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await finish(tester, session.close(discardProgress: true));
    session.dispose();
    await finish(tester, sources.close());
    resourcesClosed = true;
  }

  Future<void> pumpPlayer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          identity: film,
          session: session,
          closeWindow: () async {},
          setFullscreen: (_) async {},
        ),
      ),
    );
    await waitUntil(
      tester,
      () =>
          !session.loading &&
          session.clock.duration > Duration.zero &&
          session.precision.value.identity == film,
    );
    engines.single.emit();
    await tester.pump();
  }

  Future<void> openSession(WidgetTester tester) async {
    var done = false;
    session.open(film).then((_) => done = true);
    await waitUntil(tester, () => done);
    engines.single.emit();
    await tester.pump();
  }

  testWidgets(
    'marker panel sets intro and credits boundaries and deletes manual ranges',
    (tester) async {
      try {
        await pumpPlayer(tester);
        final markerTooltip = find.byTooltip('章节与播放标记');
        final markerButton = find.descendant(
          of: markerTooltip,
          matching: find.byType(IconButton),
        );
        await tester.tap(markerButton);
        await tester.pump();

        expect(find.byKey(const ValueKey('set-intro-start')), findsOneWidget);
        expect(find.byKey(const ValueKey('set-intro-end')), findsOneWidget);
        expect(find.byKey(const ValueKey('set-credits-start')), findsOneWidget);
        expect(find.byKey(const ValueKey('set-credits-end')), findsOneWidget);

        engines.single.emit(position: const Duration(seconds: 5));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('set-intro-start')));
        await waitUntil(
          tester,
          () => session.precision.value.markers.any(
            (marker) =>
                marker.kind == PlaybackMarkerKind.intro &&
                marker.start == const Duration(seconds: 5),
          ),
        );

        engines.single.emit(position: const Duration(seconds: 15));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('set-intro-end')));
        await waitUntil(
          tester,
          () => session.precision.value.markers.any(
            (marker) =>
                marker.kind == PlaybackMarkerKind.intro &&
                marker.end == const Duration(seconds: 15),
          ),
        );
        final intro = session.precision.value.markers.singleWhere(
          (marker) => marker.kind == PlaybackMarkerKind.intro,
        );
        expect(
          find.byKey(ValueKey('playback-marker-${intro.id}')),
          findsOneWidget,
        );
        expect(find.textContaining('0:05 – 0:15'), findsOneWidget);

        engines.single.emit(position: const Duration(seconds: 30));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('set-credits-end')));
        await waitUntil(
          tester,
          () => session.precision.value.markers.any(
            (marker) =>
                marker.kind == PlaybackMarkerKind.credits &&
                marker.start == Duration.zero &&
                marker.end == const Duration(seconds: 30),
          ),
        );

        final introRow = find.byKey(ValueKey('playback-marker-${intro.id}'));
        await tester.tap(
          find.descendant(of: introRow, matching: find.byTooltip('删除标记')),
        );
        await waitUntil(
          tester,
          () => session.precision.value.markers.every(
            (marker) => marker.id != intro.id,
          ),
        );
        expect(introRow, findsNothing);
      } finally {
        await closeHarness(tester);
      }
    },
  );

  testWidgets(
    'skip policy waits for persisted state before changing selection',
    (tester) async {
      try {
        await openSession(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 720,
                child: PlayerBasicSettings(
                  session: session,
                  palette: const PlayerPalette(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          session.precision.value.skipBehavior,
          VideoMarkerSkipBehavior.prompt,
        );
        expect(find.text('关闭'), findsAtLeastNWidgets(1));
        expect(find.text('显示按钮'), findsOneWidget);
        expect(find.text('自动跳过'), findsOneWidget);

        await finish(
          tester,
          sources.database.customStatement(
            "CREATE TRIGGER fail_marker_skip BEFORE INSERT ON player_preferences "
            "WHEN NEW.key='global.videoMarkerSkipBehavior' "
            "BEGIN SELECT RAISE(ABORT,'fixture'); END",
          ),
        );
        await tester.tap(find.byKey(const ValueKey('marker-skip-automatic')));
        await waitUntil(tester, () => session.controlError != null);
        expect(
          session.precision.value.skipBehavior,
          VideoMarkerSkipBehavior.prompt,
        );

        await finish(
          tester,
          sources.database.customStatement('DROP TRIGGER fail_marker_skip'),
        );
        await tester.tap(find.byKey(const ValueKey('marker-skip-automatic')));
        await waitUntil(
          tester,
          () =>
              session.controlError == null &&
              session.precision.value.skipBehavior ==
                  VideoMarkerSkipBehavior.automatic,
        );
      } finally {
        await closeHarness(tester);
      }
    },
  );

  testWidgets(
    'prompt shows one skip action while automatic mode stays UI-free',
    (tester) async {
      try {
        await pumpPlayer(tester);
        await session.seek(const Duration(seconds: 5));
        await session.setMarkerBoundary(
          PlaybackMarkerKind.intro,
          isStart: true,
        );
        await session.seek(const Duration(seconds: 15));
        await session.setMarkerBoundary(
          PlaybackMarkerKind.intro,
          isStart: false,
        );
        final intro = session.precision.value.markers.singleWhere(
          (marker) => marker.kind == PlaybackMarkerKind.intro,
        );

        await session.seek(const Duration(seconds: 7));
        await waitUntil(
          tester,
          () => session.precision.value.activeSkipMarker?.id == intro.id,
        );
        expect(
          find.byKey(const ValueKey('skip-active-playback-marker')),
          findsOneWidget,
        );
        expect(find.text('跳过片头'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('skip-active-playback-marker')),
        );
        await waitUntil(
          tester,
          () => session.clock.position == const Duration(seconds: 15),
        );
        await tester.pump(const Duration(milliseconds: 160));
        expect(
          find.byKey(const ValueKey('skip-active-playback-marker')),
          findsNothing,
        );

        await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
        await session.seek(const Duration(seconds: 7));
        await waitUntil(
          tester,
          () => session.clock.position == const Duration(seconds: 15),
        );
        expect(
          find.byKey(const ValueKey('skip-active-playback-marker')),
          findsNothing,
        );
      } finally {
        await closeHarness(tester);
      }
    },
  );
}
