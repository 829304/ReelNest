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
import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/mpv_owned_video_filters.dart';
import 'package:reelnest/player/software_video_colors.dart';
import 'package:reelnest/player/video_display_settings_engine.dart';
import 'package:reelnest/player/video_sharpen_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_mpv_video_filters.dart';
import 'support/fake_video_engine.dart';

class _Engine extends FakeVideoEngine implements VideoSharpenEngine {
  @override
  VideoSharpenMode sharpenMode = VideoSharpenMode.off;
  bool reject = false;
  @override
  Future<void> setSharpenMode(VideoSharpenMode mode) async {
    if (reject || failControl) throw StateError('Fixture sharpen rejection');
    sharpenMode = mode;
  }
}

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool rejectRead = false, rejectWrite = false;
  Completer<void>? gate, entered;
  void Function()? onRejected;
  @override
  Future<VideoSharpenMode> get sharpenMode {
    if (rejectRead) throw StateError('Fixture preferences unavailable');
    return super.sharpenMode;
  }

  @override
  Future<void> rememberSharpenMode(VideoSharpenMode mode) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) {
      entered?.complete();
      await waiting.future;
    }
    if (rejectWrite) {
      onRejected?.call();
      throw StateError('Fixture write rejected');
    }
    await super.rememberSharpenMode(mode);
  }
}

