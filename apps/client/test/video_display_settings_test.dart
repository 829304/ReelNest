import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_display_settings_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _DisplayEngine extends FakeVideoEngine implements VideoDisplayEngine {
  @override
  VideoDisplaySettings displaySettings = const VideoDisplaySettings();
  bool reject = false;
  @override
  Future<void> setDisplaySettings(VideoDisplaySettings value) async {
    if (reject || failControl) throw StateError('Fixture display rejection');
    displaySettings = value;
  }
}

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool fail = false;
  Completer<void>? gate, started;
  void Function()? onFailure;
  @override
  Future<void> rememberDisplaySettings(VideoDisplaySettings value) async {
    final pending = gate;
    gate = null;
    if (pending != null) {
      started?.complete();
      await pending.future;
    }
    if (fail) {
      onFailure?.call();
      throw StateError('Fixture storage failure');
    }
    await super.rememberDisplaySettings(value);
  }
}

class _Mpv {
  final properties = <String, String>{
    'video-aspect-override': 'no',
    'panscan': '0.000000',
    'deinterlace': 'no',
    'video-rotate': '0',
  };
  final filters = <Map<String, Object>>[
    {
      'label': 'quality',
      'name': 'scale',
      'params': {'w': '1280'},
    },
  ];
  final calls = <List<String>>[];
  String? ignoreProperty;
  bool failNextFlip = false, failRollback = false;
  late final commands = MpvDisplaySettingsCommands(
    command: command,
    read: read,
  );
  Future<String> read(String name) async =>
      name == 'vf' ? jsonEncode(filters) : properties[name]!;
  Future<void> command(List<String> args) async {
    calls.add(args);
    if (args.first == 'set') {
      if (args[1] == ignoreProperty) return;
      if (failRollback && args[1] == 'panscan' && args[2] == '0.000000') {
        throw StateError('Rollback rejected');
      }
      properties[args[1]] = args[2];
    } else if (args[1] == 'remove') {
      filters.removeWhere((f) => f['label'] == args[2].substring(1));
    } else if (args[1] == 'add') {
      if (failNextFlip) {
        failNextFlip = false;
        throw StateError('Filter rejected');
      }
      final parts = args[2].substring(1).split(':');
      filters.add({'label': parts[0], 'name': parts[1]});
    }
  }
}

