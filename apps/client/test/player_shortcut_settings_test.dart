import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_keyboard_shortcuts.dart';
import 'package:reelnest/features/playback/presentation/player_behavior_settings.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _ShortcutSettingsSession extends PlaybackSession {
  _ShortcutSettingsSession(SourceRepository sources)
    : super(
        sources: sources,
        records: PlaybackRepository(sources.database),
        createEngine: FakeVideoEngine.new,
      );

  bool failSave = false;

  Future<void> _change(
    VideoKeyboardShortcuts Function(VideoKeyboardShortcuts) change,
  ) async {
    if (failSave) {
      controlError = '快捷键设置保存失败，原有绑定已保留，请重试。';
    } else {
      keyboardShortcuts = change(keyboardShortcuts);
      controlError = null;
    }
    notifyListeners();
  }

  @override
  Future<void> setKeyboardShortcuts(
    VideoShortcutAction action,
    List<VideoKeyChord> keys,
  ) => _change((current) => current.set(action, keys));

  @override
  Future<void> resetKeyboardShortcut(VideoShortcutAction action) =>
      _change((current) => current.reset(action));

  @override
  Future<void> resetAllKeyboardShortcuts() =>
      _change((current) => current.resetAll());
}

Future<void> _showSettings(WidgetTester tester, PlaybackSession session) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPlayerBehaviorSettings(
            context,
            session,
            const PlayerPalette(),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('player-settings-tab-shortcuts')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SourceRepository sources;
  late _ShortcutSettingsSession session;

  setUp(() {
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    session = _ShortcutSettingsSession(sources);
  });

  tearDown(() async {
    session.dispose();
    await sources.close();
  });

  testWidgets(
    'shortcut tab records, keeps conflict recording active and transfers key',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _showSettings(tester, session);

      expect(
        find.text('这些快捷键在视频播放窗口内有效。把一个按键设给新动作时，会自动从原来的动作上移除。'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player-shortcut-reset-all')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('player-shortcut-row-playPause')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-record-nextEpisode')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player-shortcut-recording-nextEpisode')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player-shortcut-conflict-nextEpisode')),
        findsOneWidget,
      );
      expect(find.textContaining('已用于「播放 / 暂停」'), findsOneWidget);

      // Conflict confirmation keeps the recorder active so another key can be
      // chosen without restarting recording.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pump();
      expect(
        session.keyboardShortcuts.resolved(VideoShortcutAction.nextEpisode),
        [VideoKeyChord(LogicalKeyboardKey.keyN.keyId)],
      );
      expect(
        find.byKey(const ValueKey('player-shortcut-conflict-nextEpisode')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-record-nextEpisode')),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('player-shortcut-conflict-replace-nextEpisode'),
        ),
      );
      await tester.pump();
      expect(
        session.keyboardShortcuts.resolved(VideoShortcutAction.nextEpisode),
        [VideoKeyChord(LogicalKeyboardKey.keyK.keyId)],
      );
      expect(
        session.keyboardShortcuts
            .resolved(VideoShortcutAction.playPause)
            .contains(VideoKeyChord(LogicalKeyboardKey.keyK.keyId)),
        isFalse,
      );

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-clear-nextEpisode')),
      );
      await tester.pump();
      expect(
        session.keyboardShortcuts.resolved(VideoShortcutAction.nextEpisode),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('player-shortcut-reset-all')));
      await tester.pump();
      expect(
        session.keyboardShortcuts
            .resolved(VideoShortcutAction.playPause)
            .map((key) => key.keyId),
        contains(LogicalKeyboardKey.keyK.keyId),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recording owns Escape and cancels on focus, tab or window loss',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _showSettings(tester, session);

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-record-playPause')),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player-settings-dialog')),
        findsOneWidget,
        reason: '录制快捷键时 Escape 不应关闭设置弹层。',
      );
      expect(
        find.byKey(const ValueKey('player-shortcut-conflict-playPause')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-conflict-cancel-playPause')),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-record-playPause')),
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('player-shortcut-recording-playPause')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-record-playPause')),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player-shortcut-recording-playPause')),
        findsNothing,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('player-shortcut-record-playPause')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('player-settings-tab-playback')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('player-settings-tab-shortcuts')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player-shortcut-recording-playPause')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save failure keeps mapping and stays visible below the header', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _showSettings(tester, session);
    final before = session.keyboardShortcuts.resolved(
      VideoShortcutAction.playPause,
    );
    session.failSave = true;

    await tester.tap(
      find.byKey(const ValueKey('player-shortcut-clear-playPause')),
    );
    await tester.pump();
    expect(
      session.keyboardShortcuts.resolved(VideoShortcutAction.playPause),
      before,
    );
    expect(
      find.byKey(const ValueKey('player-settings-control-error')),
      findsOneWidget,
    );
    expect(find.textContaining('原有绑定已保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
