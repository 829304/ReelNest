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
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_color_adjustments_engine.dart';
import 'package:reelnest/player/software_video_colors.dart';
import 'package:reelnest/player/video_display_settings_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';
import 'support/fake_mpv_video_filters.dart';

class _ColorEngine extends FakeVideoEngine
    implements VideoColorEngine, VideoDisplayEngine {
  @override
  VideoColorAdjustments colorAdjustments = VideoColorAdjustments.neutral;
  @override
  VideoDisplaySettings displaySettings = const VideoDisplaySettings();
  bool rejectColors = false;
  @override
  Future<void> setColorAdjustments(VideoColorAdjustments value) async {
    if (rejectColors || failControl) {
      throw StateError('Fixture color rejection');
    }
    colorAdjustments = value.normalized;
  }

  @override
  Future<void> setDisplaySettings(VideoDisplaySettings value) async {
    displaySettings = value;
  }
}

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool fail = false;
  bool failRead = false;
  @override
  Future<VideoColorAdjustments> get colorAdjustments {
    if (failRead) throw StateError('Fixture preference read failure');
    return super.colorAdjustments;
  }

  Completer<void>? gate, started;
  void Function()? onFailure;
  @override
  Future<void> rememberColorAdjustments(VideoColorAdjustments value) async {
    final pending = gate;
    gate = null;
    if (pending != null) {
      started?.complete();
      await pending.future;
    }
    if (fail) {
      onFailure?.call();
      throw StateError('Fixture preferences failure');
    }
    await super.rememberColorAdjustments(value);
  }
}

class _Mpv {
  final values = <String, String>{
    for (final name in VideoColorAdjustments.neutral.toJson().keys)
      name: '0.000000',
  };
  final calls = <List<String>>[];
  String? ignoreProperty;
  bool rejectRollback = false;
  late final commands = MpvColorAdjustmentCommands(
    read: (name) async => values[name]!,
    command: (args) async {
      calls.add(args);
      if (rejectRollback && args[1] == 'brightness' && args[2] == '0.000000') {
        throw StateError('Fixture rollback rejected');
      }
      if (args[1] != ignoreProperty) values[args[1]] = args[2];
    },
  );
}

class _SoftwareMpv extends _Mpv {
  final filters = <Map<String, dynamic>>[
    {
      'name': 'scale',
      'label': 'quality',
      'params': {'w': '320'},
    },
    {'name': 'hflip', 'label': 'reelnest-hflip'},
  ];
  bool rejectNextFilter = false;
  late final software = MpvSoftwareColorCommands(
    read: (name) async => switch (name) {
      'vf' => jsonEncode(filters),
      'video-params/colormatrix' => 'bt.709',
      _ => values[name]!,
    },
    command: (args) async {
      if (args.first != 'vf') return commands.command(args);
      calls.add(args);
      if (rejectNextFilter) {
        rejectNextFilter = false;
        throw StateError('Fixture filter rejection');
      }
      const label = MpvSoftwareColorCommands.label;
      final previous = filters.indexWhere((f) => f['label'] == label);
      if (args[1] == 'remove') {
        filters.removeWhere((f) => f['label'] == label);
      } else {
        final filter = FakeMpvVideoFilters.parse(args[2]);
        if (previous < 0) {
          filters.add(filter);
        } else {
          filters[previous] = filter;
        }
      }
    },
  );
}

