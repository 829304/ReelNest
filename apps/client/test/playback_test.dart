import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/playback/presentation/player_track_popovers.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/playback/presentation/player_window_coordinator.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/data/online_subtitle_service.dart';
import 'package:reelnest/features/playback/domain/online_subtitle.dart';
import 'package:reelnest/features/playback/data/video_screenshot_store.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/playback/domain/video_screenshot.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/player/video_screenshot_engine.dart';
import 'package:reelnest/player/video_engine.dart';

import 'support/fake_video_engine.dart';
import 'support/fake_online_subtitle_settings.dart';

class _EmptySubtitleService extends OnlineSubtitleService {
  @override
  Future<OnlineSubtitleSearch> search(
    OnlineSubtitleQuery query,
    OnlineSubtitleSettings settings,
    ScanCancellation cancellation,
  ) async => const OnlineSubtitleSearch([], []);
}

void main() {
  late Directory sandbox;
  late SourceRepository sources;
  late PlaybackRepository records;
  late PlaybackSession session;
  late MediaIdentity film;
  late MediaSource source;
  late String? mount;
  var resourcesClosed = false;
  final engines = <FakeVideoEngine>[];
  setUp(() async {
    resourcesClosed = false;
    engines.clear();
    mount = 'fixture-volume';
    sandbox = await Directory.systemTemp.createTemp('reelnest-playback-test-');
    await File(p.join(sandbox.path, 'Film.mkv'))
        .writeAsString('fake engine fixture');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => mount,
    );
    records = PlaybackRepository(sources.database);
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    film = (sourceId: source.id, localId: 'Film.mkv');
    session = PlaybackSession(
      sources: sources,
      records: records,
      onlineSubtitleSettings: FakeOnlineSubtitleSettingsRepository(
        PlayerPreferencesRepository(sources.database),
      ),
      onlineSubtitleService: _EmptySubtitleService(),
      createEngine: () {
        final engine = _ScreenshotFakeVideoEngine();
        engines.add(engine);
        return engine;
      },
      screenshotStore: VideoScreenshotStore(
        directory: () async => Directory(p.join(sandbox.path, 'screenshots')),
        now: () => DateTime(2026, 10, 22, 10, 11, 12),
      ),
    );
  });
  tearDown(() async {
    if (!resourcesClosed) {
      await session.close();
      session.dispose();
      await sources.close();
    }
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-playback-test-'));
    await sandbox.delete(recursive: true);
  });
  test('resume threshold and rewind follow the original defaults', () {
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(seconds: 10),
      ).resumePosition,
      const Duration(seconds: 10),
    );
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(milliseconds: 10001),
      ).resumePosition,
      const Duration(milliseconds: 5001),
    );
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(seconds: 35),
      ).resumePosition,
      const Duration(seconds: 30),
    );
  });
  test('watched is sticky at 90 percent and rescan keeps progress', () async {
    await records.save(
      film,
      position: const Duration(seconds: 89),
      duration: const Duration(seconds: 100),
    );
    expect((await records.read(film)).watched, isFalse);
    await records.save(
      film,
      position: const Duration(seconds: 90),
      duration: const Duration(seconds: 100),
    );
    await records.save(
      film,
      position: const Duration(seconds: 3),
      duration: const Duration(seconds: 100),
    );
    await sources.scan(source.id);
    final record = await records.read(film);
    expect(record.watched, isTrue);
    expect(record.position, const Duration(seconds: 3));
    expect(record.lastPlayedAt, isNotNull);
  });
  test('unknown clock does not erase a saved position', () async {
    await records.save(
      film,
      position: const Duration(seconds: 15),
      duration: const Duration(seconds: 100),
    );
    await records.save(film, position: Duration.zero, duration: Duration.zero);
    expect((await records.read(film)).position, const Duration(seconds: 15));
  });
  test(
    'sources are isolated and deletion cannot recreate stale playback rows',
    () async {
      final nested = Directory(p.join(sandbox.path, 'other'));
      await nested.create();
      await File(p.join(nested.path, 'Film.mkv')).writeAsString('other');
      final other = await sources.add(
        kind: MediaSourceKind.localFolder,
        name: 'Other',
        location: nested.path,
        minimumFileSize: 0,
      );
      await sources.scan(other.id);
      await records.save(
        film,
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 100),
      );
      final otherId = (sourceId: other.id, localId: 'Film.mkv');
      expect((await records.read(otherId)).lastPlayedAt, isNull);
      await sources.remove(source.id);
      await records.save(
        film,
        position: const Duration(seconds: 40),
        duration: const Duration(seconds: 100),
      );
      expect((await records.read(film)).lastPlayedAt, isNull);
      expect((await sources.browse(other.id)).total, 1);
    },
  );
  test(
    'session resumes, pauses, clamps commands, saves and disposes exactly once',
    () async {
      await records.save(
        film,
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      await session.open(film);
      expect(engines.single.openedAt, const Duration(seconds: 20));
      engines.single.emit(position: const Duration(seconds: 35));
      await session.toggle();
      expect((await records.read(film)).position, const Duration(seconds: 35));
      await session.seek(const Duration(seconds: -10));
      expect(session.clock.position, Duration.zero);
      await session.seek(const Duration(seconds: 1000));
      expect(session.clock.position, const Duration(seconds: 100));
      await session.volume(500);
      expect(session.clock.volume, 100);
      await session.close();
      await session.close();
      expect(engines.single.disposals, 1);
      expect((await records.read(film)).watched, isTrue);
    },
  );
  test(
    'missing or changed mount never allocates a decoder or resets progress',
    () async {
      await records.save(
        film,
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      mount = null;
      await session.open(film);
      expect(session.loading, isFalse);
      expect(session.error, contains('NAS'));
      expect(engines, isEmpty);
      mount = 'fixture-volume';
      await File(p.join(sandbox.path, 'Film.mkv')).delete();
      await session.open(film);
      expect(engines, isEmpty);
      expect((await records.read(film)).position, const Duration(seconds: 25));
    },
  );
  test(
    'decoder failure ends loading and preserves the original resume point',
    () async {
      await records.save(
        film,
        position: const Duration(seconds: 25),
        duration: const Duration(seconds: 100),
      );
      final failing = PlaybackSession(
        sources: sources,
        records: records,
        createEngine: () => FakeVideoEngine()..failOpen = true,
      );
      await failing.open(film);
      expect(failing.loading, isFalse);
      expect(failing.error, isNotNull);
      expect(failing.engine, isNull);
      expect((await records.read(film)).position, const Duration(seconds: 25));
      await failing.close();
      failing.dispose();
    },
  );
  test(
    'switching files commits the old clock before creating the next decoder',
    () async {
      await File(p.join(sandbox.path, 'Second.mkv')).writeAsString('second');
      await sources.scan(source.id);
      final second = (sourceId: source.id, localId: 'Second.mkv');
      await session.open(film);
      engines.single.emit(position: const Duration(seconds: 37));
      await session.open(second);
      expect((await records.read(film)).position, const Duration(seconds: 37));
      expect(engines.first.disposals, 1);
      expect(engines.last.openedAt, Duration.zero);
      expect((await records.read(second)).lastPlayedAt, isNull);
    },
  );
  test(
    'completion saves duration even when the decoder resets its clock',
    () async {
      await session.open(film);
      engines.single.emit(position: Duration.zero, completed: true);
      await session.save();
      expect((await records.read(film)).position, const Duration(seconds: 100));
      expect((await records.read(film)).watched, isTrue);
    },
  );
  test('write failure is visible and may be retried without losing the current clock', () async {
    await session.open(film);
    engines.single.emit(position: const Duration(seconds: 22));
    await sources.database.customStatement(
      "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await session.close();
    expect(session.saveError, isNotNull);
    await sources.database.customStatement('DROP TRIGGER reject_progress');
    await session.save();
    expect(session.saveError, isNull);
    expect((await records.read(film)).position, const Duration(seconds: 22));
  });
  test(
    'failed close keeps the decoder usable until a successful retry',
    () async {
      await session.open(film);
      final decoder = engines.single;
      decoder.emit(position: const Duration(seconds: 22));
      await sources.database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      try {
        await session.close();
        expect(session.saveError, isNotNull);
        expect(session.engine, same(decoder));
        expect(decoder.disposals, 0);
        await session.toggle();
        expect(session.clock.playing, isTrue);
        await session.seek(const Duration(seconds: 31));
        await session.close();
        expect(session.engine, same(decoder));
        expect(decoder.disposals, 0);
      } finally {
        await sources.database.customStatement('DROP TRIGGER reject_progress');
      }
      await session.close();
      expect(session.engine, isNull);
      expect(decoder.disposals, 1);
      expect((await records.read(film)).position, const Duration(seconds: 31));
    },
  );

  test(
    'explicit discard closes exactly once after a failed checkpoint',
    () async {
      await session.open(film);
      final decoder = engines.single;
      decoder.emit(position: const Duration(seconds: 22));
      await sources.database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      try {
        await session.close();
        expect(decoder.disposals, 0);
        await session.close(discardProgress: true);
        await session.close();
        expect(decoder.disposals, 1);
        expect(session.engine, isNull);
        expect((await records.read(film)).lastPlayedAt, isNull);
      } finally {
        await sources.database.customStatement('DROP TRIGGER reject_progress');
      }
    },
  );

  test(
    'failed checkpoint prevents switching and preserves the retryable clock',
    () async {
      await File(p.join(sandbox.path, 'Second.mkv')).writeAsString('second');
      await sources.scan(source.id);
      await session.open(film);
      engines.single.emit(position: const Duration(seconds: 37));
      await sources.database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      final second = (sourceId: source.id, localId: 'Second.mkv');
      await session.open(second);
      expect(session.saveError, isNotNull);
      expect(session.item!.identity, film);
      expect(engines.single.disposals, 0);
      await sources.database.customStatement('DROP TRIGGER reject_progress');
      await session.open(second);
      expect(session.saveError, isNull);
      expect((await records.read(film)).position, const Duration(seconds: 37));
      expect(engines.first.disposals, 1);
    },
  );
  test(
    'queued open cannot allocate a decoder after closing is requested',
    () async {
      final opening = session.open(film);
      final closing = session.close();
      await Future.wait([opening, closing]);
      expect(engines, isEmpty);
    },
  );
  test(
    'native command failure is reported without an uncaught future',
    () async {
      await session.open(film);
      await session.toggle();
      engines.single.failCommand = true;
      await session.toggle();
      expect(session.error, contains('操作失败'));
    },
  );

  testWidgets('unknown duration keeps transport enabled but seek disabled', (
    tester,
  ) async {
    Future<void> waitUntil(bool Function() done) async {
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (done()) return;
      }
      fail('Unknown-duration player UI did not settle');
    }

    Future<void> finish(Future<void> future) async {
      var done = false;
      future.then((_) => done = true);
      await waitUntil(() => done);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          identity: film,
          session: session,
          closeWindow: () async {},
          setFullscreen: (_) async {},
        ),
      ),
    );
    await waitUntil(() => !session.loading && session.engine != null);
    final engine = engines.single;
    engine.value = VideoClock(
      position: const Duration(seconds: 8),
      playing: false,
      volume: engine.value.volume,
      rate: engine.value.rate,
    );
    engine.events.add(engine.value);
    await tester.pump();

    final playButton = find.descendant(
      of: find.byTooltip('播放/暂停'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(playButton).onPressed, isNotNull);
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('video-timeline')))
          .onChanged,
      isNull,
    );
    await tester.tap(playButton);
    await waitUntil(() => session.clock.playing);
    expect(session.clock.playing, isTrue);
    await tester.pumpWidget(const SizedBox());
    await finish(session.close(discardProgress: true));
    await tester.pump();
    await tester.runAsync(() async {
      session.dispose();
      await sources.close();
    });
    resourcesClosed = true;
  });

  testWidgets(
    'player controls and keyboard operate the session and close saves progress',
    (tester) async {
      tester.view.physicalSize = const Size(700, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var closed = false;
      var fullscreen = false;
      final windowGateway = _FakePlayerWindowGateway();
      final windowCoordinator = PlayerWindowCoordinator(windowGateway);
      addTearDown(windowCoordinator.dispose);
      Future<void> waitUntil(bool Function() done) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (done()) return;
        }
        fail('Player UI did not settle');
      }

      Future<void> finish(Future<void> future) async {
        var done = false;
        future.then((_) => done = true);
        await waitUntil(() => done);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: film,
            session: session,
            closeWindow: () async {
              closed = true;
            },
            setFullscreen: (value) async {
              fullscreen = value;
            },
            windowCoordinator: windowCoordinator,
          ),
        ),
      );
      await waitUntil(
        () => !session.loading && session.clock.duration > Duration.zero,
      );
      // Mirror the first native clock after loading so the throttled timeline
      // projection has the same non-zero duration as the session clock.
      engines.single.emit();
      await tester.pump();
      expect(session.error, isNull);
      expect(session.loading, isFalse);
      expect(engines, hasLength(1));
      expect(
        tester.getSize(find.byKey(const ValueKey('player-leading-actions'))),
        const Size(180, 32),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player-trailing-actions'))),
        const Size(143, 32),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player-control-dock'))),
        const Size(664, 72),
      );
      tester.view.physicalSize = const Size(360, 640);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        tester.getSize(find.byKey(const ValueKey('player-control-dock'))),
        const Size(324, 72),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player-leading-actions'))),
        const Size(69, 32),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('player-trailing-actions'))),
        const Size(106, 32),
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(700, 600);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.getSize(find.byTooltip('播放/暂停')), const Size(34, 34));
      final playerTooltipTheme = tester
          .widget<TooltipTheme>(
            find.byKey(const ValueKey('player-tooltip-theme')),
          )
          .data;
      final playerTooltipDecoration =
          playerTooltipTheme.decoration! as BoxDecoration;
      expect(playerTooltipTheme.preferBelow, isFalse);
      expect(playerTooltipTheme.textStyle?.color, const Color(0xF2FFFFFF));
      expect(playerTooltipDecoration.color, const Color(0xF21A1D22));
      for (final tooltip in [
        '字幕',
        '音轨',
        '章节与播放标记',
        '音量',
        '播放器设置',
        '迷你悬浮窗',
        '全屏',
        '锁定控制栏',
      ]) {
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
      expect(
        tester.getCenter(find.byTooltip('播放/暂停')).dx,
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('player-control-dock')))
              .dx,
          .01,
        ),
      );
      final subtitleControl = find.byTooltip('字幕');
      expect(tester.getSize(subtitleControl), const Size(32, 32));
      final subtitleSurface = find.descendant(
        of: subtitleControl,
        matching: find.byType(AnimatedContainer),
      );
      expect(subtitleSurface, findsOneWidget);
      BoxDecoration subtitleDecoration() =>
          tester.widget<AnimatedContainer>(subtitleSurface).decoration!
              as BoxDecoration;
      expect(subtitleDecoration().color, Colors.transparent);
      final dockPointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await dockPointer.addPointer();
      await dockPointer.moveTo(tester.getCenter(subtitleControl));
      await tester.pump();
      expect(subtitleDecoration().color, isNot(Colors.transparent));
      await dockPointer.moveTo(Offset.zero);
      await dockPointer.removePointer();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.tap(subtitleControl);
      await tester.pumpAndSettle();
      final trackPopover = tester.widget<PlayerTrackPopover>(
        find.byType(PlayerTrackPopover),
      );
      expect(trackPopover.palette.lightContent, isTrue);
      expect(
        Theme.of(tester.element(find.byType(PlayerTrackPopover)))
            .popupMenuTheme
            .color,
        const Color(0xFF15181D),
      );
      Navigator.of(tester.element(find.byType(PlayerTrackPopover))).pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('player-window-chrome')),
        findsOneWidget,
      );
      final windowChrome = find.byKey(const ValueKey('player-window-chrome'));
      expect(tester.getTopLeft(windowChrome).dy, 0);
      expect(tester.getSize(windowChrome).height, 54);
      expect(find.byTooltip('锁定控制栏'), findsOneWidget);
      final lockControl = find.byKey(const ValueKey('player-controls-lock'));
      expect(tester.getSize(lockControl), const Size.square(36));
      expect(
        find.descendant(
          of: lockControl,
          matching: find.byIcon(Icons.lock_open_rounded),
        ),
        findsOneWidget,
      );
      final miniModeDock = find.byKey(const ValueKey('player-mini-mode-dock'));
      expect(miniModeDock, findsOneWidget);
      expect(tester.getSize(miniModeDock), const Size.square(32));
      await tester.tap(miniModeDock);
      await waitUntil(() => windowCoordinator.miniMode);
      expect(
        find.byKey(const ValueKey('player-mini-mode-controls')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('player-window-chrome')), findsNothing);
      expect(find.byTooltip('还原窗口'), findsOneWidget);
      expect(windowGateway.alwaysOnTop, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await waitUntil(() => !windowCoordinator.miniMode);
      expect(closed, isFalse);
      expect(
        find.byKey(const ValueKey('player-window-chrome')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(400, 260), buttons: 2);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('toggle-mini-mode')), findsNothing);
      final precisionMenu = tester.widget<PlayerPanelSurface>(
        find.byKey(const ValueKey('player-precision-menu')),
      );
      expect(precisionMenu.palette.lightContent, isTrue);
      expect(
        Theme.of(
          tester.element(find.byKey(const ValueKey('player-precision-menu'))),
        ).popupMenuTheme.color,
        const Color(0xFF15181D),
      );
      expect(find.text('保存当前画面'), findsOneWidget);
      expect(find.text('图片'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('capture-current-frame')));
      await waitUntil(
        () => (engines.single as _ScreenshotFakeVideoEngine)
            .capturedModes
            .isNotEmpty,
      );
      expect(find.byKey(const ValueKey('player-precision-menu')), findsNothing);
      expect((engines.single as _ScreenshotFakeVideoEngine).capturedModes, [
        VideoScreenshotMode.subtitles,
      ]);
      await waitUntil(
        () => find
            .text('截图已保存：Film 2026-10-22 10.11.12.png')
            .evaluate()
            .isNotEmpty,
      );
      (engines.single as _ScreenshotFakeVideoEngine).failCapture = true;
      await tester.tapAt(const Offset(400, 260), buttons: 2);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('capture-current-frame')));
      await waitUntil(() => find.text('截图失败：测试截图失败').evaluate().isNotEmpty);
      expect(find.byKey(const ValueKey('player-precision-menu')), findsNothing);
      final screenshotEngine = engines.single as _ScreenshotFakeVideoEngine;
      screenshotEngine.failCapture = false;
      screenshotEngine.failCaptureUnexpectedly = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await waitUntil(() => screenshotEngine.capturedModes.length == 3);
      expect(
        screenshotEngine.capturedModes.last,
        VideoScreenshotMode.subtitles,
      );
      await waitUntil(
        () => find.text('截图失败：未能取得当前画面，请稍后重试。').evaluate().isNotEmpty,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await waitUntil(() => windowCoordinator.miniMode);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await waitUntil(() => !windowCoordinator.miniMode);
      Text trailingTime() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('player-timeline-trailing-time')),
          matching: find.byType(Text),
        ),
      );
      expect(trailingTime().data, '1:40');
      await tester.tap(
        find.byKey(const ValueKey('player-timeline-trailing-time')),
      );
      await waitUntil(() => session.options.showRemainingTime);
      expect(trailingTime().data, '-1:40');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        find.byKey(const ValueKey('player-playback-info')),
        findsOneWidget,
      );
      await waitUntil(() => find.text('Test · 本地文件夹').evaluate().isNotEmpty);
      expect(find.text('Film'), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.byKey(const ValueKey('player-playback-info')), findsNothing);
      expect(closed, isFalse);
      await tester.tap(find.byTooltip('锁定控制栏'));
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.byTooltip('显示控制栏'), findsOneWidget);
      expect(
        find.descendant(
          of: lockControl,
          matching: find.byIcon(Icons.lock_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-controls-layer')),
            )
            .opacity,
        0,
      );
      expect(
        tester
            .widget<MouseRegion>(
              find.byKey(const ValueKey('player-interaction-region')),
            )
            .cursor,
        SystemMouseCursors.basic,
      );
      await finish(session.toggle());
      await tester.pump();
      expect(session.clock.playing, isFalse);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-controls-layer')),
            )
            .opacity,
        0,
      );
      await finish(session.toggle());
      await tester.pump();
      await tester.tap(find.byTooltip('显示控制栏'));
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.byTooltip('锁定控制栏'), findsOneWidget);
      expect(
        find.descendant(
          of: lockControl,
          matching: find.byIcon(Icons.lock_open_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('player-controls-layer')),
            )
            .opacity,
        1,
      );
      if (Platform.isWindows || Platform.isLinux) {
        expect(find.byTooltip('最小化'), findsOneWidget);
        expect(find.byTooltip('最大化'), findsOneWidget);
        expect(find.byTooltip('关闭播放器'), findsOneWidget);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await waitUntil(
        () => session.clock.position == const Duration(seconds: 5),
      );
      expect(session.clock.position, const Duration(seconds: 5));
      await tester.tap(find.byTooltip('播放/暂停'));
      await finish(session.save());
      await tester.pump();
      expect(session.clock.playing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await waitUntil(() => session.clock.playing);
      expect(session.clock.playing, isTrue);
      final slider = find.byKey(const ValueKey('video-timeline'));
      await tester.tapAt(tester.getCenter(slider));
      await tester.pump();
      expect(session.clock.position.inSeconds, inInclusiveRange(45, 55));
      await tester.pump(const Duration(milliseconds: 3300));
      final interactionRegion = tester.widget<MouseRegion>(
        find.byKey(const ValueKey('player-interaction-region')),
      );
      expect(interactionRegion.cursor, SystemMouseCursors.none);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(session.clock.volume, 0);
      expect(find.byKey(const ValueKey('player-volume-hud')), findsOneWidget);
      expect(
        tester
            .widget<MouseRegion>(
              find.byKey(const ValueKey('player-interaction-region')),
            )
            .cursor,
        SystemMouseCursors.none,
      );
      await tester.pump(const Duration(milliseconds: 951));
      await tester.pump(const Duration(milliseconds: 181));
      expect(find.byKey(const ValueKey('player-volume-hud')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fullscreen, isFalse);
      expect(closed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await finish(session.close());
      await tester.pump();
      expect(closed, isTrue);
      PlaybackRecord? saved;
      await finish(records.read(film).then((record) => saved = record));
      expect(saved!.position.inSeconds, inInclusiveRange(45, 55));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    },
  );
  testWidgets(
    'A–B shortcut after a failed open does not dereference an empty selection',
    (tester) async {
      Future<void> finish(Future<void> operation) async {
        var done = false;
        operation.then((_) => done = true);
        for (var i = 0; i < 150 && !done; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue, reason: 'Player operation did not settle');
      }

      final missing = (sourceId: film.sourceId, localId: 'missing.mkv');
      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: missing,
            session: session,
            closeWindow: () async {},
            setFullscreen: (_) async {},
          ),
        ),
      );
      await finish(session.open(missing));
      await tester.pump();
      expect(session.engine, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await finish(session.refreshQueue());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(session.precision.value.loop.start, isNull);
      await tester.pumpWidget(const SizedBox());
      await finish(session.close(discardProgress: true));
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    },
  );
  testWidgets(
    'precision UI exposes markers, loop state, frame steps and shortcuts',
    (tester) async {
      Future<void> waitUntil(bool Function() done) async {
        for (var i = 0; i < 150; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (done()) return;
        }
        fail('Precision player UI did not settle');
      }

      Future<void> finish(Future<void> future) async {
        var done = false;
        future.then((_) => done = true);
        await waitUntil(() => done);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerPage(
            identity: film,
            session: session,
            closeWindow: () async {},
            setFullscreen: (_) async {},
          ),
        ),
      );
      await waitUntil(
        () =>
            !session.loading &&
            session.clock.duration > Duration.zero &&
            session.precision.value.identity == film &&
            session.precision.value.supported,
      );
      // Native engines continue emitting clocks after open; mirror that first
      // post-loading tick so the control availability projection updates.
      engines.single.emit();
      await tester.pump();

      final markerTooltip = find.byTooltip('章节与播放标记');
      expect(markerTooltip, findsOneWidget);
      final markerButton = find.descendant(
        of: markerTooltip,
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(markerButton).onPressed, isNotNull);
      await tester.tap(markerButton);
      await tester.pump();
      expect(find.byKey(const ValueKey('player-marker-panel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-playback-bookmark')));
      await waitUntil(() => session.precision.value.bookmarks.length == 1);
      final bookmark = session.precision.value.bookmarks.single;
      expect(
        find.byKey(ValueKey('playback-marker-${bookmark.id}')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('timeline-marker-${bookmark.id}')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await waitUntil(() => session.precision.value.loop.start != null);
      expect(session.precision.value.loop.end, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await waitUntil(
        () => session.clock.position == const Duration(seconds: 5),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await waitUntil(() => session.precision.value.loop.end != null);
      expect(find.byKey(const ValueKey('ab-loop-indicator')), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await waitUntil(() => session.precision.value.loop.start == null);

      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await waitUntil(() => engines.single.frameSteps.length == 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await waitUntil(() => engines.single.frameSteps.length == 2);
      expect(engines.single.frameSteps, [true, false]);

      await tester.tapAt(const Offset(400, 260), buttons: 2);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('player-precision-menu')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('toggle-current-loop')));
      await waitUntil(() => session.precision.value.loop.loopCurrentItem);
      expect(engines.single.loopCurrentItem, isTrue);
      await tester.tap(find.byKey(const ValueKey('open-playback-info')));
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        find.byKey(const ValueKey('player-playback-info')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('player-precision-menu')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 180));

      await tester.pumpWidget(const SizedBox());
      await finish(session.close());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    },
  );
  for (final discard in [false, true]) {
    testWidgets(
      'failed close dialog: ${discard ? 'explicit discard' : 'failed retry stays usable and later closes'}',
      (tester) async {
        var closed = false;
        Future<void> waitUntil(bool Function() done) async {
          for (var i = 0; i < 200; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
            if (done()) return;
          }
          fail('Close dialog did not settle');
        }

        Future<void> finish(Future<void> future) async {
          var done = false;
          future.then((_) => done = true);
          await waitUntil(() => done);
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              home: VideoPlayerPage(
                identity: film,
                session: session,
                closeWindow: () async {
                  closed = true;
                },
                setFullscreen: (_) async {},
              ),
            ),
          );
          await waitUntil(
            () => !session.loading && session.clock.duration > Duration.zero,
          );
          final decoder = engines.single;
          decoder.emit(position: const Duration(seconds: 22));
          await finish(
            sources.database.customStatement(
              "CREATE TRIGGER reject_progress BEFORE INSERT ON playback_states BEGIN SELECT RAISE(ABORT, 'test failure'); END",
            ),
          );
          await tester.tap(find.byTooltip('关闭播放器'));
          await waitUntil(
            () => find
                .byKey(const ValueKey('player-decision-dialog'))
                .evaluate()
                .isNotEmpty,
          );
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('播放进度未保存'), findsOneWidget);
          expect(
            tester
                .getSize(find.byKey(const ValueKey('player-decision-dialog')))
                .width,
            430,
          );
          expect(closed, isFalse);
          expect(session.engine, same(decoder));
          expect(decoder.disposals, 0);
          await tester.tap(find.text(discard ? '仍然关闭' : '重试'));
          if (discard) {
            await waitUntil(() => closed);
            expect(decoder.disposals, 1);
          } else {
            await waitUntil(
              () => find
                  .byKey(const ValueKey('player-decision-dialog'))
                  .evaluate()
                  .isEmpty,
            );
            // Drain the actual retry write before checking commands/window state.
            await finish(session.save());
            expect(closed, isFalse);
            expect(session.saveError, isNotNull);
            expect(session.engine, same(decoder));
            expect(decoder.disposals, 0);
            await tester.tap(find.byTooltip('播放/暂停'));
            await waitUntil(() => session.clock.playing);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await waitUntil(() => session.clock.position.inSeconds == 27);
            await finish(
              sources.database.customStatement('DROP TRIGGER reject_progress'),
            );
            await finish(
              File(p.join(sandbox.path, 'Second.mkv'))
                  .writeAsString('second')
                  .then((_) {}),
            );
            await finish(sources.scan(source.id));
            await finish(
              session.open((sourceId: source.id, localId: 'Second.mkv')),
            );
            expect(session.saveError, isNull);
            expect(decoder.disposals, 1);
            expect(session.item!.identity.localId, 'Second.mkv');
            PlaybackRecord? saved;
            await finish(records.read(film).then((record) => saved = record));
            expect(saved!.position.inSeconds, 27);
            await tester.tap(find.byTooltip('关闭播放器'));
            await waitUntil(() => closed);
            expect(engines.last.disposals, 1);
          }
          expect(session.engine, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await finish(session.close(discardProgress: true));
          await tester.pumpWidget(const SizedBox());
          session.dispose();
          await finish(sources.close());
          resourcesClosed = true;
        }
      },
    );
  }
}