void main() {
  test('original sharpening labels, defaults and luma-only presets', () {
    expect(VideoSharpenMode.values.map((m) => m.displayName), [
      '关闭',
      '轻微',
      '适中',
      '明显',
    ]);
    expect(VideoSharpenMode.values.map((m) => m.lumaAmount), [
      null,
      '0.4',
      '0.8',
      '1.2',
    ]);
  });
  test(
    'flip/sharpen/CPU color order is independent of all six click orders',
    () async {
      for (final order in [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
      ]) {
        final native = FakeMpvVideoFilters();
        final base = {
          'label': 'quality',
          'name': 'format',
          'params': {'fmt': 'yuv420p', 'note': 'A:B, [中文] % ='},
        };
        native.filters.add(base);
        final filters = MpvOwnedVideoFilters(
          command: native.command,
          read: native.read,
        );
        final sharp = MpvSharpenCommands(filters: filters);
        final display = MpvDisplaySettingsCommands(
          command: native.command,
          read: native.read,
        );
        final colors = MpvSoftwareColorCommands(
          command: native.command,
          read: native.read,
        );
        final actions = [
          () => display.apply(
            const VideoDisplaySettings(flipMode: VideoFlipMode.both),
          ),
          () => sharp.apply(VideoSharpenMode.medium),
          () => colors.apply(
            const VideoColorAdjustments(brightness: 10, gamma: 15),
          ),
        ];
        for (final at in order) {
          await actions[at]();
        }
        expect(native.filters.first, base);
        expect(native.filters.map((f) => f['name']), [
          'format',
          'hflip',
          'vflip',
          'unsharp',
          'lavfi',
        ]);
        expect(await sharp.current(), VideoSharpenMode.medium);
        final graph = jsonEncode(native.filters.last);
        final count = native.calls.length;
        for (final action in actions) {
          await action();
        }
        expect(native.calls, hasLength(count));
        await sharp.apply(VideoSharpenMode.off);
        expect(native.filters.map((f) => f['name']), [
          'format',
          'hflip',
          'vflip',
          'lavfi',
        ]);
        expect(jsonEncode(native.filters.last), graph);
        await display.apply(
          const VideoDisplaySettings(flipMode: VideoFlipMode.vertical),
        );
        expect(native.filters.map((f) => f['name']), [
          'format',
          'vflip',
          'lavfi',
        ]);
        expect(jsonEncode(native.filters.last), graph);
        expect(
          native.calls.every((c) => c.first == 'vf' || c.first == 'set'),
          isTrue,
        );
      }
    },
  );
  test('failed insertion restores the entire owned tail without deleting base filters', () async {
    final native = FakeMpvVideoFilters();
    native.filters.add({'label': 'quality', 'name': 'format'});
    final filters = MpvOwnedVideoFilters(
      command: native.command,
      read: native.read,
    );
    await filters.update({
      'reelnest-color': const MpvVideoFilter('reelnest-color', 'lavfi', {
        'graph': 'null',
      }),
    });
    final before = jsonEncode(native.filters);
    var rejected = false;
    native.reject = (args) {
      if (!rejected && args.last.contains('reelnest-sharpen')) {
        rejected = true;
        return true;
      }
      return false;
    };
    await expectLater(
      MpvSharpenCommands(filters: filters).apply(VideoSharpenMode.light),
      throwsStateError,
    );
    expect(jsonEncode(native.filters), before);
  });
  test('filter rollback failure is distinguishable and a later retry repairs order', () async {
    final native = FakeMpvVideoFilters();
    final filters = MpvOwnedVideoFilters(
      command: native.command,
      read: native.read,
    );
    await filters.update({
      'reelnest-color': const MpvVideoFilter('reelnest-color', 'lavfi', {
        'graph': 'null',
      }),
    });
    native.reject = (args) => args[1] == 'add';
    final sharp = MpvSharpenCommands(filters: filters);
    await expectLater(
      sharp.apply(VideoSharpenMode.light),
      throwsA(isA<VideoSharpenRollbackFailure>()),
    );
    native.reject = null;
    await sharp.apply(VideoSharpenMode.light);
    expect(await sharp.current(), VideoSharpenMode.light);
  });
  test('mpv filter parameter quoting counts UTF-8 bytes, including graph punctuation', () {
    const filter = MpvVideoFilter('reelnest-color', 'lavfi', {
      'graph': "null,drawtext=text='中文:a%[]=b'",
    });
    expect(
      FakeMpvVideoFilters.parse(filter.argument)['params'],
      filter.parameters,
    );
  });
  test(
    'CPU color matrix follows RGB-to-YUV conversion and HD guessing rules',
    () async {
      final native = FakeMpvVideoFilters();
      native.properties.addAll({
        'video-params/colormatrix': 'rgb',
        'video-params/w': '160',
        'video-params/h': '90',
      });
      final filters = MpvOwnedVideoFilters(
        command: native.command,
        read: native.read,
      );
      final sharpen = MpvSharpenCommands(filters: filters);
      final colors = MpvSoftwareColorCommands(
        command: native.command,
        read: native.read,
      );
      const value = VideoColorAdjustments(saturation: -100, hue: 60);
      await colors.apply(value);
      final rgb = (native.filters.last['params'] as Map)['graph'];
      await sharpen.apply(VideoSharpenMode.medium);
      await colors.apply(value);
      expect(
        (native.filters.last['params'] as Map)['graph'],
        startsWith('scale=in_color_matrix=bt601,'),
      );
      native.properties['video-params/w'] = '1280';
      await colors.apply(value);
      expect(
        (native.filters.last['params'] as Map)['graph'],
        startsWith('scale=in_color_matrix=bt709,'),
      );
      await sharpen.apply(VideoSharpenMode.off);
      await colors.apply(value);
      expect((native.filters.last['params'] as Map)['graph'], rgb);
    },
  );

  group('sharpen session and preferences', () {
    late Directory sandbox;
    late SourceRepository sources;
    late _Preferences preferences;
    late PlaybackSession session;
    late MediaIdentity film;
    final engines = <_Engine>[];
    var rejectInitial = false;
    PlaybackSession createSession() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final engine = _Engine()..reject = rejectInitial;
        engines.add(engine);
        return engine;
      },
    );
    setUp(() async {
      engines.clear();
      rejectInitial = false;
      sandbox = await Directory.systemTemp.createTemp('reelnest-sharpen-');
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
        name: 'Fixture',
        location: sandbox.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      film = (sourceId: source.id, localId: 'First.mkv');
      preferences = _Preferences(sources.database);
      session = createSession();
    });
    tearDown(() async {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
      expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-sharpen-'));
      await sandbox.delete(recursive: true);
    });
    test('persists globally and restores on next film and a new session without moving playback', () async {
      expect(await preferences.sharpenMode, VideoSharpenMode.off);
      await session.open(film);
      engines.last.emit(position: const Duration(seconds: 9), playing: false);
      await session.setSharpenMode(VideoSharpenMode.medium);
      expect(session.sharpenMode, VideoSharpenMode.medium);
      expect(session.clock.position, const Duration(seconds: 9));
      expect(session.clock.playing, isFalse);
      expect(await preferences.sharpenMode, VideoSharpenMode.medium);
      await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
      expect(engines.last.sharpenMode, VideoSharpenMode.medium);
      await session.close(discardProgress: true);
      session.dispose();
      session = createSession();
      await session.open(film);
      expect(engines.last.sharpenMode, VideoSharpenMode.medium);
    });
    test(
      'queued mode changes keep the latest choice after a delayed save',
      () async {
        await session.open(film);
        preferences.gate = Completer<void>();
        preferences.entered = Completer<void>();
        final gate = preferences.gate!;
        final first = session.setSharpenMode(VideoSharpenMode.light);
        await preferences.entered!.future;
        final second = session.setSharpenMode(VideoSharpenMode.medium);
        final third = session.setSharpenMode(VideoSharpenMode.strong);
        gate.complete();
        await Future.wait([first, second, third]);
        expect(session.sharpenMode, VideoSharpenMode.strong);
        expect(await preferences.sharpenMode, VideoSharpenMode.strong);
      },
    );
    test(
      'save failure restores the previous sharpen mode and remains playable',
      () async {
        await session.open(film);
        await session.setSharpenMode(VideoSharpenMode.light);
        preferences.rejectWrite = true;
        await session.setSharpenMode(VideoSharpenMode.strong);
        expect(session.sharpenMode, VideoSharpenMode.light);
        expect(session.controlError, isNotNull);
        expect(await preferences.sharpenMode, VideoSharpenMode.light);
        expect(session.clock.playing, isTrue);
        preferences.rejectWrite = false;
        await session.setSharpenMode(VideoSharpenMode.medium);
        expect(session.controlError, isNull);
        expect(session.sharpenMode, VideoSharpenMode.medium);
      },
    );
    test('failed rollback keeps actual mode and permits same-value persistence retry', () async {
      await session.open(film);
      preferences.rejectWrite = true;
      preferences.onRejected = () => engines.last.reject = true;
      await session.setSharpenMode(VideoSharpenMode.strong);
      expect(session.sharpenMode, VideoSharpenMode.strong);
      expect(session.controlError, contains('未能完全恢复'));
      preferences.rejectWrite = false;
      preferences.onRejected = null;
      engines.last.reject = false;
      await session.setSharpenMode(VideoSharpenMode.strong);
      expect(await preferences.sharpenMode, VideoSharpenMode.strong);
      expect(session.controlError, isNull);
    });
    test('initial apply and preference read failures are non-fatal', () async {
      await preferences.rememberSharpenMode(VideoSharpenMode.light);
      rejectInitial = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.clock.playing, isTrue);
      expect(session.controlError, contains('锐化设置未能应用'));
      rejectInitial = false;
      preferences.rejectRead = true;
      await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
      expect(session.error, isNull);
      expect(session.controlError, contains('未能读取锐化设置'));
      expect(session.sharpenMode, VideoSharpenMode.off);
    });
    test('unknown stored modes fall back to off', () async {
      await sources.database.customStatement(
        "INSERT INTO player_preferences(key,value) VALUES('global.videoSharpenMode','unknown')",
      );
      expect(await preferences.sharpenMode, VideoSharpenMode.off);
    });
  });
}
