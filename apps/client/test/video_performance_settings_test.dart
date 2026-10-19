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
import 'package:reelnest/features/playback/domain/video_performance_settings.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_performance_settings_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _Native {
  final values = Map.of(
    MpvPerformanceCommands.properties(const VideoPerformanceSettings()),
  );
  final calls = <List<String>>[];
  bool Function(List<String>)? reject, ignore;
  Future<String> read(String name) async => values[name]!;
  Future<void> command(List<String> args) async {
    calls.add(args);
    if (ignore?.call(args) != true) values[args[1]] = args[2];
    if (reject?.call(args) == true) {
      throw StateError('Fixture rejection after mutation');
    }
  }

  late final commands = MpvPerformanceCommands(command: command, read: read);
}

class _Engine extends FakeVideoEngine implements VideoPerformanceEngine {
  @override
  VideoPerformanceSettings performanceSettings =
      const VideoPerformanceSettings();
  bool reject = false, configuredBeforeOpen = false;
  int applies = 0;
  @override
  Future<void> setPerformanceSettings(VideoPerformanceSettings value) async {
    if (reject) throw StateError('Fixture settings rejected');
    performanceSettings = value;
    applies++;
  }

  @override
  Future<void> open(String path, Duration start) async {
    configuredBeforeOpen = applies > 0;
    await super.open(path, start);
  }
}

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool rejectRead = false, rejectWrite = false;
  Completer<void>? gate, entered;
  void Function()? onRejected;
  @override
  Future<VideoPerformanceSettings> get performanceSettings {
    if (rejectRead) throw StateError('Fixture read failed');
    return super.performanceSettings;
  }

  @override
  Future<void> rememberPerformanceSettings(
    VideoPerformanceSettings value,
  ) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) {
      entered?.complete();
      await waiting.future;
    }
    if (rejectWrite) {
      onRejected?.call();
      throw StateError('Fixture save failed');
    }
    await super.rememberPerformanceSettings(value);
  }
}