void main() {
  test(
    'CPU simple adjustments avoid zero samples, unit products and unit powers',
    () {
      final brightness = SoftwareVideoColors.graph(
        const VideoColorAdjustments(brightness: 30),
        'bt.709',
      );
      expect(brightness, contains("r='max((r(X,Y))+0.3,0)'"));
      expect(brightness, isNot(contains('pow(')));
      expect(brightness, isNot(contains('*')));
      final gamma = SoftwareVideoColors.graph(
        const VideoColorAdjustments(gamma: 30),
        'bt.709',
      );
      expect(gamma, contains('pow(max(r(X,Y),0),'));
      expect(gamma, isNot(contains('*')));
      final black = SoftwareVideoColors.graph(
        const VideoColorAdjustments(contrast: -100),
        'bt.709',
      );
      expect(black, isNot(contains('(X,Y)')));
      expect(black, isNot(contains('pow(')));
    },
  );
  test('original five-component rounding, limits and JSON defaults', () {
    expect(
      const VideoColorAdjustments(
        brightness: 12.4,
        contrast: -12.6,
        saturation: 33,
        gamma: -44,
        hue: 55,
      ).toJson().values,
      [12, -13, 33, -44, 55],
    );
    expect(
      const VideoColorAdjustments(
        brightness: 500,
        contrast: -500,
        saturation: double.nan,
        gamma: double.infinity,
        hue: -100.001,
      ).normalized.toJson().values,
      [100, -100, 0, 0, -100],
    );
    expect(VideoColorAdjustments.clamp(2.5), 3);
    expect(VideoColorAdjustments.clamp(-2.5), -3);
    expect(
      VideoColorAdjustments.fromJson({'brightness': 5.8}),
      const VideoColorAdjustments(brightness: 6),
    );
    expect(VideoColorAdjustments.neutral.isNeutral, isTrue);
  });
  test('native color properties preserve original order and touch no other options', () async {
    final mpv = _Mpv();
    await mpv.commands.apply(
      const VideoColorAdjustments(
        brightness: 5,
        contrast: -10,
        saturation: 15,
        gamma: -20,
        hue: 25,
      ),
    );
    expect(mpv.calls.map((c) => c[1]), [
      'brightness',
      'contrast',
      'saturation',
      'gamma',
      'hue',
    ]);
    expect(mpv.calls.every((c) => c[0] == 'set'), isTrue);
    await mpv.commands.apply(VideoColorAdjustments.neutral);
    expect(mpv.values.values.map(double.parse), everyElement(0));
  });
  test('neutral numeric readback does not send redundant commands', () async {
    final mpv = _Mpv();
    await mpv.commands.apply(VideoColorAdjustments.neutral);
    expect(mpv.calls, isEmpty);
  });
  test(
    'native partial failure restores earlier properties in reverse order',
    () async {
      final mpv = _Mpv()..ignoreProperty = 'hue';
      final before = Map.of(mpv.values);
      await expectLater(
        mpv.commands.apply(
          const VideoColorAdjustments(
            brightness: 5,
            contrast: 10,
            saturation: 15,
            gamma: 20,
            hue: 25,
          ),
        ),
        throwsStateError,
      );
      expect(mpv.values, before);
      expect(mpv.calls.skip(5).map((c) => c[1]), [
        'hue',
        'gamma',
        'saturation',
        'contrast',
        'brightness',
      ]);
    },
  );
  test('native rollback failure remains distinguishable', () async {
    final mpv = _Mpv()
      ..ignoreProperty = 'contrast'
      ..rejectRollback = true;
    await expectLater(
      mpv.commands.apply(
        const VideoColorAdjustments(brightness: 5, contrast: 5),
      ),
      throwsA(isA<VideoColorRollbackFailure>()),
    );
  });

  test(
    'CPU filter replaces only its label and neutral removes processing',
    () async {
      final mpv = _SoftwareMpv();
      final unrelated = List.of(mpv.filters);
      await mpv.software.apply(const VideoColorAdjustments(brightness: 5));
      expect(mpv.filters.take(2), unrelated);
      expect(mpv.filters, hasLength(3));
      final graph = (mpv.filters.last['params'] as Map)['graph'];
      expect(graph, startsWith('format=gbrpf32le,geq='));
      await mpv.software.apply(
        const VideoColorAdjustments(brightness: 5, hue: 10),
      );
      expect(mpv.filters, hasLength(3));
      expect((mpv.filters.last['params'] as Map)['graph'], isNot(graph));
      final before = mpv.calls.length;
      await mpv.software.apply(
        const VideoColorAdjustments(brightness: 5, hue: 10),
      );
      expect(mpv.calls.length, before);
      await mpv.software.apply(VideoColorAdjustments.neutral);
      expect(mpv.filters, unrelated);
      expect(await mpv.commands.current(), VideoColorAdjustments.neutral);
      expect(
        mpv.calls.every((c) => c.first == 'set' || c.first == 'vf'),
        isTrue,
      );
    },
  );

  test(
    'CPU filter failure rolls back properties and retains previous graph',
    () async {
      final mpv = _SoftwareMpv();
      const before = VideoColorAdjustments(brightness: 5, saturation: -10);
      await mpv.software.apply(before);
      final previous = jsonEncode(mpv.filters);
      mpv.rejectNextFilter = true;
      await expectLater(
        mpv.software.apply(before.copyWith(gamma: 30)),
        throwsStateError,
      );
      expect(await mpv.commands.current(), before);
      expect(jsonEncode(mpv.filters), previous);
    },
  );

  test('CPU RGB hue/saturation preserve the original identity semantics', () {
    final native = SoftwareVideoColors.graph(
      VideoColorAdjustments.neutral,
      'rgb',
    );
    expect(
      SoftwareVideoColors.graph(
        const VideoColorAdjustments(hue: 100, saturation: -100),
        'rgb',
      ),
      native,
    );
    expect(
      SoftwareVideoColors.graph(
        const VideoColorAdjustments(hue: 100),
        'bt.709',
      ),
      isNot(native),
    );
    expect(
      SoftwareVideoColors.graph(
        const VideoColorAdjustments(
          brightness: double.nan,
          gamma: double.infinity,
        ),
        'rgb',
      ),
      native,
    );
  });

  group('color session and preferences', () {
    late Directory sandbox;
    late SourceRepository sources;
    late _Preferences preferences;
    late PlaybackSession session;
    late MediaIdentity film;
    final engines = <_ColorEngine>[];
    var rejectInitial = false;
    PlaybackSession createSession() => PlaybackSession(
      sources: sources,
      records: PlaybackRepository(sources.database),
      preferences: preferences,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final engine = _ColorEngine()..rejectColors = rejectInitial;
        engines.add(engine);
        return engine;
      },
    );
    setUp(() async {
      engines.clear();
      rejectInitial = false;
      sandbox = await Directory.systemTemp.createTemp('reelnest-colors-');
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
      expect(p.basename(sandbox.path), startsWith('reelnest-colors-'));
      await sandbox.delete(recursive: true);
    });
    test('live changes preserve clocks/display and restore on next item and new session', () async {
      expect(await preferences.colorAdjustments, VideoColorAdjustments.neutral);
      await session.open(film);
      final engine = engines.single;
      engine.emit(position: const Duration(seconds: 9), playing: false);
      await session.updateDisplaySettings(
        (s) => s.copyWith(flipMode: VideoFlipMode.horizontal),
      );
      const value = VideoColorAdjustments(
        brightness: 5,
        contrast: -5,
        saturation: 10,
        gamma: 15,
        hue: -10,
      );
      await session.updateColorAdjustments((_) => value);
      expect(session.colorAdjustments, value);
      expect(await preferences.colorAdjustments, value);
      expect(engine.clock.position, const Duration(seconds: 9));
      expect(engine.clock.playing, isFalse);
      expect(engine.disposals, 0);
      expect(engine.displaySettings.flipMode, VideoFlipMode.horizontal);
      await session.open((sourceId: film.sourceId, localId: 'Second.mkv'));
      expect(engines.last.colorAdjustments, value);
      await session.close(discardProgress: true);
      session.dispose();
      session = createSession();
      await session.open(film);
      expect(session.colorAdjustments, value);
    });
    test('queued increments and edits use latest applied state', () async {
      await session.open(film);
      final gate = preferences.gate = Completer<void>();
      final started = preferences.started = Completer<void>();
      final first = session.updateColorAdjustments(
        (s) => s.copyWith(brightness: s.brightness + 5),
      );
      try {
        await started.future;
        final second = session.updateColorAdjustments(
          (s) => s.copyWith(brightness: s.brightness + 5),
        );
        final third = session.updateColorAdjustments(
          (s) => s.copyWith(saturation: 5),
        );
        gate.complete();
        await Future.wait([first, second, third]);
        expect(
          session.colorAdjustments,
          const VideoColorAdjustments(brightness: 10, saturation: 5),
        );
        await session.updateColorAdjustments((s) => s.copyWith(brightness: 0));
        expect(
          await preferences.colorAdjustments,
          const VideoColorAdjustments(saturation: 5),
        );
      } finally {
        if (!gate.isCompleted) gate.complete();
        await first;
      }
    });
    test('save failure rolls back, and the next queued edit does not preserve failed changes', () async {
      await session.open(film);
      preferences.fail = true;
      await session.updateColorAdjustments((s) => s.copyWith(brightness: 10));
      expect(session.controlError, contains('未能应用或保存'));
      expect(session.colorAdjustments.isNeutral, isTrue);
      expect((await preferences.colorAdjustments).isNeutral, isTrue);
      preferences.fail = false;
      await session.updateColorAdjustments((s) => s.copyWith(hue: 5));
      expect(session.controlError, isNull);
      expect(
        await preferences.colorAdjustments,
        const VideoColorAdjustments(hue: 5),
      );
    });
    test('rollback failure warns; reapplying unchanged actual state retries persistence', () async {
      await session.open(film);
      preferences.fail = true;
      preferences.onFailure = () => engines.single.rejectColors = true;
      await session.updateColorAdjustments((s) => s.copyWith(brightness: 10));
      expect(session.controlError, contains('未能完全恢复'));
      expect(session.colorAdjustments.brightness, 10);
      engines.single.rejectColors = false;
      preferences.fail = false;
      await session.updateColorAdjustments((s) => s);
      expect((await preferences.colorAdjustments).brightness, 10);
      expect(session.controlError, isNull);
    });
    test(
      'color preference read failure uses neutral without blocking playback',
      () async {
        preferences.failRead = true;
        await session.open(film);
        expect(session.error, isNull);
        expect(session.clock.playing, isTrue);
        expect(session.colorAdjustments, VideoColorAdjustments.neutral);
        expect(session.controlError, contains('未能读取画面色彩设置'));
      },
    );

    test('initial color rejection warns without preventing playback', () async {
      await preferences.rememberColorAdjustments(
        const VideoColorAdjustments(hue: 5),
      );
      rejectInitial = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.clock.playing, isTrue);
      expect(session.controlError, contains('色彩设置未能应用'));
      engines.single.rejectColors = false;
      await session.updateColorAdjustments(
        (_) => const VideoColorAdjustments(hue: 5),
      );
      expect(session.controlError, isNull);
    });
    test('bad preferences use defaults; failed atomic JSON writes preserve all components', () async {
      await sources.database.customStatement(
        "INSERT INTO player_preferences(key,value) VALUES('global.videoColorAdjustments','invalid JSON')",
      );
      expect((await preferences.colorAdjustments).isNeutral, isTrue);
      const saved = VideoColorAdjustments(brightness: 5, hue: 10);
      await preferences.rememberColorAdjustments(saved);
      await sources.database.customStatement(
        "CREATE TRIGGER reject_color BEFORE UPDATE ON player_preferences WHEN NEW.key = 'global.videoColorAdjustments' BEGIN SELECT RAISE(ABORT, 'fixture rejection'); END",
      );
      await expectLater(
        preferences.rememberColorAdjustments(
          const VideoColorAdjustments(contrast: 20),
        ),
        throwsA(isA<Exception>()),
      );
      expect(await preferences.colorAdjustments, saved);
    });
  });
}
