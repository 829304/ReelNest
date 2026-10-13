import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_marker_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/playback/domain/video_queue.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_timeline.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'original A–B selection keeps 0.20s minimum and starts a fresh range',
    () {
      var state = const PlaybackLoopState(loopCurrentItem: true);
      state = state.cycle(const Duration(seconds: 10));
      expect(state.start, const Duration(seconds: 10));
      expect(state.end, isNull);
      state = state.cycle(const Duration(milliseconds: 10200));
      expect(state.start, const Duration(milliseconds: 10200));
      expect(state.end, isNull);
      state = state.cycle(const Duration(milliseconds: 10401));
      expect(state.hasRange, isTrue);
      expect(state.end, const Duration(milliseconds: 10401));
      state = state.cycle(const Duration(seconds: 7));
      expect(state.start, const Duration(seconds: 7));
      expect(state.end, isNull);
      expect(state.loopCurrentItem, isTrue);
    },
  );

  test('mpv chapter parsing validates times and retains native indices', () {
    final chapters = VideoChapter.decode(
      '[{"time":20,"title":" B "},'
      '{"time":0},{"time":-1},{"time":"NaN"},{"time":"Infinity"},'
      '{"title":"missing"},{"time":1.125,"title":""}]',
    );
    expect(chapters.map((c) => c.index), [1, 6, 0]);
    expect(chapters.map((c) => c.title), ['章节 2', '章节 7', 'B']);
    expect(chapters[1].time, const Duration(milliseconds: 1125));
    expect(VideoChapter.decode(''), isEmpty);
  });

  test(
    'native commands use mpv loop properties and exact frame commands',
    () async {
      final commands = <List<String>>[];
      final properties = <String, String>{};
      final adapter = MpvTimelineCommands(
        command: (args) async {
          commands.add(args);
          if (args.first == 'set') properties[args[1]] = args[2];
        },
        read: (name) async => properties[name] ?? '',
      );
      await adapter.setLoopCurrentItem(true);
      await adapter.setLoopCurrentItem(false);
      await adapter.setABLoop(
        const Duration(milliseconds: 1125),
        const Duration(seconds: 3),
      );
      await adapter.stepFrame(backward: false);
      await adapter.stepFrame(backward: true);
      expect(commands, [
        ['set', 'loop-file', 'inf'],
        ['set', 'loop-file', 'no'],
        ['set', 'ab-loop-b', 'no'],
        ['set', 'ab-loop-a', '1.125'],
        ['set', 'ab-loop-b', '3.0'],
        ['frame-step'],
        ['frame-back-step'],
      ]);
      await adapter.setABLoop(null, null);
      expect(properties['ab-loop-a'], 'no');
      expect(properties['ab-loop-b'], 'no');
      await expectLater(
        adapter.setABLoop(null, const Duration(seconds: 2)),
        throwsArgumentError,
      );
    },
  );

  test('native readback detects rejected loop properties', () async {
    final adapter = MpvTimelineCommands(
      command: (_) async {},
      read: (_) async => 'no',
    );
    await expectLater(adapter.setLoopCurrentItem(true), throwsStateError);
    await expectLater(
      adapter.setABLoop(const Duration(seconds: 1), null),
      throwsStateError,
    );
  });

  group('session and marker persistence', () {
    late Directory sandbox;
    late SourceRepository sources;
    late PlaybackMarkerRepository markers;
    late PlaybackSession session;
    late MediaSource source;
    final engines = <FakeVideoEngine>[];
    MediaIdentity id(String path) => (sourceId: source.id, localId: path);
    const chapterList = [
      VideoChapter(index: 0, title: 'Opening', time: Duration.zero),
      VideoChapter(index: 1, title: 'Second', time: Duration(seconds: 20)),
    ];
    PlaybackSession makeSession() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final engine = FakeVideoEngine()..chapterList = chapterList;
        engines.add(engine);
        return engine;
      },
    );
    setUp(() async {
      engines.clear();
      sandbox = await Directory.systemTemp.createTemp('reelnest-precision-');
      for (final name in ['Film.mkv', 'Show.S01E01.mkv', 'Show.S01E02.mkv']) {
        await File(p.join(sandbox.path, name))
            .writeAsString('fake decoder fixture');
      }
      sources = SourceRepository(
        database: LibraryDatabase(
          NativeDatabase(File(p.join(sandbox.path, 'library.sqlite'))),
        ),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Test',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      markers = PlaybackMarkerRepository(sources.database);
      session = makeSession();
    });
    tearDown(() async {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-precision-'));
      await sandbox.delete(recursive: true);
    });

    test('embedded refresh preserves manual chapters and bookmarks across restarts', () async {
      await session.open(id('Film.mkv'));
      expect(session.precision.value.chapters.length, 2);
      await session.addBookmark(at: const Duration(milliseconds: 12345));
      await session.addChapter(at: const Duration(seconds: 15));
      final bookmark = session.precision.value.bookmarks.single;
      expect(bookmark.title, '书签 1');
      engines.last.chapterList = [
        const VideoChapter(
          index: 0,
          title: 'Revised',
          time: Duration(seconds: 1),
        ),
      ];
      await session.refreshTimeline();
      final saved = await markers.read(id('Film.mkv'));
      expect(saved.length, 3);
      expect(saved.any((m) => m.title == 'Opening'), isFalse);
      expect(saved.any((m) => m.title == '手动章节 1'), isTrue);
      await session.seekPlaybackMarker(bookmark.id);
      expect(session.clock.position, bookmark.start);
      await session.close();
      session.dispose();
      session = makeSession();
      await session.open(id('Film.mkv'));
      expect(session.precision.value.bookmarks.single.start, bookmark.start);
      final embeddedId = session.precision.value.chapters
          .firstWhere((m) => m.origin == PlaybackMarkerOrigin.embedded)
          .id;
      await session.deletePlaybackMarker(embeddedId);
      expect(
        session.precision.value.chapters.any((m) => m.id == embeddedId),
        isTrue,
      );
      await session.deletePlaybackMarker(bookmark.id);
      expect(session.precision.value.bookmarks, isEmpty);
    });

    test(
      'failed chapter read keeps saved bookmarks available and playback usable',
      () async {
        await session.open(id('Film.mkv'));
        await session.addBookmark(at: const Duration(seconds: 5));
        engines.last.failChapters = true;
        await session.refreshTimeline();
        expect(session.error, isNull);
        expect(session.controlError, isNotNull);
        expect(
          session.precision.value.bookmarks.single.start,
          const Duration(seconds: 5),
        );
        await session.seekPlaybackMarker(
          session.precision.value.bookmarks.single.id,
        );
        expect(session.clock.position, const Duration(seconds: 5));
        await session.toggle();
        expect(session.clock.playing, isFalse);
      },
    );

    test('empty snapshot does not erase embedded chapters', () async {
      await session.open(id('Film.mkv'));
      engines.last.chapterList = const [];
      await session.refreshTimeline();
      expect(session.precision.value.chapters.length, 2);
    });

    test(
      'switch clears A–B while keeping loop preference and per-film markers',
      () async {
        await session.open(id('Show.S01E01.mkv'));
        await session.addBookmark(at: const Duration(seconds: 5));
        await session.setLoopCurrentItem(true);
        await session.seek(const Duration(seconds: 10));
        await session.cycleABLoop();
        await session.seek(const Duration(seconds: 20));
        await session.cycleABLoop();
        expect(engines.last.abEnd, const Duration(seconds: 20));
        await session.adjacent(1);
        expect(session.item!.identity, id('Show.S01E02.mkv'));
        expect(session.precision.value.bookmarks, isEmpty);
        expect(session.precision.value.loop.start, isNull);
        expect(engines.last.abStart, isNull);
        expect(engines.last.loopCurrentItem, isTrue);
        expect(
          (await markers.read(id('Show.S01E01.mkv')))
              .where((m) => m.kind == PlaybackMarkerKind.bookmark)
              .length,
          1,
        );
        await session.close();
        session.dispose();
        session = makeSession();
        await session.open(id('Film.mkv'));
        expect(session.precision.value.loop.loopCurrentItem, isTrue);
        expect(session.precision.value.loop.start, isNull);
      },
    );

    test(
      'loop terminal EOF cannot trigger next episode or close window',
      () async {
        await session.open(id('Show.S01E01.mkv'));
        await session.setEndAction(VideoEndAction.closeWindow);
        await session.setLoopCurrentItem(true);
        engines.last.emit(
          completed: true,
          position: const Duration(seconds: 100),
        );
        await session.refreshQueue(); // drain serialized end processing
        expect(session.closeRequests.value, 0);
        expect(session.item!.identity, id('Show.S01E01.mkv'));
        expect(session.clock.position, Duration.zero);
        expect(session.clock.playing, isTrue);
      },
    );

    test(
      'step pauses, records progress and leaves a failed command retryable',
      () async {
        await session.open(id('Film.mkv'));
        await session.seek(const Duration(seconds: 10));
        await session.stepFrame();
        expect(session.clock.playing, isFalse);
        expect(engines.last.frameSteps, [false]);
        expect(
          (await session.records.read(id('Film.mkv'))).position,
          const Duration(milliseconds: 10040),
        );
        await session.stepFrame(backward: true);
        expect(engines.last.frameSteps, [false, true]);
        engines.last.failControl = true;
        await session.setLoopCurrentItem(true);
        expect(session.error, isNull);
        expect(session.controlError, isNotNull);
        expect(session.precision.value.loop.loopCurrentItem, isFalse);
        engines.last.failControl = false;
        await session.setLoopCurrentItem(true);
        expect(session.controlError, isNull);
        await session.toggle();
        expect(session.clock.playing, isTrue);
      },
    );

    test('loop persistence failure rolls native state back', () async {
      await session.open(id('Film.mkv'));
      await sources.database.customStatement(
        "CREATE TRIGGER fail_loop BEFORE INSERT ON player_preferences WHEN NEW.key='global.videoLoopCurrentItem' BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await session.setLoopCurrentItem(true);
      expect(session.controlError, isNotNull);
      expect(engines.last.loopCurrentItem, isFalse);
      expect(session.precision.value.loop.loopCurrentItem, isFalse);
    });

    test(
      'delayed old chapter events do not contaminate a switched film',
      () async {
        await session.open(id('Film.mkv'));
        final old = engines.last;
        old.chapterList = [
          const VideoChapter(
            index: 0,
            title: 'Stale',
            time: Duration(seconds: 7),
          ),
        ];
        old.chapterEvents.add(old.chapterList);
        await session.open(id('Show.S01E01.mkv'));
        await session.refreshTimeline();
        expect(
          session.precision.value.chapters.any((m) => m.title == 'Stale'),
          isFalse,
        );
        expect(session.precision.value.identity, id('Show.S01E01.mkv'));
      },
    );

    test('markers are source-scoped and cascade with their media', () async {
      final second = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Other',
        location: (await Directory(
          p.join(sandbox.path, 'other'),
        ).create()).path,
        minimumFileSize: 0,
      );
      await File(p.join(second.location, 'Film.mkv')).writeAsString('fixture');
      await sources.scan(second.id);
      final firstId = id('Film.mkv');
      final secondId = (sourceId: second.id, localId: 'Film.mkv');
      for (final identity in [firstId, secondId]) {
        await markers.save(
          PlaybackMarker(
            id: 'same-marker',
            identity: identity,
            kind: PlaybackMarkerKind.bookmark,
            title: '  ',
            start: const Duration(seconds: -1),
          ),
        );
      }
      expect((await markers.read(firstId)).single.title, '书签');
      expect((await markers.read(secondId)).single.start, Duration.zero);
      await markers.deleteManual(firstId, 'same-marker');
      expect(await markers.read(firstId), isEmpty);
      expect(await markers.read(secondId), hasLength(1));
      await sources.database.customStatement(
        'DELETE FROM media WHERE source_id=? AND local_id=?',
        [secondId.sourceId, secondId.localId],
      );
      expect(await markers.read(secondId), isEmpty);
    });
  });
}
