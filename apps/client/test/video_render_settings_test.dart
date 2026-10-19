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
import 'package:reelnest/features/playback/domain/video_render_settings.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_render_settings_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _Native {
  final values = Map.of(
    MpvRenderSettingsCommands.properties(const VideoRenderSettings()),
  );
  final calls = <List<String>>[];
  bool Function(List<String>)? reject, ignore;
  Future<String> read(String name) async => values[name]!;
  Future<void> command(List<String> args) async {
    calls.add(args);
    if (ignore?.call(args) != true) values[args[1]] = args[2];
    if (reject?.call(args) == true) throw StateError('Fixture partial write');
  }

  late final commands = MpvRenderSettingsCommands(command: command, read: read);
}

class _Engine extends FakeVideoEngine implements VideoRenderEngine {
  @override
  VideoRenderSettings renderSettings = const VideoRenderSettings();
  bool reject = false, unavailable = false;
  @override
  Future<void> setRenderSettings(VideoRenderSettings value) async {
    if (unavailable) {
      throw const VideoRenderUnavailable();
    }
    if (reject) throw StateError('Fixture render rejection');
    renderSettings = value;
  }
}

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool rejectRead = false, rejectWrite = false;
  Completer<void>? gate, entered;
  void Function()? onRejected;
  @override
  Future<VideoRenderSettings> get renderSettings {
    if (rejectRead) throw StateError('Fixture read unavailable');
    return super.renderSettings;
  }

  @override
  Future<void> rememberRenderSettings(VideoRenderSettings value) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) {
      entered?.complete();
      await waiting.future;
    }
    if (rejectWrite) {
      onRejected?.call();
      throw StateError('Fixture save unavailable');
    }
    await super.rememberRenderSettings(value);
  }
}

