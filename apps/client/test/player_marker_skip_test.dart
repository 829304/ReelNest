import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_marker_repository.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/playback_marker.dart';
import 'package:reelnest/features/playback/domain/video_queue.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _SkipEngine extends FakeVideoEngine {
  final seeks = <Duration>[];
  bool failSeek = false;
  Completer<void>? volumeGate;
  Completer<void>? volumeEntered;

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    if (failSeek) throw StateError('fixture seek failure');
    await super.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    final gate = volumeGate;
    if (gate != null) {
      volumeEntered?.complete();
      await gate.future;
    }
    await super.setVolume(volume);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SourceRepository sources;
  late PlaybackMarkerRepository markers;
  late PlaybackSession session;
  late MediaSource source;
  final engines = <_SkipEngine>[];
  MediaIdentity id([String name = 'Film.mkv']) =>
      (sourceId: source.id, localId: name);
  PlaybackSession createSession() => PlaybackSession(
    sources: sources,
    records: PlaybackRepository(sources.database),
    checkpointInterval: const Duration(hours: 1),
    createEngine: () {
      final engine = _SkipEngine();
      engines.add(engine);
      return engine;
    },
  );
  Future<void> range({int start = 10, int end = 20}) async {
    await session.setMarkerBoundary(
      PlaybackMarkerKind.intro,
      isStart: true,
      at: Duration(seconds: start),
    );
    await session.setMarkerBoundary(
      PlaybackMarkerKind.intro,
      isStart: false,
      at: Duration(seconds: end),
    );
  }

  Future<void> restart() async {
    await session.close(discardProgress: true);
    session.dispose();
    session = createSession();
    await session.open(id());
  }

  setUp(() async {
    engines.clear();
    directory = await Directory.systemTemp.createTemp('reelnest-marker-skip-');
    for (final name in ['Film.mkv', 'Next.mkv']) {
      await File(p.join(directory.path, name)).writeAsString('fake video');
    }
    sources = SourceRepository(
      database: LibraryDatabase(
        NativeDatabase(File(p.join(directory.path, 'library.sqlite'))),
      ),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'fixture',
      location: directory.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    markers = PlaybackMarkerRepository(sources.database);
    session = createSession();
    await session.open(id());
  });
  tearDown(() async {
    for (final engine in engines) {
      if (engine.volumeGate case final gate? when !gate.isCompleted) {
        gate.complete();
      }
    }
    await session.close(discardProgress: true);
    session.dispose();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
    expect(p.basename(directory.path), startsWith('reelnest-marker-skip-'));
    await directory.delete(recursive: true);
  });

  test(
    'manual boundaries retain IDs, persist and follow original editing rules',
    () async {
      await range();
      final first = (await markers.read(id())).single;
      await session.setMarkerBoundary(
        PlaybackMarkerKind.intro,
        isStart: true,
        at: const Duration(seconds: 25),
      );
      var marker = (await markers.read(id())).single;
      expect(marker.id, first.id);
      expect(
        marker.createdAt.millisecondsSinceEpoch,
        first.createdAt.millisecondsSinceEpoch,
      );
      expect(marker.end, isNull);
      await session.setMarkerBoundary(
        PlaybackMarkerKind.intro,
        isStart: false,
        at: const Duration(seconds: 15),
      );
      marker = (await markers.read(id())).single;
      expect(marker.start, Duration.zero);
      expect(marker.end, const Duration(seconds: 15));
      await restart();
      expect(session.precision.value.markers.single.id, first.id);
      expect(
        session.precision.value.markers.single.end,
        const Duration(seconds: 15),
      );
    },
  );

  test(
    'end-first supports a 90s fallback and a zero-time minimum range',
    () async {
      await session.setMarkerBoundary(
        PlaybackMarkerKind.credits,
        isStart: false,
        at: const Duration(seconds: 100),
      );
      var marker = (await markers.read(id())).single;
      expect(marker.start, const Duration(seconds: 10));
      expect(marker.end, const Duration(seconds: 100));
      await session.deletePlaybackMarker(marker.id);
      await session.setMarkerBoundary(
        PlaybackMarkerKind.credits,
        isStart: false,
        at: Duration.zero,
      );
      marker = (await markers.read(id())).single;
      expect(marker.start, Duration.zero);
      expect(marker.end, const Duration(milliseconds: 100));
    },
  );

  test(
    'prompt is default, contains start not end and updates only on entry/exit',
    () async {
      await range();
      expect(
        session.precision.value.skipBehavior,
        VideoMarkerSkipBehavior.prompt,
      );
      var notifications = 0;
      void changed() => notifications++;
      session.precision.addListener(changed);
      engines.last.emit(position: const Duration(seconds: 10));
      final active = session.precision.value.activeSkipMarker!;
      engines.last.emit(position: const Duration(seconds: 11));
      engines.last.emit(position: const Duration(seconds: 19));
      expect(notifications, 1);
      expect(engines.last.seeks, isEmpty);
      await session.skipPlaybackMarker(active.id);
      expect(session.clock.position, const Duration(seconds: 20));
      expect(session.precision.value.activeSkipMarker, isNull);
      expect(notifications, 2);
      await session.skipPlaybackMarker(active.id);
      expect(engines.last.seeks, hasLength(1));
      session.precision.removeListener(changed);
    },
  );

  test(
    'off hides prompts without deleting markers and persists globally',
    () async {
      await range();
      engines.last.emit(position: const Duration(seconds: 12));
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.off);
      expect(session.precision.value.activeSkipMarker, isNull);
      expect(await markers.read(id()), hasLength(1));
      await restart();
      engines.last.emit(position: const Duration(seconds: 12));
      expect(session.precision.value.skipBehavior, VideoMarkerSkipBehavior.off);
      expect(session.precision.value.activeSkipMarker, isNull);
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.prompt);
      expect(session.precision.value.activeSkipMarker, isNotNull);
    },
  );

  test(
    'automatic skips once on entry, rearms after exit and preserves pause',
    () async {
      await range();
      await session.toggle();
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
      engines.last.emit(position: const Duration(seconds: 12));
      engines.last.emit(position: const Duration(seconds: 13));
      await session.refreshQueue();
      expect(engines.last.seeks, [const Duration(seconds: 20)]);
      expect(session.clock.playing, isFalse);
      engines.last.emit(position: const Duration(seconds: 14));
      await session.refreshQueue();
      expect(engines.last.seeks, hasLength(2));
      await restart();
      expect(
        session.precision.value.skipBehavior,
        VideoMarkerSkipBehavior.automatic,
      );
    },
  );

  test(
    'incomplete, pending and rejected ranges never prompt or auto-skip',
    () async {
      await session.setMarkerBoundary(
        PlaybackMarkerKind.intro,
        isStart: true,
        at: const Duration(seconds: 10),
      );
      for (final review in [
        PlaybackMarkerReview.pending,
        PlaybackMarkerReview.rejected,
      ]) {
        await markers.save(
          PlaybackMarker(
            identity: id(),
            kind: PlaybackMarkerKind.credits,
            title: 'candidate',
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
            origin: PlaybackMarkerOrigin.automatic,
            review: review,
          ),
        );
      }
      await session.refreshTimeline();
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
      engines.last.emit(position: const Duration(seconds: 12));
      await session.refreshQueue();
      expect(session.precision.value.activeSkipMarker, isNull);
      expect(engines.last.seeks, isEmpty);
    },
  );

  test(
    'failed writes retain saved boundaries and settings and allow retry',
    () async {
      await range();
      await sources.database.customStatement(
        "CREATE TRIGGER fail_marker BEFORE INSERT ON playback_markers BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await session.setMarkerBoundary(
        PlaybackMarkerKind.intro,
        isStart: true,
        at: const Duration(seconds: 15),
      );
      expect(session.controlError, isNotNull);
      expect(
        (await markers.read(id())).single.start,
        const Duration(seconds: 10),
      );
      await sources.database.customStatement('DROP TRIGGER fail_marker');
      await sources.database.customStatement(
        "CREATE TRIGGER fail_pref BEFORE INSERT ON player_preferences WHEN NEW.key='global.videoMarkerSkipBehavior' BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
      expect(session.controlError, isNotNull);
      expect(
        session.precision.value.skipBehavior,
        VideoMarkerSkipBehavior.prompt,
      );
      await sources.database.customStatement('DROP TRIGGER fail_pref');
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.off);
      expect(session.controlError, isNull);
      expect(session.error, isNull);
    },
  );

  test(
    'failed automatic seek is retryable and is not retried every clock tick',
    () async {
      await range();
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
      engines.last.failSeek = true;
      engines.last.emit(position: const Duration(seconds: 12));
      await session.refreshQueue();
      for (var i = 0; i < 10; i++) {
        engines.last.emit(position: const Duration(seconds: 13));
      }
      await session.refreshQueue();
      expect(engines.last.seeks, hasLength(1));
      expect(session.controlError, contains('自动跳过失败'));
      expect(session.error, isNull);
      engines.last.failSeek = false;
      await session.skipPlaybackMarker(
        session.precision.value.activeSkipMarker!.id,
      );
      expect(session.clock.position, const Duration(seconds: 20));
      expect(session.controlError, isNull);
    },
  );

  for (final switchFilm in [false, true]) {
    test(
      'queued automatic skip is discarded after ${switchFilm ? 'film switch' : 'range exit'}',
      () async {
        await range();
        await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
        final old = engines.last;
        old.volumeGate = Completer<void>();
        old.volumeEntered = Completer<void>();
        final blocked = session.volume(50);
        await old.volumeEntered!.future;
        final switching = switchFilm
            ? session.open(id('Next.mkv'))
            : Future<void>.value();
        old.emit(position: const Duration(seconds: 12));
        if (!switchFilm) old.emit(position: const Duration(seconds: 30));
        old.volumeGate!.complete();
        await blocked;
        await switching;
        await session.refreshQueue();
        expect(old.seeks, isEmpty);
        expect(engines.last.seeks, isEmpty);
        if (switchFilm) expect(session.precision.value.markers, isEmpty);
      },
    );
  }

  test(
    'loop state survives skipping and close cancels a pending skip',
    () async {
      await range();
      await session.seek(const Duration(seconds: 5));
      await session.cycleABLoop();
      await session.seek(const Duration(seconds: 30));
      await session.cycleABLoop();
      await session.setLoopCurrentItem(true);
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
      engines.last.emit(position: const Duration(seconds: 12));
      await session.refreshQueue();
      expect(session.clock.position, const Duration(seconds: 20));
      expect(session.precision.value.loop.hasRange, isTrue);
      expect(engines.last.abStart, const Duration(seconds: 5));
      expect(engines.last.loopCurrentItem, isTrue);
      final count = engines.last.seeks.length;
      engines.last.emit(position: const Duration(seconds: 12));
      await session.close(discardProgress: true);
      expect(engines.last.seeks, hasLength(count));
    },
  );

  test(
    'manual range IDs and deletes remain isolated between sources',
    () async {
      await range();
      final otherDirectory = await Directory(p.join(directory.path, 'other'))
          .create();
      await File(p.join(otherDirectory.path, 'Film.mkv'))
          .writeAsString('fixture');
      final other = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'other',
        location: otherDirectory.path,
        minimumFileSize: 0,
      );
      await sources.scan(other.id);
      final otherId = (sourceId: other.id, localId: 'Film.mkv');
      await markers.setManualBoundary(
        otherId,
        PlaybackMarkerKind.intro,
        isStart: false,
        at: const Duration(seconds: 30),
      );
      final own = (await markers.read(id())).single;
      final foreign = (await markers.read(otherId)).single;
      expect(own.id, isNot(foreign.id));
      await session.deletePlaybackMarker(own.id);
      expect(await markers.read(id()), isEmpty);
      expect(await markers.read(otherId), hasLength(1));
    },
  );

  test('unknown skip preference uses original prompt default', () async {
    await sources.database.customStatement(
      "INSERT INTO player_preferences(key,value) VALUES('global.videoMarkerSkipBehavior','future')",
    );
    expect(
      await PlayerPreferencesRepository(sources.database).markerSkipBehavior,
      VideoMarkerSkipBehavior.prompt,
    );
  });

  test(
    'database reopen restores ranges and automatic policy before resume',
    () async {
      await range(start: 0, end: 20);
      await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
      await session.refreshQueue();
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
      sources = SourceRepository(
        database: LibraryDatabase(
          NativeDatabase(File(p.join(directory.path, 'library.sqlite'))),
        ),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      markers = PlaybackMarkerRepository(sources.database);
      session = createSession();
      await session.open(id());
      await session.refreshQueue();
      expect(
        session.precision.value.skipBehavior,
        VideoMarkerSkipBehavior.automatic,
      );
      expect(session.clock.position, const Duration(seconds: 20));
      expect(
        session.precision.value.markers.single.end,
        const Duration(seconds: 20),
      );
    },
  );

  test(
    'failed delete keeps the prompt and successful delete removes it',
    () async {
      await range();
      engines.last.emit(position: const Duration(seconds: 12));
      final marker = session.precision.value.activeSkipMarker!;
      await sources.database.customStatement(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON playback_markers BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await session.deletePlaybackMarker(marker.id);
      expect(session.controlError, isNotNull);
      expect(session.precision.value.activeSkipMarker!.id, marker.id);
      await sources.database.customStatement('DROP TRIGGER fail_delete');
      await session.deletePlaybackMarker(marker.id);
      expect(session.precision.value.activeSkipMarker, isNull);
      expect(session.controlError, isNull);
    },
  );

  test(
    'a queued boundary command does not write into a newly selected film',
    () async {
      final old = engines.last;
      old.volumeGate = Completer<void>();
      old.volumeEntered = Completer<void>();
      final blocked = session.volume(50);
      await old.volumeEntered!.future;
      final switching = session.open(id('Next.mkv'));
      final edit = session.setMarkerBoundary(
        PlaybackMarkerKind.intro,
        isStart: true,
        at: const Duration(seconds: 12),
      );
      old.volumeGate!.complete();
      await blocked;
      await switching;
      await edit;
      expect(await markers.read(id()), isEmpty);
      expect(await markers.read(id('Next.mkv')), isEmpty);
    },
  );

  test('credits skip keeps the configured EOF action', () async {
    await session.setMarkerBoundary(
      PlaybackMarkerKind.credits,
      isStart: true,
      at: const Duration(seconds: 80),
    );
    await session.setMarkerBoundary(
      PlaybackMarkerKind.credits,
      isStart: false,
      at: const Duration(seconds: 100),
    );
    await session.setEndAction(VideoEndAction.closeWindow);
    await session.setMarkerSkipBehavior(VideoMarkerSkipBehavior.automatic);
    engines.last.emit(position: const Duration(seconds: 85));
    await session.refreshQueue();
    expect(session.clock.position, const Duration(seconds: 100));
    expect(session.closeRequests.value, 0);
    engines.last.emit(completed: true, playing: false);
    await session.refreshQueue();
    expect(session.closeRequests.value, 1);
  });
}
