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
import 'package:reelnest/features/playback/domain/video_equalizer_settings.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_equalizer_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_mpv_video_filters.dart';
import 'support/fake_video_engine.dart';

class _AudioFilters extends FakeMpvVideoFilters {
  bool failAfterWrite = false;
  @override
  Future<String> read(String name) async {
    expect(name, 'af');
    return jsonEncode(filters);
  }

  @override
  Future<void> command(List<String> args) async {
    expect(args.first, 'af');
    await super.command(args);
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('Partial native update');
    }
  }
}

class _Engine extends FakeVideoEngine implements VideoEqualizerEngine {
  @override
  VideoEqualizerSettings equalizerSettings = const VideoEqualizerSettings();
  bool reject = false;
  @override
  Future<void> setEqualizerSettings(VideoEqualizerSettings value) async {
    if (reject) throw StateError('Fixture apply failed');
    equalizerSettings = value;
  }
}

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool rejectRead = false, rejectWrite = false;
  Completer<void>? gate, entered;
  void Function()? onRejected;
  @override
  Future<VideoEqualizerSettings> get equalizerSettings {
    if (rejectRead) throw StateError('Fixture read failed');
    return super.equalizerSettings;
  }

  @override
  Future<void> rememberEqualizerSettings(VideoEqualizerSettings value) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) {
      entered?.complete();
      await waiting.future;
    }
    if (rejectWrite) {
      onRejected?.call();
      throw StateError('Fixture write failed');
    }
    return super.rememberEqualizerSettings(value);
  }
}

