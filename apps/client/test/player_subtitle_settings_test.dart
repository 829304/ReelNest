import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/video_subtitle_settings.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/subtitle_font_catalog.dart';
import 'package:reelnest/player/video_subtitle_settings_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _Preferences extends PlayerPreferencesRepository {
  _Preferences(super.database);
  bool failSave = false;
  Completer<void>? styleSaveGate;
  Completer<void>? styleSaveStarted;
  void Function()? onFailure;
  void _check() {
    if (failSave) {
      onFailure?.call();
      throw StateError('Fixture storage failure');
    }
  }

  @override
  Future<void> rememberSubtitleStyle(VideoSubtitleStyle style) async {
    final gate = styleSaveGate;
    styleSaveGate = null;
    if (gate != null) {
      styleSaveStarted?.complete();
      await gate.future;
    }
    _check();
    await super.rememberSubtitleStyle(style);
  }

  @override
  Future<void> rememberNumber(String key, double value) async {
    _check();
    await super.rememberNumber(key, value);
  }
}

class _SubtitleEngine extends FakeVideoEngine {
  bool rejectStyle = false;
  @override
  Future<void> setSubtitleStyle(VideoSubtitleStyle style) async {
    if (rejectStyle) throw StateError('Fixture subtitle style rejection');
    await super.setSubtitleStyle(style);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original defaults, quantization, bounds, colors and explicit font reset',
    () {
      expect(VideoSubtitleStyle.standard.isStandard, isTrue);
      final extreme = VideoSubtitleStyle(
        fontName: '',
        borderSize: double.nan,
        backgroundOpacity: double.infinity,
      ).normalized;
      expect(extreme.fontName, '');
      expect(extreme.borderSize, 3);
      expect(extreme.backgroundOpacity, 0);
      expect(
        const VideoSubtitleStyle(fontName: 'Arial')
            .copyWith(fontName: null)
            .isStandard,
        isTrue,
      );
      expect(
        const VideoSubtitleStyle(
          borderSize: 12,
          backgroundOpacity: 1,
        ).normalized.borderSize,
        6,
      );
      expect(
        const VideoSubtitleStyle(backgroundOpacity: 1)
            .normalized
            .backgroundOpacity,
        .8,
      );
      expect(
        MpvSubtitleSettingsCommands.styleProperties(
          const VideoSubtitleStyle(
            bold: true,
            colorPreset: VideoSubtitleColorPreset.yellow,
            backgroundOpacity: .45,
          ),
        ),
        {
          'sub-font': 'sans-serif',
          'sub-bold': true,
          'sub-color': '#F5D547',
          'sub-border-size': 3.0,
          'sub-back-color': '#73000000',
        },
      );
      expect(VideoSubtitleColorPreset.values.map((c) => c.mpvColor), [
        '#FFFFFF',
        '#F5D547',
        '#7FE3E8',
        '#8FE388',
        '#F5A14B',
      ]);
      final timing = const VideoTimingSettings(
        audioDelay: .16,
        subtitleDelay: -.16,
        subtitleScale: 1.13,
        subtitlePosition: 81.7,
      ).normalized;
      expect(
        timing,
        const VideoTimingSettings(
          audioDelay: .2,
          subtitleDelay: -.2,
          subtitleScale: 1.15,
          subtitlePosition: 82,
        ),
      );
      expect(VideoTimingSettings.syncDelay(1e308), 3);
      expect(VideoTimingSettings.syncDelay(-1e308), -3);
      expect(VideoTimingSettings.scale(1e308), 1.5);
      expect(VideoTimingSettings.position(-1e308), 70);
      expect(
        const VideoTimingSettings(
          audioDelay: double.nan,
          subtitleDelay: double.infinity,
          subtitleScale: double.nan,
          subtitlePosition: double.infinity,
        ).normalized,
        const VideoTimingSettings(),
      );
    },
  );

