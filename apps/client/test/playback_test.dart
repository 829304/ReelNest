import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackRepository records;
  late PlaybackSession session;
  late MediaIdentity film;
  late MediaSource source;
  late String? mount;
  var resourcesClosed = false;
  final engines = <FakeVideoEngine>[];
  setUp(() async {
    resourcesClosed = false;
    engines.clear();
    mount = 'fixture-volume';
    sandbox = await Directory.systemTemp.createTemp('reelnest-playback-test-');
    await File(p.join(sandbox.path, 'Film.mkv'))
        .writeAsString('fake engine fixture');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => mount,
    );
    records = PlaybackRepository(sources.database);
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    film = (sourceId: source.id, localId: 'Film.mkv');
    session = PlaybackSession(
      sources: sources,
      records: records,
      createEngine: () {
        final engine = FakeVideoEngine();
        engines.add(engine);
        return engine;
      },
    );
  });
  tearDown(() async {
    if (!resourcesClosed) {
      await session.close();
      session.dispose();
      await sources.close();
    }
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-playback-test-'));
    await sandbox.delete(recursive: true);
  });
  test('resume threshold and rewind follow the original defaults', () {
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(seconds: 10),
      ).resumePosition,
      const Duration(seconds: 10),
    );
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(milliseconds: 10001),
      ).resumePosition,
      const Duration(milliseconds: 5001),
    );
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(seconds: 35),
      ).resumePosition,
      const Duration(seconds: 30),
    );
  });
  test('watched is sticky at 90 percent and rescan keeps progress', () async {
    await records.save(
      film,
      position: const Duration(seconds: 89),
      duration: const Duration(seconds: 100),
    );
    expect((await records.read(film)).watched, isFalse);
    await records.save(
      film,
      position: const Duration(seconds: 90),
      duration: const Duration(seconds: 100),
    );
    await records.save(
      film,
      position: const Duration(seconds: 3),
      duration: const Duration(seconds: 100),
    );
    await sources.scan(source.id);
    final record = await records.read(film);
    expect(record.watched, isTrue);
    expect(record.position, const Duration(seconds: 3));
    expect(record.lastPlayedAt, isNotNull);
  });
  test('unknown clock does not erase a saved position', () async {
    await records.save(
      film,
      position: const Duration(seconds: 15),
      duration: const Duration(seconds: 100),
    );
    await records.save(film, position: Duration.zero, duration: Duration.zero);
    expect((await records.read(film)).position, const Duration(seconds: 15));
  });
  test(
    'sources are isolated and deletion cannot recreate stale playback rows',
    () async {
      final nested = Directory(p.join(sandbox.path, 'other'));
      await nested.create();
      await File(p.join(nested.path, 'Film.mkv')).writeAsString('other');
      final other = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Other',
        location: nested.path,
        minimumFileSize: 0,
      );
      await sources.scan(other.id);
      await records.save(
        film,
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 100),
      );
      final otherId = (sourceId: other.id, localId: 'Film.mkv');
      expect((await records.read(otherId)).lastPlayedAt, isNull);
      await sources.remove(source.id);
      await records.save(
        film,
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 100),
      );
      expect((await records.read(film)).lastPlayedAt, isNull);
      expect((await sources.browse(other.id)).total, 1);
    },
  );
  test(
    'session resumes, pauses, clamps commands, saves and disposes exactly once',
    () async {
      await records.save(
        film,
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      await session.open(film);
      expect(engines.single.openedAt, const Duration(seconds: 20));
      engines.single.emit(position: const Duration(seconds: 35));
      await session.toggle();
      expect((await records.read(film)).position, const Duration(seconds: 35));
      await session.seek(const Duration(seconds: -10));
      expect(session.clock.position, Duration.zero);
      await session.seek(const Duration(seconds: 1000));
      expect(session.clock.position, const Duration(seconds: 100));
      await session.volume(500);
      expect(session.clock.volume, 100);
      await session.close();
      await session.close();
      expect(engines.single.disposals, 1);
      expect((await records.read(film)).watched, isTrue);
    },
  );
  test(
    'missing or changed mount never allocates a decoder or resets progress',
    () async {
      await records.save(
        film,
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      mount = null;
      await session.open(film);
      expect(session.loading, isFalse);
      expect(session.error, contains('NAS'));
      expect(engines, isEmpty);
      mount = 'fixture-volume';
      await File(p.join(sandbox.path, 'Film.mkv')).delete();
      await session.open(film);
      expect(engines, isEmpty);
      expect((await records.read(film)).position, const Duration(seconds: 25));
    },
  );
  test(
    'decoder failure ends loading and preserves the original resume point',
    () async {
      await records.save(
        film,
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      final failing = PlaybackSession(
        sources: sources,
        records: records,
        createEngine: () => FakeVideoEngine()..failOpen = true,
      );
      await failing.open(film);
      expect(failing.loading, isFalse);
      expect(failing.error, isNotNull);
      expect(failing.engine, isNull);
      expect((await records.read(film)).position, const Duration(seconds: 25));
      await failing.close();
      failing.dispose();
    },
  );
  test(
    'switching files commits the old clock before creating the next decoder',
    () async {
      await File(p.join(sandbox.path, 'Second.mkv')).writeAsString('second');
      await sources.scan(source.id);
      final second = (sourceId: source.id, localId: 'Second.mkv');
      await session.open(film);
      engines.single.emit(position: const Duration(seconds: 37));
      await session.open(second);
      expect((await records.read(film)).position, const Duration(seconds: 37));
      expect(engines.first.disposals, 1);
      expect(engines.last.openedAt, Duration.zero);
      expect((await records.read(second)).lastPlayedAt, isNull);
    },
  );
  test(
    'completion saves duration even when the decoder resets its clock',
    () async {
      await session.open(film);
      engines.single.emit(position: Duration.zero, completed: true);
      await session.save();
      expect((await records.read(film)).position, const Duration(seconds: 100));
      expect((await records.read(film)).watched, isTrue);
    },
  );
  test('write failure is visible and may be retried without losing the current clock', () async {
    await session.open(film);
    engines.single.emit(position: const Duration(seconds: 22));
    await sources.database.customStatement(
      "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await session.close();
    expect(session.saveError, isNotNull);
    await sources.database.customStatement('DROP TRIGGER reject_progress');
    await session.save();
    expect(session.saveError, isNull);
    expect((await records.read(film)).position, const Duration(seconds: 22));
  });
  test(
    'failed close keeps the decoder usable until a successful retry',
    () async {
      await session.open(film);
      final decoder = engines.single;
      decoder.emit(position: const Duration(seconds: 22));
      await sources.database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      try {
        await session.close();
        expect(session.saveError, isNotNull);
        expect(session.engine, same(decoder));
        expect(decoder.disposals, 0);
        await session.toggle();
        expect(session.clock.playing, isTrue);
        await session.seek(const Duration(seconds: 31));
        await session.close();
        expect(session.engine, same(decoder));
        expect(decoder.disposals, 0);
      } finally {
        await sources.database.customStatement('DROP TRIGGER reject_progress');
      }
      await session.close();
      expect(session.engine, isNull);
      expect(decoder.disposals, 1);
      expect((await records.read(film)).position, const Duration(seconds: 31));
    },
  );

  test(
    'explicit discard closes exactly once after a failed checkpoint',
    () async {
      await session.open(film);
      final decoder = engines.single;
      decoder.emit(position: const Duration(seconds: 22));
      await sources.database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      try {
        await session.close();
        expect(decoder.disposals, 0);
        await session.close(discardProgress: true);
        await session.close();
        expect(decoder.disposals, 1);
        expect(session.engine, isNull);
        expect((await records.read(film)).lastPlayedAt, isNull);
      } finally {
        await sources.database.customStatement('DROP TRIGGER reject_progress');
      }
    },
  );

  test(
    'failed checkpoint prevents switching and preserves the retryable clock',
    () async {
      await File(p.join(sandbox.path, 'Second.mkv')).writeAsString('second');
      await sources.scan(source.id);
      await session.open(film);
      engines.single.emit(position: const Duration(seconds: 37));
      await sources.database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      final second = (sourceId: source.id, localId: 'Second.mkv');
      await session.open(second);
      expect(session.saveError, isNotNull);
      expect(session.item!.identity, film);
      expect(engines.single.disposals, 0);
      await sources.database.customStatement('DROP TRIGGER reject_progress');
      await session.open(second);
      expect(session.saveError, isNull);
      expect((await records.read(film)).position, const Duration(seconds: 37));
      expect(engines.first.disposals, 1);
    },
  );
  test(
    'queued open cannot allocate a decoder after closing is requested',
    () async {
      final opening = session.open(film);
      final closing = session.close();
      await Future.wait([opening, closing]);
      expect(engines, isEmpty);
    },
  );
  test(
    'native command failure is reported without an uncaught future',
    () async {
      await session.open(film);
      await session.toggle();
      engines.single.failCommand = true;
      await session.toggle();
      expect(session.error, contains('操作失败'));
    },
  );

  testWidgets(
    'player controls and keyboard operate the session and close saves progress',
    (tester) async {
      var closed = false;
      var fullscreen = false;
      Future<void> waitUntil(bool Function() done) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (done()) return;
        }
        fail('Player UI did not settle');
      }

      Future<void> finish(Future<void> future) async {
        var done = false;
        future.then((_) => done = true);
        await waitUntil(() => done);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: film,
            session: session,
            closeWindow: () async {
              closed = true;
            },
            setFullscreen: (value) async {
              fullscreen = value;
            },
          ),
        ),
      );
      await waitUntil(
        () => !session.loading && session.clock.duration > Duration.zero,
      );
      expect(session.error, isNull);
      expect(session.loading, isFalse);
      expect(engines, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(session.clock.position, const Duration(seconds: 5));
      await tester.tap(find.byTooltip('播放/暂停'));
      await finish(session.save());
      await tester.pump();
      expect(session.clock.playing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(session.clock.playing, isTrue);
      final slider = find.byKey(const ValueKey('video-timeline'));
      await tester.tapAt(tester.getCenter(slider));
      await tester.pump();
      expect(session.clock.position.inSeconds, inInclusiveRange(45, 55));
      await tester.tap(find.byTooltip('静音'));
      await tester.pump();
      expect(session.clock.volume, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fullscreen, isFalse);
      expect(closed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await finish(session.close());
      await tester.pump();
      expect(closed, isTrue);
      PlaybackRecord? saved;
      await finish(records.read(film).then((record) => saved = record));
      expect(saved!.position.inSeconds, inInclusiveRange(45, 55));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    },
  );
  for (final discard in [false, true]) {
    testWidgets(
      'failed close dialog: ${discard ? 'explicit discard' : 'failed retry stays usable and later closes'}',
      (tester) async {
        var closed = false;
        Future<void> waitUntil(bool Function() done) async {
          for (var i = 0; i < 200; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            if (done()) return;
          }
          fail('Close dialog did not settle');
        }

        Future<void> finish(Future<void> future) async {
          var done = false;
          future.then((_) => done = true);
          await waitUntil(() => done);
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              home: VideoPlayerPage(
                identity: film,
                session: session,
                closeWindow: () async {
                  closed = true;
                },
                setFullscreen: (_) async {},
              ),
            ),
          );
          await waitUntil(
            () => !session.loading && session.clock.duration > Duration.zero,
          );
          final decoder = engines.single;
          decoder.emit(position: const Duration(seconds: 22));
          await finish(
            sources.database.customStatement(
              "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
            ),
          );
          await tester.tap(find.byTooltip('关闭播放器'));
          await waitUntil(() => find.byType(AlertDialog).evaluate().isNotEmpty);
          expect(closed, isFalse);
          expect(session.engine, same(decoder));
          expect(decoder.disposals, 0);
          await tester.tap(find.text(discard ? '仍然关闭' : '重试'));
          if (discard) {
            await waitUntil(() => closed);
            expect(decoder.disposals, 1);
          } else {
            await waitUntil(() => find.byType(AlertDialog).evaluate().isEmpty);
            // Drain the actual retry write before checking commands/window state.
            await finish(session.save());
            expect(closed, isFalse);
            expect(session.saveError, isNotNull);
            expect(session.engine, same(decoder));
            expect(decoder.disposals, 0);
            await tester.tap(find.byTooltip('播放/暂停'));
            await waitUntil(() => session.clock.playing);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await waitUntil(() => session.clock.position.inSeconds == 27);
            await finish(
              sources.database.customStatement('DROP TRIGGER reject_progress'),
            );
            await finish(
              File(p.join(sandbox.path, 'Second.mkv'))
                  .writeAsString('second')
                  .then((_) {}),
            );
            await finish(sources.scan(source.id));
            await finish(
              session.open((sourceId: source.id, localId: 'Second.mkv')),
            );
            expect(session.saveError, isNull);
            expect(decoder.disposals, 1);
            expect(session.item!.identity.localId, 'Second.mkv');
            PlaybackRecord? saved;
            await finish(records.read(film).then((record) => saved = record));
            expect(saved!.position.inSeconds, 27);
            await tester.tap(find.byTooltip('关闭播放器'));
            await waitUntil(() => closed);
            expect(engines.last.disposals, 1);
          }
          expect(session.engine, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await finish(session.close(discardProgress: true));
          await tester.pumpWidget(const SizedBox());
          session.dispose();
          await finish(sources.close());
          resourcesClosed = true;
        }
      },
    );
  }
}