void main() {
  const standard = VideoPerformanceSettings();
  const fallback = VideoPerformanceSettings(
    hardwareDecodingMode: VideoHardwareDecodingMode.off,
    memoryBufferingEnabled: false,
  );
  test(
    'original hardware modes, buffering defaults and corrupt JSON fields',
    () {
      expect(VideoHardwareDecodingMode.values.map((m) => m.displayName), [
        '兼容',
        '自动',
        '关闭',
      ]);
      expect(VideoHardwareDecodingMode.values.map((m) => m.mpvValue), [
        'auto-safe',
        'auto',
        'no',
      ]);
      expect(standard.hardwareDecodingMode, VideoHardwareDecodingMode.safe);
      expect(standard.memoryBufferingEnabled, isTrue);
      expect(VideoPerformanceSettings.fromJson(standard.toJson()), standard);
      expect(VideoPerformanceSettings.fromJson(fallback.toJson()), fallback);
      expect(
        VideoPerformanceSettings.fromJson({
          'hardwareDecodingMode': [],
          'memoryBufferingEnabled': 'false',
        }),
        standard,
      );
      expect(
        VideoPerformanceSettings.fromJson({
          'hardwareDecodingMode': 'unknown',
          'memoryBufferingEnabled': false,
        }).memoryBufferingEnabled,
        isFalse,
      );
    },
  );
  test(
    'exact original profiles, numeric byte readback and no unrelated commands',
    () async {
      final native = _Native();
      native.values.addAll({
        'demuxer-max-bytes': '268435456',
        'demuxer-max-back-bytes': '100663296',
        'cache-secs': '90.000000',
      });
      await native.commands.apply(standard);
      expect(native.calls, isEmpty);
      for (final enabled in [false, true]) {
        for (final mode in VideoHardwareDecodingMode.values) {
          final value = VideoPerformanceSettings(
            hardwareDecodingMode: mode,
            memoryBufferingEnabled: enabled,
          );
          await native.commands.apply(value);
          expect(await native.commands.current(), value);
        }
      }
      expect(MpvPerformanceCommands.properties(fallback), {
        'cache': 'auto',
        'cache-secs': '20',
        'demuxer-readahead-secs': '20',
        'demuxer-max-bytes': '96MiB',
        'demuxer-max-back-bytes': '24MiB',
        'cache-pause': 'no',
        'hwdec': 'no',
      });
      expect(
        native.calls.every(
          (c) =>
              c.first == 'set' &&
              MpvPerformanceCommands.properties(standard).containsKey(c[1]),
        ),
        isTrue,
      );
    },
  );
  test(
    'partial native writes including the rejected property are rolled back',
    () async {
      final native = _Native();
      final before = Map.of(native.values);
      var rejected = false;
      native.reject = (c) =>
          !rejected && c[1] == 'demuxer-max-bytes' && (rejected = true);
      await expectLater(native.commands.apply(fallback), throwsStateError);
      expect(native.values, before);
      expect(native.calls.last[1], 'cache');
    },
  );
  test('silent native clamping is rejected and restored', () async {
    final native = _Native();
    final before = Map.of(native.values);
    native.ignore = (c) => c[1] == 'demuxer-readahead-secs';
    await expectLater(native.commands.apply(fallback), throwsStateError);
    expect(native.values, before);
  });
  test('rollback failure is explicit and the same desired value can repair a mixed profile', () async {
    final native = _Native();
    native.reject = (c) => c[1] == 'cache-secs';
    await expectLater(
      native.commands.apply(fallback),
      throwsA(isA<VideoPerformanceRollbackFailure>()),
    );
    native.reject = null;
    await native.commands.apply(fallback);
    expect(await native.commands.current(), fallback);
  });
  test('failed initial snapshot performs no native mutations', () async {
    final native = _Native();
    final commands = MpvPerformanceCommands(
      command: native.command,
      read: (n) async {
        if (n == 'cache-secs') throw StateError('Unavailable property');
        return native.read(n);
      },
    );
    await expectLater(commands.apply(fallback), throwsStateError);
    expect(native.calls, isEmpty);
  });

  group('session and global preferences', () {
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
      sandbox = await Directory.systemTemp.createTemp('reelnest-performance-');
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
      expect(p.basename(sandbox.path), startsWith('reelnest-performance-'));
      await sandbox.delete(recursive: true);
    });
    test(
      'applies before open and persists for next film and a new session',
      () async {
        expect(await preferences.performanceSettings, standard);
        await session.open(film);
        expect(engines.last.configuredBeforeOpen, isTrue);
        engines.last.emit(position: const Duration(seconds: 9), playing: false);
        await session.updatePerformanceSettings(
          hardwareDecodingMode: fallback.hardwareDecodingMode,
          memoryBufferingEnabled: false,
        );
        expect(session.performanceSettings, fallback);
        expect(session.clock.position, const Duration(seconds: 9));
        expect(session.clock.playing, isFalse);
        await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
        expect(engines.last.configuredBeforeOpen, isTrue);
        expect(engines.last.performanceSettings, fallback);
        await session.close(discardProgress: true);
        session.dispose();
        session = createSession();
        await session.open(film);
        expect(session.performanceSettings, fallback);
      },
    );
    test(
      'rapid cross-field edits merge the latest state after delayed save',
      () async {
        await session.open(film);
        preferences.gate = Completer<void>();
        preferences.entered = Completer<void>();
        final gate = preferences.gate!;
        final first = session.updatePerformanceSettings(
          hardwareDecodingMode: VideoHardwareDecodingMode.off,
        );
        await preferences.entered!.future;
        final second = session.updatePerformanceSettings(
          memoryBufferingEnabled: false,
        );
        gate.complete();
        await Future.wait([first, second]);
        expect(session.performanceSettings, fallback);
        expect(await preferences.performanceSettings, fallback);
      },
    );
    test(
      'save failure rolls back without losing the earlier persisted field',
      () async {
        await session.open(film);
        await session.updatePerformanceSettings(
          hardwareDecodingMode: VideoHardwareDecodingMode.off,
        );
        final before = session.performanceSettings;
        preferences.rejectWrite = true;
        await session.updatePerformanceSettings(memoryBufferingEnabled: false);
        expect(session.performanceSettings, before);
        expect(await preferences.performanceSettings, before);
        expect(session.controlError, contains('播放性能设置未能应用或保存'));
        expect(session.clock.playing, isTrue);
        preferences.rejectWrite = false;
        await session.updatePerformanceSettings(memoryBufferingEnabled: false);
        expect(session.controlError, isNull);
        expect(session.performanceSettings, fallback);
      },
    );
    test(
      'native rejection does not persist, then retry clears the warning',
      () async {
        await session.open(film);
        engines.last.reject = true;
        await session.updatePerformanceSettings(memoryBufferingEnabled: false);
        expect(await preferences.performanceSettings, standard);
        expect(session.controlError, isNotNull);
        engines.last.reject = false;
        await session.updatePerformanceSettings(memoryBufferingEnabled: false);
        expect(session.controlError, isNull);
      },
    );
    test('failed save rollback reflects applied settings and permits same-value retry', () async {
      await session.open(film);
      preferences.rejectWrite = true;
      preferences.onRejected = () => engines.last.reject = true;
      await session.updatePerformanceSettings(memoryBufferingEnabled: false);
      expect(session.performanceSettings.memoryBufferingEnabled, isFalse);
      expect(session.controlError, contains('未能完全恢复'));
      preferences.rejectWrite = false;
      preferences.onRejected = null;
      engines.last.reject = false;
      await session.updatePerformanceSettings(memoryBufferingEnabled: false);
      expect(
        await preferences.performanceSettings,
        session.performanceSettings,
      );
      expect(session.controlError, isNull);
    });
    test(
      'initial read and apply failures are nonfatal and retain saved intent',
      () async {
        await preferences.rememberPerformanceSettings(fallback);
        rejectInitial = true;
        await session.open(film);
        expect(session.error, isNull);
        expect(session.clock.playing, isTrue);
        expect(session.controlError, contains('播放性能设置未能应用'));
        expect(await preferences.performanceSettings, fallback);
        rejectInitial = false;
        preferences.rejectRead = true;
        await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
        expect(session.error, isNull);
        expect(session.performanceSettings, standard);
        expect(session.controlError, contains('未能读取播放性能设置'));
      },
    );
    test(
      'malformed JSON falls back and the complete profile is one atomic row',
      () async {
        await sources.database.customStatement(
          "INSERT INTO player_preferences(key,value) VALUES('global.videoPerformanceSettings','not-json')",
        );
        expect(await preferences.performanceSettings, standard);
        await preferences.rememberPerformanceSettings(fallback);
        final row = await sources.database
            .customSelect(
              "SELECT value FROM player_preferences WHERE key='global.videoPerformanceSettings'",
            )
            .getSingle();
        expect(jsonDecode(row.read<String>('value')), fallback.toJson());
        expect(await preferences.performanceSettings, fallback);
      },
    );
  });
}
