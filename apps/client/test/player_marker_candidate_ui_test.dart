import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/playback/presentation/player_precision_controls.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_timeline.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _MarkerUiSession extends PlaybackSession {
  _MarkerUiSession({
    required super.sources,
    required super.records,
    required super.createEngine,
  }) : super(checkpointInterval: const Duration(hours: 1));

  bool delayAnalysis = false;
  ScanCancellation? receivedCancellation;
  Completer<int?>? delayedResult;

  @override
  Future<int?> analyzeIntroOutroMarkers({ScanCancellation? cancellation}) {
    if (!delayAnalysis) {
      return super.analyzeIntroOutroMarkers(cancellation: cancellation);
    }
    receivedCancellation = cancellation;
    delayedResult = Completer<int?>();
    return delayedResult!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late SourceRepository sources;
  late _MarkerUiSession session;
  late MediaIdentity film;
  late MediaIdentity second;
  var resourcesClosed = false;

  setUp(() async {
    resourcesClosed = false;
    sandbox = await Directory.systemTemp.createTemp('reelnest-marker-ui-');
    await File(p.join(sandbox.path, 'Film.mkv')).writeAsString('fixture');
    await File(p.join(sandbox.path, 'Second.mkv')).writeAsString('fixture');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'marker-ui-volume',
    );
    final source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Marker UI',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    film = (sourceId: source.id, localId: 'Film.mkv');
    second = (sourceId: source.id, localId: 'Second.mkv');
    session = _MarkerUiSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      createEngine: () => FakeVideoEngine()
        ..chapterList = const [
          VideoChapter(index: 0, title: 'Opening', time: Duration.zero),
          VideoChapter(index: 1, title: 'Main', time: Duration(seconds: 30)),
          VideoChapter(index: 2, title: 'Credits', time: Duration(seconds: 80)),
        ],
    );
    await session.open(film);
  });

  tearDown(() async {
    if (!resourcesClosed) {
      final delayed = session.delayedResult;
      if (delayed != null && !delayed.isCompleted) {
        delayed.complete(null);
      }
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
    }
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    await sandbox.delete(recursive: true);
  });

  Future<void> pumpPanel(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 330,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: PlayerMarkerPanel(
                session: session,
                palette: const PlayerPalette(),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> waitUntil(WidgetTester tester, bool Function() condition) async {
    for (var attempt = 0; attempt < 150; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (condition()) return;
    }
    fail('Marker candidate UI did not settle');
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
    await waitUntil(tester, () => done);
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
  }

  Future<void> closeHarness(WidgetTester tester) async {
    final delayed = session.delayedResult;
    if (delayed != null && !delayed.isCompleted) {
      delayed.complete(null);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await finish(tester, session.close(discardProgress: true));
    session.dispose();
    await finish(tester, sources.close());
    resourcesClosed = true;
  }

  testWidgets('detects, accepts and rejects current-video candidates', (
    tester,
  ) async {
    try {
      await pumpPanel(tester);
      await tester.tap(
        find.byKey(const ValueKey('analyze-intro-outro-markers')),
      );
      await waitUntil(
        tester,
        () =>
            session.precision.value.markers
                .where((marker) => marker.isPendingReview)
                .length ==
            2,
      );

      expect(find.text('发现 2 个待审核标记'), findsOneWidget);
      final pending = session.precision.value.markers
          .where((marker) => marker.isPendingReview)
          .toList();
      final intro = pending.singleWhere(
        (marker) => marker.kind == PlaybackMarkerKind.intro,
      );
      final credits = pending.singleWhere(
        (marker) => marker.kind == PlaybackMarkerKind.credits,
      );
      expect(find.text('待审核 · 88% · 0:00 – 0:30'), findsOneWidget);
      expect(find.text('待审核 · 88% · 1:20 – 1:40'), findsOneWidget);
      expect(find.byTooltip('采用自动标记'), findsNWidgets(2));
      expect(find.byTooltip('忽略自动标记'), findsNWidgets(2));

      await tester.tap(
        find.byKey(ValueKey('accept-automatic-marker-${intro.id}')),
      );
      await waitUntil(
        tester,
        () => session.precision.value.markers.any(
          (marker) =>
              marker.id == intro.id &&
              marker.review == PlaybackMarkerReview.accepted,
        ),
      );
      expect(find.text('已采用自动标记 · 片头'), findsOneWidget);
      expect(find.text('自动标记 · 88% · 0:00 – 0:30'), findsOneWidget);
      expect(
        find.byKey(ValueKey('accept-automatic-marker-${intro.id}')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(ValueKey('reject-automatic-marker-${credits.id}')),
      );
      await waitUntil(
        tester,
        () => !session.precision.value.markers.any(
          (marker) => marker.id == credits.id,
        ),
      );
      expect(find.text('已忽略自动标记 · 片尾'), findsOneWidget);
      expect(
        find.byKey(ValueKey('playback-marker-${credits.id}')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('analyze-intro-outro-markers')),
      );
      await waitUntil(
        tester,
        () => find.text('没有发现可审核候选').evaluate().isNotEmpty,
      );
    } finally {
      await closeHarness(tester);
    }
  });

  testWidgets('closing the panel cancels a current-video detection', (
    tester,
  ) async {
    try {
      session.delayAnalysis = true;
      await pumpPanel(tester);
      await tester.tap(
        find.byKey(const ValueKey('analyze-intro-outro-markers')),
      );
      await tester.pump();
      expect(find.text('正在检测…'), findsOneWidget);
      expect(session.receivedCancellation, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        session.receivedCancellation!.check,
        throwsA(isA<ScanCancelled>()),
      );
    } finally {
      await closeHarness(tester);
    }
  });

  testWidgets('switching video suppresses a late detection result', (
    tester,
  ) async {
    try {
      session.delayAnalysis = true;
      await pumpPanel(tester);
      await tester.tap(
        find.byKey(const ValueKey('analyze-intro-outro-markers')),
      );
      await tester.pump();
      final cancellation = session.receivedCancellation!;

      var switched = false;
      unawaited(session.open(second).then((_) => switched = true));
      await waitUntil(tester, () => switched);
      expect(cancellation.check, throwsA(isA<ScanCancelled>()));
      session.delayedResult!.complete(2);
      await tester.pump();

      expect(find.text('发现 2 个待审核标记'), findsNothing);
      expect(find.text('检测片头片尾'), findsOneWidget);
    } finally {
      await closeHarness(tester);
    }
  });
}