void main() {
  const rock = VideoEqualizerSettings(
    enabled: true,
    preset: VideoEqualizerPreset.rock,
  );
  const vocal = VideoEqualizerSettings(
    enabled: true,
    preset: VideoEqualizerPreset.vocal,
  );
  test('original defaults, names and all five-band gain vectors', () {
    expect(VideoEqualizerPreset.values.map((p) => p.displayName), [
      '纯平',
      '流行',
      '摇滚',
      '爵士',
      '古典',
      '低音增强',
      '人声',
      '高音增强',
    ]);
    expect(VideoEqualizerPreset.frequencies, [60, 230, 910, 3600, 14000]);
    expect(VideoEqualizerPreset.values.map((p) => p.gainsDB), [
      [0, 0, 0, 0, 0],
      [-1, 2, 4, 2, -1],
      [4, 2, -1, 2, 4],
      [3, 1, 1, 2, 3],
      [4, 2, -1, 2, 3],
      [6, 4, 1, 0, 0],
      [-2, 0, 4, 3, 0],
      [0, 0, 1, 4, 6],
    ]);
    expect(
      rock.filterGraph,
      "firequalizer=gain_entry='entry(60,4.0);entry(230,2.0);entry(910,-1.0);entry(3600,2.0);entry(14000,4.0)'",
    );
    expect(const VideoEqualizerSettings().filterGraph, isNull);
    expect(const VideoEqualizerSettings(enabled: true).filterGraph, isNull);
    for (final preset in VideoEqualizerPreset.values) {
      final value = VideoEqualizerSettings(enabled: true, preset: preset);
      expect(VideoEqualizerSettings.fromJson(value.toJson()), value);
    }
  });

  group('owned audio filter', () {
    late _AudioFilters native;
    late MpvEqualizerCommands commands;
    setUp(() {
      native = _AudioFilters();
      commands = MpvEqualizerCommands(
        command: native.command,
        read: native.read,
      );
    });
    test(
      'updates in place, bypasses flat/off and preserves foreign filters',
      () async {
        final before = {
          'label': 'before',
          'name': 'volume',
          'params': {'volume': '0.5'},
        };
        final after = {
          'label': 'after',
          'name': 'lavfi',
          'params': {'graph': "anull,volume=1:precision=double"},
        };
        native.filters.add(before);
        await commands.apply(rock);
        native.filters.add(after);
        await commands.apply(vocal);
        expect(native.filters.map((f) => f['label']), [
          'before',
          MpvEqualizerCommands.label,
          'after',
        ]);
        expect(native.filters.first, before);
        expect(native.filters.last, after);
        expect(await commands.actual(rock), vocal);
        final count = native.calls.length;
        await commands.apply(vocal);
        expect(native.calls, hasLength(count));
        await commands.apply(vocal.copyWith(enabled: false));
        expect(native.filters, [before, after]);
        await commands.apply(const VideoEqualizerSettings(enabled: true));
        expect(native.filters, [before, after]);
        await commands.apply(rock);
        await commands.apply(rock.copyWith(enabled: false));
        expect(native.filters, [before, after]);
      },
    );
    test(
      'a partially applied native failure restores the previous graph',
      () async {
        await commands.apply(rock);
        native.failAfterWrite = true;
        await expectLater(commands.apply(vocal), throwsStateError);
        expect(await commands.actual(rock), rock);
        await commands.apply(vocal);
        expect(await commands.actual(rock), vocal);
      },
    );
    test(
      'failed rollback reports actual graph and allows later recovery',
      () async {
        await commands.apply(rock);
        native.failAfterWrite = true;
        native.reject = (args) => args.last.contains('entry(60,4.0)');
        await expectLater(
          commands.apply(vocal),
          throwsA(isA<VideoEqualizerRollbackFailure>()),
        );
        expect(await commands.actual(rock), vocal);
        native.reject = null;
        await commands.apply(rock);
        expect(await commands.actual(rock), rock);
      },
    );
    test(
      'foreign filter loss cannot be reported as a successful rollback',
      () async {
        native.filters.add({'label': 'foreign', 'name': 'anull'});
        native.reject = (_) {
          native.filters.removeWhere((f) => f['label'] == 'foreign');
          return true;
        };
        await expectLater(
          commands.apply(rock),
          throwsA(isA<VideoEqualizerRollbackFailure>()),
        );
      },
    );
    test('malformed or duplicate owned entries fail before mutation', () async {
      for (final invalid in [
        {'label': MpvEqualizerCommands.label, 'name': 'volume'},
        {
          'label': MpvEqualizerCommands.label,
          'name': 'lavfi',
          'enabled': false,
          'params': {'graph': rock.filterGraph},
        },
      ]) {
        native.filters
          ..clear()
          ..add(invalid);
        await expectLater(commands.apply(rock), throwsFormatException);
      }
      native.filters.clear();
      await commands.apply(rock);
      native.filters.add(Map.of(native.filters.single));
      final count = native.calls.length;
      await expectLater(commands.apply(vocal), throwsFormatException);
      expect(native.calls, hasLength(count));
    });
  });

  group('equalizer session', () {
    late Directory sandbox;
    late SourceRepository sources;
    late _Preferences preferences;
    late PlaybackSession session;
    late MediaIdentity film;
    final engines = <_Engine>[];
    var initialReject = false, supported = true;
    PlaybackSession createSession() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        if (!supported) return FakeVideoEngine();
        final engine = _Engine()..reject = initialReject;
        engines.add(engine);
        return engine;
      },
    );
    setUp(() async {
      engines.clear();
      initialReject = false;
      supported = true;
      sandbox = await Directory.systemTemp.createTemp('reelnest-equalizer-');
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
      expect(p.basename(sandbox.path), startsWith('reelnest-equalizer-'));
      await sandbox.delete(recursive: true);
    });
    test('global settings restore across films and sessions without moving playback', () async {
      expect(
        await preferences.equalizerSettings,
        const VideoEqualizerSettings(),
      );
      await session.open(film);
      engines.last.emit(position: const Duration(seconds: 9), playing: false);
      await session.updateEqualizerSettings(
        enabled: true,
        preset: VideoEqualizerPreset.rock,
      );
      expect(session.equalizerSettings, rock);
      expect(session.clock.position, const Duration(seconds: 9));
      expect(session.clock.playing, isFalse);
      expect(await preferences.equalizerSettings, rock);
      await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
      expect(engines.last.equalizerSettings, rock);
      await session.close(discardProgress: true);
      session.dispose();
      session = createSession();
      await session.open(film);
      expect(engines.last.equalizerSettings, rock);
      await session.updateEqualizerSettings(enabled: false);
      expect(session.equalizerSettings, rock.copyWith(enabled: false));
      await session.updateEqualizerSettings(enabled: true);
      expect(session.equalizerSettings, rock);
    });
    test(
      'rapid enable/preset edits merge when serial execution starts',
      () async {
        await session.open(film);
        preferences.gate = Completer<void>();
        preferences.entered = Completer<void>();
        final gate = preferences.gate!;
        final first = session.updateEqualizerSettings(enabled: true);
        await preferences.entered!.future;
        final second = session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.vocal,
        );
        final third = session.updateEqualizerSettings(enabled: false);
        final fourth = session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.rock,
        );
        gate.complete();
        await Future.wait([first, second, third, fourth]);
        expect(session.equalizerSettings, rock.copyWith(enabled: false));
        expect(await preferences.equalizerSettings, session.equalizerSettings);
      },
    );
    test(
      'apply and save errors retain prior settings and can be retried',
      () async {
        await session.open(film);
        await session.updateEqualizerSettings(
          enabled: true,
          preset: VideoEqualizerPreset.rock,
        );
        engines.last.reject = true;
        await session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.vocal,
        );
        expect(session.equalizerSettings, rock);
        expect(session.controlError, isNotNull);
        engines.last.reject = false;
        preferences.rejectWrite = true;
        await session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.vocal,
        );
        expect(session.equalizerSettings, rock);
        expect(await preferences.equalizerSettings, rock);
        expect(session.error, isNull);
        expect(session.clock.playing, isTrue);
        preferences.rejectWrite = false;
        await session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.vocal,
        );
        expect(session.equalizerSettings, vocal);
        expect(session.controlError, isNull);
      },
    );
    test(
      'failed save rollback exposes actual state and permits persistence retry',
      () async {
        await session.open(film);
        preferences.rejectWrite = true;
        preferences.onRejected = () => engines.last.reject = true;
        await session.updateEqualizerSettings(
          enabled: true,
          preset: VideoEqualizerPreset.rock,
        );
        expect(session.equalizerSettings, rock);
        expect(session.controlError, contains('未能完全恢复'));
        preferences.rejectWrite = false;
        preferences.onRejected = null;
        engines.last.reject = false;
        await session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.rock,
        );
        expect(await preferences.equalizerSettings, rock);
        expect(session.controlError, isNull);
      },
    );
    test(
      'read and initial apply failures are nonfatal and preserve stored choice',
      () async {
        await preferences.rememberEqualizerSettings(rock);
        initialReject = true;
        await session.open(film);
        expect(session.error, isNull);
        expect(session.clock.playing, isTrue);
        expect(session.controlError, contains('均衡器设置未能应用'));
        expect(await preferences.equalizerSettings, rock);
        initialReject = false;
        preferences.rejectRead = true;
        await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
        expect(session.controlError, contains('未能读取均衡器设置'));
        expect(session.equalizerSettings, const VideoEqualizerSettings());
      },
    );
    test(
      'unsupported engine opens defaults, warns on active saved settings',
      () async {
        supported = false;
        await session.open(film);
        expect(session.error, isNull);
        expect(session.controlError, isNull);
        await session.updateEqualizerSettings(enabled: true);
        expect(session.controlError, isNotNull);
        expect(
          await preferences.equalizerSettings,
          const VideoEqualizerSettings(),
        );
        await preferences.rememberEqualizerSettings(rock);
        await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
        expect(session.error, isNull);
        expect(session.controlError, contains('暂不支持'));
        expect(await preferences.equalizerSettings, rock);
      },
    );
    test(
      'malformed values use defaults and actual SQLite failure preserves row',
      () async {
        for (final raw in [
          '{broken',
          '[]',
          'null',
          '{"enabled":"true","preset":12}',
        ]) {
          await sources.database.customStatement(
            'INSERT OR REPLACE INTO player_preferences VALUES(?,?)',
            ['global.videoEqualizerSettings', raw],
          );
          expect(
            await preferences.equalizerSettings,
            const VideoEqualizerSettings(),
          );
        }
        await preferences.rememberEqualizerSettings(rock);
        await session.open(film);
        await sources.database.customStatement(
          "CREATE TRIGGER reject_equalizer BEFORE UPDATE ON player_preferences WHEN NEW.key='global.videoEqualizerSettings' BEGIN SELECT RAISE(ABORT, 'fixture write failure'); END",
        );
        await session.updateEqualizerSettings(
          preset: VideoEqualizerPreset.vocal,
        );
        expect(await preferences.equalizerSettings, rock);
        expect(session.equalizerSettings, rock);
        expect(session.controlError, isNotNull);
      },
    );
  });
}
