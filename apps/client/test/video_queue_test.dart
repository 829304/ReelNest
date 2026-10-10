import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/video_queue.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

IndexedMedia media(
  String id, {
  String source = 'a',
  String? parent,
  int? season,
  int? episode,
  String? title,
  bool series = false,
  String type = 'episode',
}) => IndexedMedia(
  identity: (sourceId: source, localId: id),
  title: title ?? id,
  type: type,
  bytes: 10,
  modified: DateTime.utc(2026),
  parentId: parent,
  seasonNumber: season,
  episodeNumber: episode,
  isSeries: series,
);

void main() {
  test('visible suffix differs from full manual adjacency across seasons', () {
    final parent = media('show', series: true);
    final special = media('special', parent: 'show', season: 0, episode: 1);
    final a = media('one', parent: 'show', season: 1, episode: 1);
    final b = media('two', parent: 'show', season: 1, episode: 2);
    final c = media('three', parent: 'show', season: 2, episode: 1);
    final other = media(
      'one',
      source: 'b',
      parent: 'show',
      season: 1,
      episode: 1,
    );
    final queue = VideoQueue.forItem(b, [c, b, parent, other, a, special]);
    expect(queue.items, [b, c]);
    expect(queue.adjacent(b.identity, -1), a);
    expect(queue.adjacent(special.identity, -1), isNull);
    expect(queue.adjacent(c.identity, 1), isNull);
    expect(queue.adjacent(b.identity, 0), c);
    expect(queue.adjacent(other.identity, 1), isNull);
  });
  test('natural title order and absent parent fallback match original', () {
    final parent = media('show', series: true);
    final a = media('a', parent: 'show', title: 'Episode 2');
    final b = media('b', parent: 'show', title: 'Episode 10');
    expect(VideoQueue.forItem(a, [b, parent, a]).items, [a, b]);
    expect(VideoQueue.forItem(a, [b, a]).items, [a]);
  });
  test(
    'films have a singleton autoplay queue and manual adjacency does not wrap',
    () {
      final a = media('a', type: 'movie');
      final b = media('b', type: 'movie');
      final queue = VideoQueue.forItem(a, [
        a,
        media('song', type: 'music'),
        media('image', type: 'photo'),
        b,
      ]);
      expect(queue.items, [a]);
      expect(queue.adjacent(a.identity, 1), b);
      expect(queue.adjacent(a.identity, -1), isNull);
    },
  );

  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackRepository records;
  late PlayerPreferencesRepository preferences;
  late PlaybackSession session;
  late MediaSource source;
  final engines = <FakeVideoEngine>[];
  var failNext = false;
  var resourcesClosed = false;
  MediaIdentity id(int n) => (sourceId: source.id, localId: 'Show.S01E0$n.mkv');

  setUp(() async {
    engines.clear();
    failNext = false;
    resourcesClosed = false;
    sandbox = await Directory.systemTemp.createTemp('reelnest-queue-test-');
    for (var n = 1; n <= 3; n++) {
      await File(p.join(sandbox.path, 'Show.S01E0$n.mkv'))
          .writeAsString('fake');
    }
    await File(p.join(sandbox.path, 'Film.mkv')).writeAsString('fake');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    records = PlaybackRepository(sources.database);
    preferences = PlayerPreferencesRepository(sources.database);
    session = PlaybackSession(
      sources: sources,
      records: records,
      createEngine: () {
        final engine = FakeVideoEngine()..failOpen = failNext;
        failNext = false;
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
    expect(p.basename(sandbox.path), startsWith('reelnest-queue-test-'));
    await sandbox.delete(recursive: true);
  });

  Future<void> rejectProgress() => sources.database.customStatement(
    "CREATE TRIGGER reject_queue_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'fixture'); END",
  );

  test(
    'top-level adjacency follows persisted update time across sources',
    () async {
      final otherRoot = Directory(p.join(sandbox.path, 'other'));
      await otherRoot.create();
      await File(p.join(otherRoot.path, 'Other.mkv')).writeAsString('fake');
      final other = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Other',
        location: otherRoot.path,
        minimumFileSize: 0,
      );
      await sources.scan(other.id);
      final film = (sourceId: source.id, localId: 'Film.mkv');
      final otherFilm = (sourceId: other.id, localId: 'Other.mkv');
      await records.save(
        film,
        position: const Duration(seconds: 3),
        duration: const Duration(seconds: 100),
        playedAt: DateTime.utc(2100),
      );
      final inventory = await sources.inventory();
      final current = inventory.items.firstWhere((i) => i.identity == film);
      expect(current.updatedAt, DateTime.utc(2100));
      final queue = VideoQueue.forItem(current, inventory.items);
      expect(queue.sequence.first.identity, film);
      expect(queue.adjacent(film, 1)?.identity, otherFilm);
      await sources.remove(other.id);
      final rows = await sources.database
          .customSelect(
            "SELECT * FROM media_activity WHERE source_id = '${other.id}'",
          )
          .get();
      expect(rows, isEmpty);
    },
  );

  test(
    'failed progress transaction does not change media update time',
    () async {
      final before = (await sources.inventory()).items
          .firstWhere((i) => i.identity == id(1))
          .updatedAt;
      await rejectProgress();
      await expectLater(
        records.save(
          id(1),
          position: const Duration(seconds: 3),
          duration: const Duration(seconds: 100),
          playedAt: DateTime.utc(2100),
        ),
        throwsA(anything),
      );
      expect(
        (await sources.inventory()).items
            .firstWhere((i) => i.identity == id(1))
            .updatedAt,
        before,
      );
    },
  );

  test(
    'queue record batches preserve source identity and absent-record defaults',
    () async {
      await records.save(
        id(2),
        position: const Duration(seconds: 95),
        duration: const Duration(seconds: 100),
      );
      final unknown = List.generate(
        405,
        (n) => (sourceId: 'unknown', localId: '$n'),
      );
      final values = await records.readMany([id(1), id(2), ...unknown, id(2)]);
      expect(values.length, 407);
      expect(values[id(2)]!.watched, isTrue);
      expect(values[id(1)]!.lastPlayedAt, isNull);
      expect(values[unknown.last]!.position, Duration.zero);
      expect(await records.readMany([]), isEmpty);
    },
  );

  test(
    'manual next/previous saves, resumes and rebuilds suffix without wrapping',
    () async {
      await records.save(
        id(2),
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      await session.open(id(1));
      expect(session.queue.items.length, 3);
      engines.single.emit(position: const Duration(seconds: 37));
      await session.adjacent(1);
      expect((await records.read(id(1))).position.inSeconds, 37);
      expect(engines.last.openedAt!.inSeconds, 20);
      expect(session.queue.items.map((i) => i.identity), [id(2), id(3)]);
      await session.adjacent(-1);
      expect(session.item!.identity, id(1));
      final current = session.engine;
      await session.adjacent(-1);
      expect(session.transitionMessage, '已经是第一集');
      expect(session.engine, same(current));
      await session.open(id(3));
      final last = session.engine;
      await session.adjacent(1);
      expect(session.transitionMessage, '已经是最后一集');
      expect(session.engine, same(last));
    },
  );
  test('missing target preserves running decoder and old clock', () async {
    await session.open(id(1));
    engines.single.emit(position: const Duration(seconds: 17));
    await File(p.join(sandbox.path, id(2).localId)).delete();
    await session.adjacent(1);
    expect(session.item!.identity, id(1));
    expect(engines.single.disposals, 0);
    expect(session.clock.playing, isTrue);
    expect(session.clock.position.inSeconds, 17);
    expect(session.error, isNull);
    expect(session.transitionMessage, isNotNull);
  });
  test(
    'invalid target decoder is disposed while previous one stays usable',
    () async {
      await session.open(id(1));
      engines.single.emit(position: const Duration(seconds: 17));
      failNext = true;
      await session.adjacent(1);
      expect(engines.length, 2);
      expect(engines.first.disposals, 0);
      expect(engines.last.disposals, 1);
      expect(session.engine, same(engines.first));
      expect(session.item!.identity, id(1));
      expect(session.clock.playing, isTrue);
      await session.seek(const Duration(seconds: 20));
      expect(session.clock.position.inSeconds, 20);
      await session.adjacent(1);
      expect(session.item!.identity, id(2));
    },
  );
  test(
    'failed save blocks manual switch without creating another decoder',
    () async {
      await session.open(id(1));
      engines.single.emit(position: const Duration(seconds: 17));
      await rejectProgress();
      await session.adjacent(1);
      expect(session.saveError, isNotNull);
      expect(session.item!.identity, id(1));
      expect(engines.single.disposals, 0);
      await sources.database.customStatement(
        'DROP TRIGGER reject_queue_progress',
      );
      await session.adjacent(1);
      expect(session.item!.identity, id(2));
      expect((await records.read(id(1))).position.inSeconds, 17);
    },
  );
  test(
    'duplicate EOF advances once and saves completed duration before next',
    () async {
      await session.open(id(1));
      final finished = engines.single;
      finished.emit(position: Duration.zero, completed: true, playing: false);
      finished.emit(completed: true, playing: false);
      await session.refreshQueue();
      expect(session.item!.identity, id(2));
      expect(engines.length, 2);
      expect((await records.read(id(1))).position.inSeconds, 100);
      expect((await records.read(id(1))).watched, isTrue);
    },
  );
  test(
    'last episode and film EOF hold even with automatic-next selected',
    () async {
      await session.open(id(3));
      engines.last.emit(completed: true, playing: false);
      await session.refreshQueue();
      expect(session.item!.identity, id(3));
      expect(engines.length, 1);
      final film = (sourceId: source.id, localId: 'Film.mkv');
      await session.open(film);
      engines.last.emit(completed: true, playing: false);
      await session.refreshQueue();
      expect(session.item!.identity, film);
      expect(engines.length, 2);
      expect(session.clock.completed, isTrue);
    },
  );
  test('hold action persists and seeking back rearms completion', () async {
    await session.open(id(1));
    await session.setEndAction(VideoEndAction.holdLastFrame);
    expect(await preferences.endAction, VideoEndAction.holdLastFrame);
    engines.single.emit(completed: true, playing: false);
    await session.refreshQueue();
    expect(session.item!.identity, id(1));
    await session.seek(const Duration(seconds: 3));
    await session.setEndAction(VideoEndAction.nextEpisode);
    engines.single.emit(completed: true, playing: false);
    await session.refreshQueue();
    expect(session.item!.identity, id(2));
  });
  test(
    'close action requests window close once only after successful save',
    () async {
      await session.open(id(1));
      await session.setEndAction(VideoEndAction.closeWindow);
      engines.single.emit(completed: true, playing: false);
      engines.single.emit(completed: true, playing: false);
      await session.refreshQueue();
      expect(session.closeRequests.value, 1);
      expect((await records.read(id(1))).watched, isTrue);
      expect(session.engine, isNotNull);
    },
  );
  test('save failure suppresses EOF advance and window close', () async {
    await session.open(id(1));
    await rejectProgress();
    engines.single.emit(completed: true, playing: false);
    await session.refreshQueue();
    expect(session.saveError, isNotNull);
    expect(engines.length, 1);
    await session.seek(const Duration(seconds: 10));
    await session.setEndAction(VideoEndAction.closeWindow);
    engines.single.emit(completed: true, playing: false);
    await session.refreshQueue();
    expect(session.closeRequests.value, 0);
    expect(engines.single.disposals, 0);
  });
  test('stale EOF cannot advance a newer manual selection', () async {
    await session.open(id(1));
    final switching = session.open(id(3));
    engines.single.emit(completed: true, playing: false);
    await switching;
    await session.refreshQueue();
    expect(session.item!.identity, id(3));
    expect(engines.length, 2);
  });
  test(
    'end setting failure retains previous value and reopening remembers choice',
    () async {
      expect(await preferences.endAction, VideoEndAction.nextEpisode);
      await session.open(id(1));
      await session.setEndAction(VideoEndAction.holdLastFrame);
      await sources.database.customStatement(
        "CREATE TRIGGER reject_end_setting BEFORE INSERT ON player_preferences BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      await session.setEndAction(VideoEndAction.closeWindow);
      expect(session.endAction, VideoEndAction.holdLastFrame);
      expect(session.controlError, isNotNull);
      await sources.database.customStatement('DROP TRIGGER reject_end_setting');
      await session.open(id(2));
      expect(session.endAction, VideoEndAction.holdLastFrame);
    },
  );

  testWidgets('toolbar queue, switching and end-action panel are usable', (
    tester,
  ) async {
    Future<void> finish(Future<void> future) async {
      var done = false;
      future.then((_) => done = true);
      for (var i = 0; i < 200 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done, isTrue);
      // Playback commits after the surface frame; render the final controls
      // state scheduled by that commit before sending the next pointer event.
      await tester.pump();
    }

    var closes = 0;
    try {
      await finish(session.open(id(1)));
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: id(1),
            session: session,
            closeWindow: () async {
              closes++;
            },
            setFullscreen: (_) async {},
          ),
        ),
      );
      await finish(session.refreshQueue());
      await tester.tap(find.byTooltip('剧集列表'));
      await tester.pump();
      await finish(session.refreshQueue());
      expect(find.text('3 集'), findsOneWidget);
      expect(find.textContaining('正在播放'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('episode-${source.id}-${id(2).localId}')),
      );
      await finish(session.refreshQueue());
      expect(session.item!.identity, id(2));
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.tap(find.byTooltip('上一集'));
      await finish(session.refreshQueue());
      expect(session.item!.identity, id(1));
      await tester.tap(find.byTooltip('播放器设置'));
      await tester.pump();
      await tester.tap(find.text('打开内置播放器设置'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('end-action-closeWindow')));
      await finish(session.refreshQueue());
      engines.last.emit(completed: true, playing: false);
      await finish(session.refreshQueue());
      expect(closes, 1);
      expect(session.engine, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await finish(session.close(discardProgress: true));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    }
  });
}