class _ScreenshotFakeVideoEngine extends FakeVideoEngine
    implements VideoScreenshotEngine {
  final capturedModes = <VideoScreenshotMode>[];
  bool failCapture = false;
  bool failCaptureUnexpectedly = false;

  @override
  Future<Uint8List> captureCurrentFrame(VideoScreenshotMode mode) async {
    capturedModes.add(mode);
    if (failCapture) {
      throw const VideoScreenshotFailure('测试截图失败');
    }
    if (failCaptureUnexpectedly) {
      throw StateError(r'secret C:\media\Film.mkv');
    }
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
  }
}

class _FakePlayerWindowGateway implements PlayerWindowGateway {
  Rect bounds = const Rect.fromLTWH(100, 80, 960, 540);
  bool alwaysOnTop = false;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<Rect> getVisibleScreenBounds(Rect windowBounds) async =>
      const Rect.fromLTWH(0, 0, 1920, 1080);

  @override
  Future<bool> isFullScreen() async => false;

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> unmaximize() async {}

  @override
  Future<void> maximize() async {}

  @override
  Future<void> setBounds(Rect value) async => bounds = value;

  @override
  Future<void> setMinimumSize(Size value) async {}

  @override
  Future<void> setAspectRatio(double aspectRatio) async {}

  @override
  Future<void> setAlwaysOnTop(bool enabled) async => alwaysOnTop = enabled;

  @override
  Future<void> setVisibleOnAllWorkspaces(bool enabled) async {}

  @override
  Future<void> focus() async {}
}