void main() {
  test('original modes, defaults and mpv values are preserved', () {
    expect(VideoAspectOverride.values.map((v) => v.mpvValue), [
      'no',
      '1:1',
      '4:3',
      '16:9',
      '16:10',
      '21:9',
      '2.39:1',
    ]);
    expect(VideoCropMode.values.map((v) => v.panscan), [0, .18, .42, 1]);
    expect(VideoDeinterlaceMode.values.map((v) => v.mpvValue), [
      'no',
      'auto',
      'yes',
    ]);
    expect(VideoRotationMode.values.map((v) => v.degrees), [0, 90, 180, 270]);
    expect(VideoFlipMode.values.map((v) => v.displayName), [
      '关闭',
      '水平',
      '垂直',
      '双向',
    ]);
    expect(
      MpvDisplaySettingsCommands.properties(const VideoDisplaySettings()),
      {
        'video-aspect-override': 'no',
        'panscan': 0.0,
        'deinterlace': 'no',
        'video-rotate': 0,
      },
    );
  });
  test('named flip updates preserve unrelated filters and remove only owned stages', () async {
    final mpv = _Mpv();
    for (final mode in [
      VideoFlipMode.horizontal,
      VideoFlipMode.vertical,
      VideoFlipMode.both,
      VideoFlipMode.none,
    ]) {
      await mpv.commands.apply(VideoDisplaySettings(flipMode: mode));
      expect(mpv.filters.first, {
        'label': 'quality',
        'name': 'scale',
        'params': {'w': '1280'},
      });
      expect(mpv.filters.skip(1).map((f) => f['name']), switch (mode) {
        VideoFlipMode.none => [],
        VideoFlipMode.horizontal => ['hflip'],
        VideoFlipMode.vertical => ['vflip'],
        VideoFlipMode.both => ['hflip', 'vflip'],
      });
    }
    expect(
      mpv.calls.every(
        (c) =>
            !c.contains('hwdec') &&
            !c.contains('seek') &&
            !c.contains('loadfile'),
      ),
      isTrue,
    );
  });
  test(
    'silent property rejection rolls back previously applied values',
    () async {
      final mpv = _Mpv()..ignoreProperty = 'video-rotate';
      final before = Map.of(mpv.properties);
      await expectLater(
        mpv.commands.apply(
          const VideoDisplaySettings(
            aspectOverride: VideoAspectOverride.square,
            cropMode: VideoCropMode.balanced,
            rotationMode: VideoRotationMode.clockwise90,
          ),
        ),
        throwsStateError,
      );
      expect(mpv.properties, before);
      expect(mpv.filters, hasLength(1));
    },
  );
  test('filter failure restores earlier flip and scalar options', () async {
    final mpv = _Mpv();
    await mpv.commands.apply(
      const VideoDisplaySettings(flipMode: VideoFlipMode.horizontal),
    );
    final before = Map.of(mpv.properties);
    mpv.failNextFlip = true;
    await expectLater(
      mpv.commands.apply(
        const VideoDisplaySettings(
          cropMode: VideoCropMode.fill,
          flipMode: VideoFlipMode.both,
        ),
      ),
      throwsStateError,
    );
    expect(mpv.properties, before);
    expect(mpv.filters.map((f) => f['name']), ['scale', 'hflip']);
  });
  test(
    'numeric source aspect is restored with the symbolic no value',
    () async {
      final mpv = _Mpv()..failNextFlip = true;
      mpv.properties['video-aspect-override'] = '0.000000';
      await expectLater(
        mpv.commands.apply(
          const VideoDisplaySettings(
            aspectOverride: VideoAspectOverride.square,
            flipMode: VideoFlipMode.horizontal,
          ),
        ),
        throwsStateError,
      );
      expect(mpv.properties['video-aspect-override'], 'no');
    },
  );
  test(
    'rollback rejection is distinguished from normal apply failure',
    () async {
      final mpv = _Mpv()
        ..ignoreProperty = 'video-rotate'
        ..failRollback = true;
      await expectLater(
        mpv.commands.apply(
          const VideoDisplaySettings(
            cropMode: VideoCropMode.fill,
            rotationMode: VideoRotationMode.clockwise90,
          ),
        ),
        throwsA(isA<VideoDisplayRollbackFailure>()),
      );
    },
  );
  test(
    'numeric aspect readback does not reject equivalent ratio text',
    () async {
      final mpv = _Mpv();
      mpv.properties['video-aspect-override'] = '1.777778';
      await mpv.commands.apply(
        const VideoDisplaySettings(
          aspectOverride: VideoAspectOverride.sixteenByNine,
        ),
      );
      expect(mpv.calls, isEmpty);
      mpv.properties['video-aspect-override'] = '0.000000';
      await mpv.commands.apply(const VideoDisplaySettings());
      expect(mpv.calls, isEmpty);
    },
  );

  group('session and preferences', () {
    late Directory sandbox;
    late SourceRepository sources;
    late _Preferences preferences;
    late PlaybackSession session;
    late MediaIdentity film;
    final engines = <_DisplayEngine>[];
    var rejectOpen = false;
    PlaybackSession makeSession() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final e = _DisplayEngine()..reject = rejectOpen;
        engines.add(e);
        return e;
      },
    );
    setUp(() async {
      engines.clear();
      rejectOpen = false;
      sandbox = await Directory.systemTemp.createTemp(
        'reelnest-display-settings-',
      );
      for (final name in ['First.mkv', 'Second.mkv']) {
        await File(p.join(sandbox.path, name)).writeAsString('fixture');
      }
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
      film = (sourceId: source.id, localId: 'First.mkv');
      preferences = _Preferences(sources.database);
      session = makeSession();
    });
    tearDown(() async {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(
        p.basename(sandbox.path),
        startsWith('reelnest-display-settings-'),
      );
      await sandbox.delete(recursive: true);
    });
    test(
      'changes preserve playback and restore on next item and new session',
      () async {
        expect(await preferences.displaySettings, const VideoDisplaySettings());
        await session.open(film);
        final engine = engines.single;
        engine.emit(position: const Duration(seconds: 9), playing: false);
        const value = VideoDisplaySettings(
          aspectOverride: VideoAspectOverride.cinemaScope,
          cropMode: VideoCropMode.balanced,
          deinterlaceMode: VideoDeinterlaceMode.auto,
          rotationMode: VideoRotationMode.clockwise90,
          flipMode: VideoFlipMode.both,
        );
        await session.updateDisplaySettings((_) => value);
        expect(session.displaySettings, value);
        expect(engine.displaySettings, value);
        expect(engine.clock.position, const Duration(seconds: 9));
        expect(engine.clock.playing, isFalse);
        expect(engine.disposals, 0);
        expect(await preferences.displaySettings, value);
        await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
        expect(engines.last.displaySettings, value);
        await session.close(discardProgress: true);
        session.dispose();
        session = makeSession();
        await session.open(film);
        expect(session.displaySettings, value);
      },
    );
    test('rapid edits merge against state after a delayed save', () async {
      await session.open(film);
      final gate = preferences.gate = Completer<void>();
      final started = preferences.started = Completer<void>();
      final first = session.updateDisplaySettings(
        (s) => s.copyWith(aspectOverride: VideoAspectOverride.square),
      );
      try {
        await started.future;
        final second = session.updateDisplaySettings(
          (s) => s.copyWith(flipMode: VideoFlipMode.vertical),
        );
        gate.complete();
        await Future.wait([first, second]);
        const value = VideoDisplaySettings(
          aspectOverride: VideoAspectOverride.square,
          flipMode: VideoFlipMode.vertical,
        );
        expect(session.displaySettings, value);
        expect(await preferences.displaySettings, value);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await first;
      }
    });
    test(
      'save failure restores native state and the next edit can succeed',
      () async {
        await session.open(film);
        preferences.fail = true;
        await session.updateDisplaySettings(
          (s) => s.copyWith(cropMode: VideoCropMode.fill),
        );
        expect(session.controlError, contains('未能应用或保存'));
        expect(session.displaySettings, const VideoDisplaySettings());
        expect(engines.single.displaySettings, const VideoDisplaySettings());
        preferences.fail = false;
        await session.updateDisplaySettings(
          (s) => s.copyWith(flipMode: VideoFlipMode.both),
        );
        expect(
          (await preferences.displaySettings).cropMode,
          VideoCropMode.none,
        );
        expect(
          (await preferences.displaySettings).flipMode,
          VideoFlipMode.both,
        );
        expect(session.controlError, isNull);
      },
    );
    test('rollback failure warns and reapplying the same setting retries persistence', () async {
      await session.open(film);
      preferences.fail = true;
      preferences.onFailure = () => engines.single.reject = true;
      await session.updateDisplaySettings(
        (s) => s.copyWith(cropMode: VideoCropMode.fill),
      );
      expect(session.controlError, contains('未能完全恢复'));
      expect(session.displaySettings.cropMode, VideoCropMode.fill);
      engines.single.reject = false;
      preferences.fail = false;
      await session.updateDisplaySettings((s) => s);
      expect((await preferences.displaySettings).cropMode, VideoCropMode.fill);
      expect(session.controlError, isNull);
    });
    test('initial display rejection is nonfatal and can be retried', () async {
      await preferences.rememberDisplaySettings(
        const VideoDisplaySettings(flipMode: VideoFlipMode.horizontal),
      );
      rejectOpen = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.clock.playing, isTrue);
      expect(session.controlError, contains('仍可播放'));
      engines.single.reject = false;
      await session.updateDisplaySettings(
        (_) => const VideoDisplaySettings(flipMode: VideoFlipMode.horizontal),
      );
      expect(session.controlError, isNull);
    });
    test('unknown preference modes fall back individually and multi-key writes are atomic', () async {
      await sources.database.customStatement(
        "INSERT INTO player_preferences(key,value) VALUES('global.videoCropMode','invalid')",
      );
      expect(await preferences.displaySettings, const VideoDisplaySettings());
      await sources.database.customStatement(
        "CREATE TRIGGER reject_display BEFORE INSERT ON player_preferences WHEN NEW.key = 'global.videoFlipMode' BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END",
      );
      await expectLater(
        preferences.rememberDisplaySettings(
          const VideoDisplaySettings(
            aspectOverride: VideoAspectOverride.square,
            flipMode: VideoFlipMode.both,
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(await preferences.displaySettings, const VideoDisplaySettings());
    });
  });
}
