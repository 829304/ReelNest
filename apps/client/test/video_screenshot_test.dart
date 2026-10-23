import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/data/video_screenshot_store.dart';
import 'package:reelnest/features/playback/domain/video_screenshot.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_screenshot_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/pictures_directory.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import 'support/fake_video_engine.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _Engine extends FakeVideoEngine implements VideoScreenshotEngine {
  bool disposed = false;
  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }

  final modes = <VideoScreenshotMode>[];
  Completer<void>? gate, started;
  bool fail = false;
  @override
  Future<Uint8List> captureCurrentFrame(VideoScreenshotMode mode) async {
    modes.add(mode);
    started?.complete();
    if (gate != null) await gate!.future;
    if (fail) throw StateError('Authenticated URL/path must not reach UI');
    return _png;
  }
}

void main() {
  test('original modes, default, PNG geometry and invalid data limits', () {
    expect(VideoScreenshotMode.values.map((m) => m.label), [
      '带字幕',
      '纯视频',
      '窗口所见',
    ]);
    expect(
      VideoScreenshotMode.fromStorage(null),
      VideoScreenshotMode.subtitles,
    );
    expect(
      VideoScreenshotMode.fromStorage('invalid'),
      VideoScreenshotMode.subtitles,
    );
    for (final mode in VideoScreenshotMode.values) {
      expect(VideoScreenshotMode.fromStorage(mode.name), mode);
    }
    VideoScreenshotLimits.png(_png);
    VideoScreenshotLimits.dimensions(7680, 4320);
    expect(
      () => VideoScreenshotLimits.png(Uint8List(8)),
      throwsA(isA<VideoScreenshotFailure>()),
    );
    final oversized = Uint8List.fromList(_png);
    ByteData.sublistView(oversized).setUint32(16, 20000);
    expect(
      () => VideoScreenshotLimits.png(oversized),
      throwsA(isA<VideoScreenshotFailure>()),
    );
    expect(
      () => VideoScreenshotLimits.dimensions(0, 1080),
      throwsA(isA<VideoScreenshotFailure>()),
    );
  });
  test('filenames retain Unicode, original timestamp, bounded graphemes and safe paths', () {
    final at = DateTime(2026, 10, 22, 10, 20, 30);
    expect(
      VideoScreenshotStore.filename('电影/剧集:*?\n', at),
      '电影 剧集 2026-10-22 10.20.30.png',
    );
    expect(
      VideoScreenshotStore.filename('....', at),
      '视频截图 2026-10-22 10.20.30.png',
    );
    expect(
      VideoScreenshotStore.filename('😀' * 70, at).startsWith('😀' * 56),
      isTrue,
    );
    final long = VideoScreenshotStore.filename('e${'\u0301' * 500}', at);
    expect(long, startsWith('视频截图'));
    expect(p.basename(long), long);
  });
  test(
    'Linux Pictures uses safe absolute XDG data with no shell expansion',
    () {
      expect(linuxPicturesPath('/home/me', null), '/home/me/Pictures');
      expect(
        linuxPicturesPath('/home/me', r'XDG_PICTURES_DIR="$HOME/图片"'),
        '/home/me/图片',
      );
      expect(
        linuxPicturesPath('/home/me', r'XDG_PICTURES_DIR="${HOME}/Screens"'),
        '/home/me/Screens',
      );
      expect(
        linuxPicturesPath('/home/me', 'XDG_PICTURES_DIR="/mnt/photos"'),
        '/mnt/photos',
      );
      expect(
        linuxPicturesPath('/home/me', r'XDG_PICTURES_DIR="$(evil)/Pictures"'),
        '/home/me/Pictures',
      );
      expect(
        linuxPicturesPath('/home/me', 'XDG_PICTURES_DIR="relative"'),
        '/home/me/Pictures',
      );
    },
  );

  late Directory sandbox;
  setUp(
    () async =>
        sandbox = await Directory.systemTemp.createTemp('reelnest-screenshot-'),
  );
  tearDown(() async {
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-screenshot-'));
    await sandbox.delete(recursive: true);
  });
  VideoScreenshotStore store({Future<Directory> Function()? directory}) =>
      VideoScreenshotStore(
        directory:
            directory ??
            () => RuntimeStoragePaths(
              root: sandbox,
              portable: true,
            ).screenshots(),
        now: () => DateTime(2026, 10, 22, 10, 20, 30),
      );
  test('concurrent screenshots reserve unique PNGs without overwriting existing files', () async {
    final folder = await RuntimeStoragePaths(
      root: sandbox,
      portable: true,
    ).screenshots();
    final old = File(p.join(folder.path, 'Film 2026-10-22 10.20.30.png'));
    await old.writeAsString('preserved');
    final paths = await Future.wait(
      List.generate(12, (_) => store().save('Film', _png)),
    );
    expect(paths.toSet(), hasLength(12));
    expect(await old.readAsString(), 'preserved');
    for (final path in paths) {
      expect(
        p.isWithin(p.join(sandbox.path, 'userdata', 'screenshots'), path),
        isTrue,
      );
      expect(await File(path).readAsBytes(), _png);
    }
    expect(await folder.list().length, 13); // No staging dirs or reservations.
  });
  test('unwritable directory and invalid PNG do not overwrite or leave staging output', () async {
    final blocker = File(p.join(sandbox.path, 'blocked'));
    await blocker.writeAsString('keep');
    final broken = store(directory: () async => Directory(blocker.path));
    await expectLater(
      broken.save('Film', _png),
      throwsA(isA<VideoScreenshotFailure>()),
    );
    await expectLater(
      store().save('Film', Uint8List(10)),
      throwsA(isA<VideoScreenshotFailure>()),
    );
    expect(await blocker.readAsString(), 'keep');
    expect(await sandbox.list().length, 1);
  });
  test(
    'portable screenshot directories reject external junctions before writing',
    () async {
      final outside = await Directory(p.join(sandbox.path, 'outside')).create();
      final program = await Directory(p.join(sandbox.path, 'program')).create();
      final userdata = await Directory(p.join(program.path, 'userdata'))
          .create();
      final alias = p.join(userdata.path, 'screenshots');
      if (Platform.isWindows) {
        final result = await Process.run(
          'powershell.exe',
          [
            '-NoProfile',
            '-Command',
            'New-Item -ItemType Junction -Path \$env:REELNEST_TEST_SCREENSHOT_ALIAS -Target \$env:REELNEST_TEST_SCREENSHOT_OUTSIDE -ErrorAction Stop | Out-Null',
          ],
          environment: {
            'REELNEST_TEST_SCREENSHOT_ALIAS': alias,
            'REELNEST_TEST_SCREENSHOT_OUTSIDE': outside.path,
          },
        );
        expect(result.exitCode, 0);
      } else {
        await Link(alias).create(outside.path);
      }
      try {
        final guarded = VideoScreenshotStore(
          directory: () =>
              RuntimeStoragePaths(root: program, portable: true).screenshots(),
        );
        await expectLater(
          guarded.save('Film', _png),
          throwsA(isA<VideoScreenshotFailure>()),
        );
        expect(await outside.list().length, 0);
      } finally {
        await Link(alias).delete();
      }
    },
  );

  group('session and persistence', () {
    late SourceRepository sources;
    late PlayerPreferencesRepository preferences;
    late PlaybackSession session;
    late MediaIdentity film, second;
    final engines = <_Engine>[];
    PlaybackSession create() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      screenshotStore: store(),
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final e = _Engine();
        engines.add(e);
        return e;
      },
    );
    setUp(() async {
      engines.clear();
      for (final name in ['First.mkv', 'Second.mkv']) {
        await File(p.join(sandbox.path, name)).writeAsString('fixture');
      }
      sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture',
      );
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Test',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      film = (sourceId: source.id, localId: 'First.mkv');
      second = (sourceId: source.id, localId: 'Second.mkv');
      preferences = PlayerPreferencesRepository(sources.database);
      session = create();
    });
    tearDown(() async {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
    });
    test('all modes preserve playback clock, volume and tracks and restore on another film/session', () async {
      expect(session.canCaptureFrame, isFalse);
      await session.open(film);
      engines.last.emit(position: const Duration(seconds: 7), playing: true);
      final clock = session.clock;
      for (final mode in VideoScreenshotMode.values) {
        await session.setScreenshotMode(mode);
        final result = await session.captureCurrentFrame();
        expect(await File(result).readAsBytes(), _png);
        expect(engines.last.modes.last, mode);
        expect(session.clock, clock);
        expect(session.capturingFrame, isFalse);
      }
      await session.open(second);
      expect(session.screenshotMode, VideoScreenshotMode.window);
      await session.close(discardProgress: true);
      session.dispose();
      session = create();
      await session.open(film);
      expect(session.screenshotMode, VideoScreenshotMode.window);
    });
    test('failed preference write preserves mode; invalid value restores original default', () async {
      await session.open(film);
      await sources.database.customStatement(
        "CREATE TRIGGER reject_screenshot BEFORE INSERT ON player_preferences WHEN NEW.key='global.videoScreenshotMode' BEGIN SELECT RAISE(ABORT,'fixture'); END",
      );
      await session.setScreenshotMode(VideoScreenshotMode.video);
      expect(session.screenshotMode, VideoScreenshotMode.subtitles);
      expect(session.controlError, contains('截图内容设置保存失败'));
      await sources.database.customStatement('DROP TRIGGER reject_screenshot');
      await sources.database.customStatement(
        "INSERT INTO player_preferences VALUES('global.videoScreenshotMode','unknown')",
      );
      await session.open(second);
      expect(session.screenshotMode, VideoScreenshotMode.subtitles);
    });
    test(
      'capture errors are safe and retry retains the playing decoder',
      () async {
        await session.open(film);
        final engine = engines.last..fail = true;
        await expectLater(
          session.captureCurrentFrame(),
          throwsA(
            isA<VideoScreenshotFailure>().having(
              (e) => e.message,
              'safe message',
              isNot(contains('Authenticated')),
            ),
          ),
        );
        expect(engine.disposed, isFalse);
        expect(session.error, isNull);
        expect(session.capturingFrame, isFalse);
        engine.fail = false;
        expect(
          await File(await session.captureCurrentFrame()).exists(),
          isTrue,
        );
      },
    );
    test(
      'in-flight capture blocks duplicates and serializes a film switch',
      () async {
        await session.open(film);
        final engine = engines.last;
        engine.gate = Completer<void>();
        engine.started = Completer<void>();
        final capture = session.captureCurrentFrame();
        await engine.started!.future;
        await expectLater(
          session.captureCurrentFrame(),
          throwsA(isA<VideoScreenshotFailure>()),
        );
        final change = session.open(second);
        expect(engine.disposed, isFalse);
        engine.gate!.complete();
        final path = await capture;
        await change;
        expect(p.basename(path), startsWith('First '));
        expect(engine.disposed, isTrue);
        expect(session.item!.identity, second);
      },
    );
    test('close waits for native capture before disposal and cancels unsaved output', () async {
      await session.open(film);
      final engine = engines.last;
      engine.gate = Completer<void>();
      engine.started = Completer<void>();
      final capture = expectLater(
        session.captureCurrentFrame(),
        throwsA(isA<VideoScreenshotFailure>()),
      );
      await engine.started!.future;
      final closing = session.close(discardProgress: true);
      expect(engine.disposed, isFalse);
      engine.gate!.complete();
      await capture;
      await closing;
      expect(engine.disposed, isTrue);
      expect(
        await Directory(p.join(sandbox.path, 'userdata', 'screenshots'))
            .exists(),
        isFalse,
      );
    });
  });
}