  test(
    'native readback rejects silent failure and restores earlier writes',
    () async {
      final properties = <String, String>{
        'sub-font': 'sans-serif',
        'sub-bold': 'no',
        'sub-color': '#FFFFFFFF',
        'sub-border-size': '3.000000',
        'sub-back-color': '#00000000',
      };
      final before = Map.of(properties);
      var reject = true;
      final commands = MpvSubtitleSettingsCommands(
        read: (name) async => properties[name]!,
        command: (args) async {
          if (args[1] == 'sub-color' && reject) {
            reject = false;
            return;
          }
          properties[args[1]] = args[2];
        },
      );
      await expectLater(
        commands.applyStyle(
          const VideoSubtitleStyle(
            fontName: 'Arial',
            bold: true,
            colorPreset: VideoSubtitleColorPreset.cyan,
          ),
        ),
        throwsStateError,
      );
      expect(properties, before);
      await commands.applyStyle(
        const VideoSubtitleStyle(
          fontName: 'Arial',
          bold: true,
          colorPreset: VideoSubtitleColorPreset.cyan,
        ),
      );
      expect(properties['sub-font'], 'Arial');
      expect(properties['sub-bold'], 'yes');
      expect(properties['sub-color'], '#7FE3E8');
    },
  );

  test('rollback failure is distinguished from a rejected setting', () async {
    final commands = MpvSubtitleSettingsCommands(
      read: (_) async => 'no',
      command: (_) async => throw StateError('Rejected'),
    );
    await expectLater(
      commands.apply({'sub-bold': true}),
      throwsA(isA<SubtitleSettingsRollbackFailure>()),
    );
  });

