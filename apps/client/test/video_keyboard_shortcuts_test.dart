import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/video_keyboard_shortcuts.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/presentation/player_shortcut_router.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_display_settings_engine.dart';
import 'package:reelnest/player/video_track_shortcut_engine.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _Engine extends FakeVideoEngine
    implements VideoDisplayEngine, VideoTrackShortcutEngine {
  @override
  VideoDisplaySettings displaySettings = const VideoDisplaySettings();
  @override
  Future<void> setDisplaySettings(VideoDisplaySettings value) async =>
      displaySettings = value;
  final commands = <String>[];
  @override
  Future<void> cycleAudioTrack() async => commands.add('audio');
  @override
  Future<void> cycleSubtitleTrack() async => commands.add('subtitle');
  @override
  Future<void> toggleSubtitleVisibility() async => commands.add('visibility');
}

void main() {
  VideoKeyChord chord(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool control = false,
    bool meta = false,
    bool alt = false,
  }) => VideoKeyChord(
    key.keyId,
    shift: shift,
    control: control,
    meta: meta,
    alt: alt,
  );
  group('original keyboard model', () {
    test('all original actions and groups include external play', () {
      expect(VideoShortcutAction.values, hasLength(60));
      expect(VideoShortcutAction.groups, [
        '播放',
        '跳转',
        '窗口与控制',
        '画面',
        '音画同步',
        '轨道',
      ]);
      expect(
        VideoShortcutAction.values.any((a) => a.name == 'openExternal'),
        isTrue,
      );
    });
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      test('default aliases and exact modifiers on $platform', () {
        final keys = VideoKeyboardShortcuts(platform: platform);
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.space)),
          VideoShortcutAction.playPause,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.keyK)),
          VideoShortcutAction.playPause,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.enter)),
          VideoShortcutAction.toggleFullscreen,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.keyQ)),
          VideoShortcutAction.closeWindow,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.keyJ)),
          VideoShortcutAction.seekBackwardTen,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.pageUp)),
          VideoShortcutAction.seekForwardLarge,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.arrowRight, shift: true)),
          VideoShortcutAction.seekForwardSmall,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.arrowLeft, alt: true)),
          VideoShortcutAction.seekBackwardLarge,
        );
        expect(
          keys.actionFor(
            chord(
              LogicalKeyboardKey.keyF,
              meta: platform == TargetPlatform.macOS,
              control: platform != TargetPlatform.macOS,
            ),
          ),
          VideoShortcutAction.toggleFullscreen,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.minus, control: true)),
          VideoShortcutAction.audioDelayDown,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.keyB, shift: true)),
          VideoShortcutAction.clearABLoop,
        );
        expect(
          keys.actionFor(chord(LogicalKeyboardKey.keyK, alt: true)),
          isNull,
        );
        for (var n = 0; n < 10; n++) {
          final action = keys.actionFor(
            VideoKeyChord(LogicalKeyboardKey.digit0.keyId + n),
          );
          expect(action?.seekPercent, n / 10);
        }
        final bindings = [
          for (final action in VideoShortcutAction.values)
            ...keys.resolved(action),
        ];
        expect(
          bindings.toSet().length,
          bindings.length,
          reason: 'Defaults must be conflict free',
        );
      });
    }
    test('replacement removes only conflicting alias; clear/reset differ and reset uses original first-match', () {
      final k = chord(LogicalKeyboardKey.keyK);
      var keys = VideoKeyboardShortcuts(platform: TargetPlatform.windows);
      expect(
        keys.conflict(k, excluding: VideoShortcutAction.mute),
        VideoShortcutAction.playPause,
      );
      keys = keys.set(VideoShortcutAction.mute, [k, k]);
      expect(keys.resolved(VideoShortcutAction.playPause), [
        chord(LogicalKeyboardKey.space),
      ]);
      expect(keys.resolved(VideoShortcutAction.mute), [k]);
      expect(keys.actionFor(k), VideoShortcutAction.mute);
      keys = keys.reset(VideoShortcutAction.playPause);
      expect(keys.actionFor(k), VideoShortcutAction.playPause);
      expect(
        keys.conflict(k, excluding: VideoShortcutAction.playPause),
        VideoShortcutAction.mute,
      );
      keys = keys.set(VideoShortcutAction.playPause, []);
      expect(keys.actionFor(chord(LogicalKeyboardKey.space)), isNull);
      expect(keys.actionFor(k), VideoShortcutAction.mute);
      expect(keys.resetAll().overrides, isEmpty);
    });
    test('serialized bindings immutable and malformed values never clear valid defaults', () {
      final input = <VideoKeyChord>[
        chord(LogicalKeyboardKey.f8, control: true),
      ];
      final keys = VideoKeyboardShortcuts(
        overrides: {VideoShortcutAction.playPause: input},
      );
      input.clear();
      expect(keys.resolved(VideoShortcutAction.playPause), hasLength(1));
      expect(() => keys.overrides.clear(), throwsUnsupportedError);
      final restored = VideoKeyboardShortcuts.fromJson(
        jsonDecode(jsonEncode(keys.toJson())),
      );
      expect(
        restored.resolved(VideoShortcutAction.playPause),
        keys.resolved(VideoShortcutAction.playPause),
      );
      for (final invalid in [
        null,
        [],
        {'playPause': false},
        {
          'playPause': [
            {'key': -1},
          ],
        },
        {
          'playPause': [
            {'key': 65, 'control': 'true'},
          ],
        },
      ]) {
        expect(
          VideoKeyboardShortcuts.fromJson(invalid)
              .actionFor(chord(LogicalKeyboardKey.space)),
          VideoShortcutAction.playPause,
        );
      }
      expect(
        VideoKeyboardShortcuts.fromJson({'playPause': []})
            .actionFor(chord(LogicalKeyboardKey.space)),
        isNull,
      );
      expect(chord(LogicalKeyboardKey.shiftLeft).valid, isFalse);
    });
    test(
      'display distinguishes mac Command/Control and portable Ctrl/Meta',
      () {
        final value = chord(
          LogicalKeyboardKey.keyF,
          meta: true,
          control: true,
          alt: true,
          shift: true,
        );
        expect(
          value.displayName(TargetPlatform.macOS),
          'Command+Option+Control+Shift+F',
        );
        expect(
          value.displayName(TargetPlatform.windows),
          'Meta+Alt+Ctrl+Shift+F',
        );
      },
    );
  });

  group('session and persistence', () {
    late Directory root;
    late SourceRepository sources;
    late PlayerPreferencesRepository preferences;
    late PlaybackSession session;
    late MediaIdentity first, second;
    final engines = <_Engine>[];
    setUp(() async {
      root = await Directory.systemTemp.createTemp('reelnest-shortcuts-test-');
      await File(p.join(root.path, 'Film.mkv')).writeAsString('video');
      await File(p.join(root.path, 'Other.mkv')).writeAsString('video');
      sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
        identityLookup: (_) async => 'fixture-volume',
      );
      final source = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Test',
        location: root.path,
        minimumFileSize: 0,
      );
      await sources.scan(source.id);
      first = (sourceId: source.id, localId: 'Film.mkv');
      second = (sourceId: source.id, localId: 'Other.mkv');
      preferences = PlayerPreferencesRepository(sources.database);
      engines.clear();
      session = PlaybackSession(
        sources: sources,
        records: PlaybackRepository(sources.database),
        preferences: preferences,
        createEngine: () {
          final e = _Engine();
          engines.add(e);
          return e;
        },
      );
    });
    tearDown(() async {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
      expect(p.isWithin(Directory.systemTemp.path, root.path), isTrue);
      expect(p.basename(root.path), startsWith('reelnest-shortcuts-test-'));
      await root.delete(recursive: true);
    });
    test('mapping saves serial edits and clear/reset persist across opening a film', () async {
      final k = chord(LogicalKeyboardKey.keyK),
          f8 = chord(LogicalKeyboardKey.f8);
      await Future.wait([
        session.setKeyboardShortcuts(VideoShortcutAction.mute, [k]),
        session.setKeyboardShortcuts(VideoShortcutAction.captureFrame, [f8]),
      ]);
      expect(session.keyboardShortcuts.actionFor(k), VideoShortcutAction.mute);
      await session.open(first);
      expect(session.keyboardShortcuts.actionFor(k), VideoShortcutAction.mute);
      expect(
        (await preferences.keyboardShortcuts).actionFor(f8),
        VideoShortcutAction.captureFrame,
      );
      await session.setKeyboardShortcuts(VideoShortcutAction.mute, []);
      await session.open(second);
      expect(
        session.keyboardShortcuts.resolved(VideoShortcutAction.mute),
        isEmpty,
      );
      await session.resetAllKeyboardShortcuts();
      expect((await preferences.keyboardShortcuts).overrides, isEmpty);
    });
    test(
      'failed write does not publish or steal old binding; retry works',
      () async {
        await session.open(first);
        await sources.database.customStatement(
          "CREATE TRIGGER reject_shortcut BEFORE INSERT ON player_preferences BEGIN SELECT RAISE(ABORT,'fixture'); END",
        );
        await session.setKeyboardShortcuts(VideoShortcutAction.mute, [
          chord(LogicalKeyboardKey.keyK),
        ]);
        expect(session.controlError, contains('快捷键设置保存失败'));
        expect(
          session.keyboardShortcuts.actionFor(chord(LogicalKeyboardKey.keyK)),
          VideoShortcutAction.playPause,
        );
        await sources.database.customStatement('DROP TRIGGER reject_shortcut');
        await session.setKeyboardShortcuts(VideoShortcutAction.mute, [
          chord(LogicalKeyboardKey.keyK),
        ]);
        expect(session.controlError, isNull);
        expect(
          session.keyboardShortcuts.actionFor(chord(LogicalKeyboardKey.keyK)),
          VideoShortcutAction.mute,
        );
      },
    );
    test('rapid deltas use latest committed session values and retain last value across switches', () async {
      await session.open(first);
      await session.rate(1);
      await Future.wait(
        List.generate(
          4,
          (_) => session.performKeyboardAction(VideoShortcutAction.speedUp),
        ),
      );
      expect(session.clock.rate, 2);
      await Future.wait(
        List.generate(
          3,
          (_) => session.performKeyboardAction(
            VideoShortcutAction.subtitleDelayUp,
          ),
        ),
      );
      expect(session.timing.subtitleDelay, closeTo(.3, .00001));
      await Future.wait(
        List.generate(
          2,
          (_) => session.performKeyboardAction(
            VideoShortcutAction.rotateVideoRight,
          ),
        ),
      );
      expect(session.displaySettings.rotationMode, VideoRotationMode.rotate180);
      await session.performKeyboardAction(VideoShortcutAction.rotateVideoLeft);
      expect(
        session.displaySettings.rotationMode,
        VideoRotationMode.clockwise90,
      );
      await session.performKeyboardAction(VideoShortcutAction.seekTo90Percent);
      expect(session.clock.position, const Duration(seconds: 90));
      for (final action in [
        VideoShortcutAction.subtitleCycle,
        VideoShortcutAction.subtitleToggle,
        VideoShortcutAction.audioCycle,
      ]) {
        await session.performKeyboardAction(action);
      }
      expect(engines.single.commands, ['subtitle', 'visibility', 'audio']);
      await session.open(second);
      expect(session.clock.rate, 1, reason: 'Rate remains per-media');
      expect(session.timing.subtitleDelay, closeTo(.3, .00001));
    });
    test('held forward plays temporary 3x without changing remembered rate or the next film', () async {
      await session.open(first);
      await session.rate(1.5);
      await engines.single.pause();
      await session.setKeyboardSeekForwardHold(true);
      expect(session.clock.rate, 3);
      expect(session.clock.playing, isTrue);
      expect(await preferences.rate(session.item!), 1.5);
      await session.setKeyboardSeekForwardHold(false);
      expect(session.clock.rate, 1.5);
      await session.setKeyboardSeekForwardHold(true);
      await session.open(second);
      await session.setKeyboardSeekForwardHold(false);
      expect(session.clock.rate, 1);
    });
    test('malformed JSON safely uses defaults without rewriting it', () async {
      await sources.database.customStatement(
        "INSERT INTO player_preferences VALUES('global.videoKeyboardShortcuts','{bad')",
      );
      await session.open(first);
      expect(session.error, isNull);
      expect(
        session.keyboardShortcuts.actionFor(chord(LogicalKeyboardKey.space)),
        VideoShortcutAction.playPause,
      );
      expect(
        (await sources.database
                .customSelect(
                  "SELECT value FROM player_preferences WHERE key='global.videoKeyboardShortcuts'",
                )
                .getSingle())
            .read<String>('value'),
        '{bad',
      );
    });
    testWidgets(
      'router respects text, modifiers, modal routes and restores a hold on focus loss',
      (tester) async {
        final actions = <VideoShortcutAction>[], holds = <bool>[];
        final textFocus = FocusNode();
        addTearDown(textFocus.dispose);
        final playerFocus = FocusNode();
        addTearDown(playerFocus.dispose);
        final buttonFocus = FocusNode();
        addTearDown(buttonFocus.dispose);
        var buttonPresses = 0;
        BuildContext? pageContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                pageContext = context;
                return PlayerShortcutRouter(
                  session: session,
                  onAction: actions.add,
                  onSeekForwardHold: holds.add,
                  child: Scaffold(
                    body: Column(
                      children: [
                        Focus(
                          focusNode: playerFocus,
                          autofocus: true,
                          child: const Text('video'),
                        ),
                        TextField(focusNode: textFocus),
                        TextButton(
                          focusNode: buttonFocus,
                          onPressed: () => buttonPresses++,
                          child: const Text('control'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        expect(actions, [VideoShortcutAction.playPause]);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(actions, hasLength(1));
        textFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        expect(actions, hasLength(1));
        buttonFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(actions.last, VideoShortcutAction.toggleFullscreen);
        expect(
          buttonPresses,
          0,
          reason: 'Original window shortcut precedes button activation',
        );
        playerFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        expect(holds, [true]);
        expect(actions.last, VideoShortcutAction.seekForward);
        textFocus.requestFocus();
        await tester.pump();
        expect(holds, [
          true,
          false,
        ], reason: 'Editing focus ends the hold before release');
        // The router still owns ancestor focus when a text field inside it gains
        // focus; releasing the held physical key must nevertheless restore speed.
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        expect(holds, [true, false]);
        playerFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        expect(holds.last, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        expect(holds.last, isFalse);
        final inactiveCount = actions.length;
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        expect(actions, hasLength(inactiveCount));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.runAsync(
          () => session.setKeyboardShortcuts(VideoShortcutAction.playPause, [
            chord(LogicalKeyboardKey.keyN),
          ]),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        expect(actions, hasLength(inactiveCount));
        await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
        expect(actions.last, VideoShortcutAction.playPause);
        expect(actions, hasLength(inactiveCount + 1));
        final dialog = showDialog<void>(
          context: pageContext!,
          builder: (_) => const AlertDialog(content: Text('modal')),
        );
        await tester.pumpAndSettle();
        final count = actions.length;
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        expect(actions, hasLength(count));
        Navigator.pop(tester.element(find.byType(AlertDialog)));
        await tester.pumpAndSettle();
        await dialog;
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'recorded shifted punctuation, modifiers and key-up are normalized',
      (tester) async {
        VideoKeyChord? captured;
        await tester.pumpWidget(
          MaterialApp(
            home: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) {
                  captured = VideoKeyChord.fromEvent(event);
                }
                return KeyEventResult.handled;
              },
              child: const SizedBox(),
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        expect(captured, isNull);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        // Flutter's legacy Android test key map cannot synthesize '!'; feed
        // the platform KeyEvent shape while Shift is genuinely held instead.
        captured = VideoKeyChord.fromEvent(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.digit1,
            logicalKey: LogicalKeyboardKey.exclamation,
            timeStamp: Duration.zero,
          ),
        );
        expect(captured, chord(LogicalKeyboardKey.digit1, shift: true));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