void main() {
  const defaults = VideoRenderSettings();
  const changed = VideoRenderSettings(
    debandMode: VideoDebandMode.strong,
    toneMappingMode: VideoToneMappingMode.hable,
  );
  test('original labels, defaults and all policy values', () {
    expect(VideoDebandMode.values.map((m) => m.displayName), [
      '关闭',
      '轻微',
      '明显',
    ]);
    expect(VideoToneMappingMode.values.map((m) => m.displayName), [
      '自动',
      'BT.2390',
      'Hable',
      'Mobius',
      'Reinhard',
      '裁剪',
    ]);
    expect(MpvRenderSettingsCommands.properties(defaults), {
      'deband': 'no',
      'deband-threshold': '64',
      'deband-range': '16',
      'deband-grain': '48',
      'tone-mapping': 'auto',
    });
    expect(
      MpvRenderSettingsCommands.properties(
        const VideoRenderSettings(debandMode: VideoDebandMode.light),
      ),
      {
        'deband': 'yes',
        'deband-threshold': '32',
        'deband-range': '12',
        'deband-grain': '24',
        'tone-mapping': 'auto',
      },
    );
    expect(MpvRenderSettingsCommands.properties(changed), {
      'deband': 'yes',
      'deband-threshold': '48',
      'deband-range': '18',
      'deband-grain': '36',
      'tone-mapping': 'hable',
    });
    expect(VideoToneMappingMode.values.map((m) => m.mpvValue), [
      'auto',
      'bt.2390',
      'hable',
      'mobius',
      'reinhard',
      'clip',
    ]);
    expect(VideoRenderSettings.fromJson(changed.toJson()), changed);
    expect(
      VideoRenderSettings.fromJson({
        'debandMode': 'invalid',
        'toneMappingMode': 'bt2390',
      }),
      const VideoRenderSettings(toneMappingMode: VideoToneMappingMode.bt2390),
    );
    expect(
      VideoRenderSettings.fromJson({
        'debandMode': 'light',
        'toneMappingMode': [],
      }),
      const VideoRenderSettings(debandMode: VideoDebandMode.light),
    );
  });
  test('all 18 combinations roundtrip, numeric alias readback and off resets numbers', () async {
    final native = _Native();
    native.values['deband-threshold'] = '64.000000';
    await native.commands.apply(defaults);
    expect(native.calls, isEmpty);
    for (final deband in VideoDebandMode.values) {
      for (final tone in VideoToneMappingMode.values) {
        final value = VideoRenderSettings(
          debandMode: deband,
          toneMappingMode: tone,
        );
        await native.commands.apply(value);
        expect(await native.commands.current(), value);
      }
    }
    await native.commands.apply(defaults);
    expect(native.values, MpvRenderSettingsCommands.properties(defaults));
    expect(
      native.calls.every(
        (c) =>
            c.first == 'set' &&
            MpvRenderSettingsCommands.properties(defaults).containsKey(c[1]),
      ),
      isTrue,
    );
  });
  test(
    'partial native failure and silent rejection both restore previous values',
    () async {
      for (final silent in [true, false]) {
        final native = _Native();
        final before = Map.of(native.values);
        if (silent) {
          native.ignore = (c) => c[1] == 'deband-range';
        } else {
          var rejected = false;
          native.reject = (c) =>
              !rejected && c[1] == 'deband-range' && (rejected = true);
        }
        await expectLater(native.commands.apply(changed), throwsStateError);
        expect(native.values, before);
      }
    },
  );
  test(
    'rollback failure is distinct and the same-value retry repairs the profile',
    () async {
      final native = _Native();
      native.reject = (c) => c[1] == 'deband-range';
      await expectLater(
        native.commands.apply(changed),
        throwsA(isA<VideoRenderRollbackFailure>()),
      );
      native.reject = null;
      await native.commands.apply(changed);
      expect(await native.commands.current(), changed);
    },
  );

  group('session and preferences', () {
    late Directory sandbox;
    late SourceRepository sources;
    late _Preferences preferences;
    late PlaybackSession session;
    late MediaIdentity film;
    final engines = <_Engine>[];
    var rejectInitial = false, unavailable = false;
    PlaybackSession createSession() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final current = _Engine()
          ..reject = rejectInitial
          ..unavailable = unavailable;
        engines.add(current);
        return current;
      },
    );
    setUp(() async {
      engines.clear();
      rejectInitial = false;
      unavailable = false;
      sandbox = await Directory.systemTemp.createTemp('reelnest-render-');
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
      expect(p.basename(sandbox.path), startsWith('reelnest-render-'));
      await sandbox.delete(recursive: true);
    });
    test(
      'global restore on next item and new session preserves paused playback',
      () async {
        await session.open(film);
        engines.last.emit(position: const Duration(seconds: 9), playing: false);
        await session.updateRenderSettings(
          debandMode: changed.debandMode,
          toneMappingMode: changed.toneMappingMode,
        );
        expect(session.renderSettings, changed);
        expect(session.clock.position, const Duration(seconds: 9));
        expect(session.clock.playing, isFalse);
        await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
        expect(session.renderSettings, changed);
        await session.close(discardProgress: true);
        session.dispose();
        session = createSession();
        await session.open(film);
        expect(session.renderSettings, changed);
      },
    );
    test('queued field edits merge after delayed persistence', () async {
      await session.open(film);
      preferences.gate = Completer<void>();
      preferences.entered = Completer<void>();
      final gate = preferences.gate!;
      final first = session.updateRenderSettings(
        debandMode: changed.debandMode,
      );
      await preferences.entered!.future;
      final second = session.updateRenderSettings(
        toneMappingMode: changed.toneMappingMode,
      );
      gate.complete();
      await Future.wait([first, second]);
      expect(session.renderSettings, changed);
      expect(await preferences.renderSettings, changed);
    });
    test('save failure restores old profile, clears error on retry', () async {
      await session.open(film);
      await session.updateRenderSettings(debandMode: VideoDebandMode.light);
      final before = session.renderSettings;
      preferences.rejectWrite = true;
      await session.updateRenderSettings(
        toneMappingMode: VideoToneMappingMode.hable,
      );
      expect(session.renderSettings, before);
      expect(await preferences.renderSettings, before);
      expect(session.controlError, contains('未能应用或保存'));
      expect(session.clock.playing, isTrue);
      preferences.rejectWrite = false;
      await session.updateRenderSettings(
        toneMappingMode: VideoToneMappingMode.hable,
      );
      expect(session.controlError, isNull);
    });
    test(
      'failed rollback keeps readable state and allows persistence retry',
      () async {
        await session.open(film);
        preferences.rejectWrite = true;
        preferences.onRejected = () => engines.last.reject = true;
        await session.updateRenderSettings(debandMode: VideoDebandMode.light);
        expect(session.renderSettings.debandMode, VideoDebandMode.light);
        expect(session.controlError, contains('未能完全恢复'));
        preferences.rejectWrite = false;
        preferences.onRejected = null;
        engines.last.reject = false;
        await session.updateRenderSettings(debandMode: VideoDebandMode.light);
        expect(await preferences.renderSettings, session.renderSettings);
        expect(session.controlError, isNull);
      },
    );
    test('native unavailable warning never persists a false success', () async {
      await session.open(film);
      engines.last.unavailable = true;
      await session.updateRenderSettings(debandMode: VideoDebandMode.light);
      expect(session.renderSettings, defaults);
      expect(await preferences.renderSettings, defaults);
      expect(session.controlError, VideoRenderUnavailable.message);
      expect(session.clock.playing, isTrue);
    });
    test('software fallback preserves GPU intent even when clicking a default field', () async {
      await preferences.rememberRenderSettings(changed);
      unavailable = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.controlError, contains('偏好已保留'));
      await session.updateRenderSettings(debandMode: VideoDebandMode.off);
      expect(session.controlError, VideoRenderUnavailable.message);
      expect(await preferences.renderSettings, changed);
      unavailable = false;
      await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
      expect(session.renderSettings, changed);
      expect(session.controlError, isNull);
    });
    test('initial native and preferences failures are nonfatal, saved intent retained', () async {
      await preferences.rememberRenderSettings(changed);
      rejectInitial = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.controlError, contains('设置未能应用'));
      expect(await preferences.renderSettings, changed);
      rejectInitial = false;
      unavailable = true;
      await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
      expect(session.error, isNull);
      expect(session.controlError, contains('偏好已保留'));
      expect(await preferences.renderSettings, changed);
      unavailable = false;
      preferences.rejectRead = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.controlError, contains('未能读取去色带'));
    });
    test('malformed JSON fallback and complete profile stored atomically in one row', () async {
      await sources.database.customStatement(
        "INSERT INTO player_preferences(key,value) VALUES('global.videoRenderSettings','not-json')",
      );
      expect(await preferences.renderSettings, defaults);
      await preferences.rememberRenderSettings(changed);
      final row = await sources.database
          .customSelect(
            "SELECT value FROM player_preferences WHERE key='global.videoRenderSettings'",
          )
          .getSingle();
      expect(jsonDecode(row.read<String>('value')), changed.toJson());
    });
  });
}