  group('installed preferred font catalog', () {
    const channel = MethodChannel('reelnest/subtitle_fonts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));
    test('filters actual families in platform preference order', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'families');
        return [
          'Georgia',
          'arial',
          'Arial',
          'Unrelated',
          'Microsoft YaHei',
          'PingFang SC',
          'DejaVu Sans',
        ];
      });
      expect(await SubtitleFontCatalog(platform: 'windows').families(), [
        'Microsoft YaHei',
        'Arial',
        'Georgia',
      ]);
      expect(await SubtitleFontCatalog(platform: 'macos').families(), [
        'PingFang SC',
        'Georgia',
        'Arial',
      ]);
      expect(await SubtitleFontCatalog(platform: 'linux').families(), [
        'DejaVu Sans',
        'Arial',
        'Georgia',
      ]);
    });
    test(
      'empty installed preferences is valid; failure is not fake success',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async => ['Other']);
        expect(await SubtitleFontCatalog().families(), isEmpty);
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'font_enumeration_failed'),
        );
        await expectLater(
          SubtitleFontCatalog().families(),
          throwsA(isA<PlatformException>()),
        );
      },
    );
  });

  group('session and persistence', () {
    late Directory sandbox;
    late SourceRepository sources;
    late _Preferences preferences;
    late PlaybackSession session;
    late MediaIdentity film;
    final engines = <_SubtitleEngine>[];
    var rejectStyleOnOpen = false;
    PlaybackSession makeSession({Future<List<String>> Function()? fonts}) =>
        PlaybackSession(
          sources: sources,
          records: PlaybackRepository(sources.database),
          preferences: preferences,
          checkpointInterval: const Duration(hours: 1),
          subtitleFonts: fonts,
          createEngine: () {
            final engine = _SubtitleEngine()..rejectStyle = rejectStyleOnOpen;
            engines.add(engine);
            return engine;
          },
        );
    setUp(() async {
      engines.clear();
      rejectStyleOnOpen = false;
      sandbox = await Directory.systemTemp.createTemp(
        'reelnest-subtitle-settings-',
      );
      await File(p.join(sandbox.path, 'Film.mkv')).writeAsString('fixture');
      await File(p.join(sandbox.path, 'Other.mkv')).writeAsString('fixture');
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
      film = (sourceId: source.id, localId: 'Film.mkv');
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
        startsWith('reelnest-subtitle-settings-'),
      );
      await sandbox.delete(recursive: true);
    });
    test(
      'settings are live, persisted, restored on next item and new session',
      () async {
        expect(await preferences.subtitleStyle, VideoSubtitleStyle.standard);
        expect(await preferences.timing, const VideoTimingSettings());
        await session.open(film);
        final engine = engines.single;
        engine.emit(position: const Duration(seconds: 12), playing: false);
        const style = VideoSubtitleStyle(
          fontName: 'Arial',
          bold: true,
          colorPreset: VideoSubtitleColorPreset.orange,
          borderSize: 4.5,
          backgroundOpacity: .25,
        );
        await session.setSubtitleStyle(style);
        await session.audioDelay(.24);
        await session.subtitleDelay(-.26);
        await session.subtitleScale(1.23);
        await session.subtitlePosition(84);
        expect(session.engine, same(engine));
        expect(engine.disposals, 0);
        expect(engine.clock.position, const Duration(seconds: 12));
        expect(engine.clock.playing, isFalse);
        expect(session.subtitleStyle, style);
        expect(await preferences.subtitleStyle, style);
        const timing = VideoTimingSettings(
          audioDelay: .2,
          subtitleDelay: -.3,
          subtitleScale: 1.25,
          subtitlePosition: 84,
        );
        expect(session.timing, timing);
        expect(await preferences.timing, timing);
        await session.open((sourceId: film.sourceId, localId: 'Other.mkv'));
        expect(engines.last.subtitleStyle, style);
        expect(engines.last.timing, timing);
        await session.close(discardProgress: true);
        session.dispose();
        session = makeSession();
        await session.open(film);
        expect(session.subtitleStyle, style);
        expect(session.timing, timing);
        await session.setSubtitleStyle(
          session.subtitleStyle.copyWith(fontName: null),
        );
        expect((await preferences.subtitleStyle).fontName, isNull);
      },
    );
    test(
      'failed storage restores native settings and allows another attempt',
      () async {
        await session.open(film);
        final engine = engines.single;
        engine.emit(position: const Duration(seconds: 9), playing: true);
        preferences.failSave = true;
        await session.setSubtitleStyle(const VideoSubtitleStyle(bold: true));
        expect(session.controlError, isNotNull);
        expect(engine.subtitleStyle, VideoSubtitleStyle.standard);
        expect(session.subtitleStyle, VideoSubtitleStyle.standard);
        await session.audioDelay(.5);
        expect(engine.timing.audioDelay, 0);
        await session.subtitleDelay(.5);
        expect(engine.timing.subtitleDelay, 0);
        await session.subtitleScale(1.5);
        expect(engine.timing.subtitleScale, 1);
        await session.subtitlePosition(80);
        expect(engine.timing.subtitlePosition, 100);
        expect(await preferences.timing, const VideoTimingSettings());
        expect(engine.disposals, 0);
        expect(engine.clock.position, const Duration(seconds: 9));
        expect(engine.clock.playing, isTrue);
        preferences.failSave = false;
        await session.audioDelay(.5);
        expect(session.controlError, isNull);
        expect(engine.timing.audioDelay, .5);
      },
    );
    test(
      'queued style edits merge after a delayed save and persist together',
      () async {
        await session.open(film);
        final gate = preferences.styleSaveGate = Completer<void>();
        final started = preferences.styleSaveStarted = Completer<void>();
        final first = session.updateSubtitleStyle(
          (style) => style.copyWith(bold: true),
        );
        try {
          await started.future;
          expect(session.subtitleStyle.bold, isFalse);
          expect(engines.single.subtitleStyle.bold, isTrue);
          final edits = [
            first,
            session.updateSubtitleStyle(
              (style) =>
                  style.copyWith(colorPreset: VideoSubtitleColorPreset.orange),
            ),
            session.updateSubtitleStyle(
              (style) => style.copyWith(borderSize: style.borderSize + .5),
            ),
            session.updateSubtitleStyle(
              (style) => style.copyWith(borderSize: style.borderSize + .5),
            ),
            session.updateSubtitleStyle(
              (style) => style.copyWith(fontName: 'Arial'),
            ),
            session.updateSubtitleStyle(
              (style) => style.copyWith(fontName: null),
            ),
          ];
          gate.complete();
          await Future.wait(edits);
          const expected = VideoSubtitleStyle(
            bold: true,
            colorPreset: VideoSubtitleColorPreset.orange,
            borderSize: 4,
          );
          expect(session.subtitleStyle, expected);
          expect(engines.single.subtitleStyle, expected);
          expect(await preferences.subtitleStyle, expected);
          expect(session.controlError, isNull);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await first;
        }
      },
    );
    test(
      'queued edit uses rolled-back state after the preceding save fails',
      () async {
        await session.open(film);
        preferences.failSave = true;
        preferences.onFailure = () => preferences.failSave = false;
        await Future.wait([
          session.updateSubtitleStyle((style) => style.copyWith(bold: true)),
          session.updateSubtitleStyle(
            (style) =>
                style.copyWith(colorPreset: VideoSubtitleColorPreset.cyan),
          ),
        ]);
        const expected = VideoSubtitleStyle(
          colorPreset: VideoSubtitleColorPreset.cyan,
        );
        expect(session.subtitleStyle, expected);
        expect(engines.single.subtitleStyle, expected);
        expect(await preferences.subtitleStyle, expected);
        expect(session.controlError, isNull);
      },
    );
    test(
      'rejected command does not save; rollback failure surfaces explicitly',
      () async {
        await session.open(film);
        final engine = engines.single;
        engine.failControl = true;
        await session.setSubtitleStyle(const VideoSubtitleStyle(bold: true));
        expect(await preferences.subtitleStyle, VideoSubtitleStyle.standard);
        expect(session.controlError, isNotNull);
        expect(engine.disposals, 0);
        engine.failControl = false;
        preferences.failSave = true;
        preferences.onFailure = () => engine.failControl = true;
        await session.audioDelay(.5);
        expect(session.controlError, contains('未能完全恢复'));
        expect(session.timing.audioDelay, .5);
        expect(await preferences.timing, const VideoTimingSettings());
        engine.failControl = false;
        preferences.failSave = false;
        await session.audioDelay(.5);
        expect((await preferences.timing).audioDelay, .5);
        expect(session.controlError, isNull);
      },
    );
    test('initial subtitle failure warns without preventing playback and can retry', () async {
      await preferences.rememberSubtitleStyle(
        const VideoSubtitleStyle(bold: true),
      );
      rejectStyleOnOpen = true;
      await session.open(film);
      expect(session.error, isNull);
      expect(session.controlError, contains('仍可播放'));
      expect(session.clock.playing, isTrue);
      expect(engines.single.disposals, 0);
      engines.single.rejectStyle = false;
      await session.setSubtitleStyle(await preferences.subtitleStyle);
      expect(session.subtitleStyle.bold, isTrue);
      expect(session.controlError, isNull);
    });
    test('font future is shared, failed enumeration can retry', () async {
      await session.close(discardProgress: true);
      session.dispose();
      var loads = 0;
      session = makeSession(
        fonts: () async {
          loads++;
          if (loads == 1) throw StateError('Font fixture failure');
          return ['Arial'];
        },
      );
      final failed = session.subtitleFontFamilies;
      expect(session.subtitleFontFamilies, same(failed));
      await expectLater(failed, throwsStateError);
      expect(await session.subtitleFontFamilies, ['Arial']);
      expect(await session.subtitleFontFamilies, ['Arial']);
      expect(loads, 2);
    });
  });
}
