import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/player/video_engine.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _NetworkPlaybackSession extends PlaybackSession {
  _NetworkPlaybackSession(this.fake, SourceRepository sources)
    : super(
        sources: sources,
        records: PlaybackRepository(sources.database),
        createEngine: () => fake,
      );

  final FakeVideoEngine fake;

  @override
  Future<void> open(MediaIdentity identity) async {
    item = IndexedMedia(
      identity: identity,
      title: '远程影片',
      type: 'movie',
      bytes: 0,
      modified: DateTime(2026),
      remote: const RemoteMediaMetadata(externalId: 'remote-film'),
    );
    filePath = null;
    loading = false;
    error = null;
    engine = fake;
    emitSpeed(null);
    notifyListeners();
  }

  void emitSpeed(int? bytesPerSecond) {
    clock = VideoClock(
      position: clock.position,
      duration: const Duration(minutes: 100),
      playing: true,
      buffering: clock.buffering,
      completed: clock.completed,
      volume: clock.volume,
      rate: clock.rate,
      warning: clock.warning,
      error: clock.error,
      networkBytesPerSecond: bytesPerSecond,
    );
    timeline.value = clock;
  }

  void setLoading(bool value) {
    loading = value;
    notifyListeners();
  }
}

void main() {
  test('network speed uses binary KB/s and MB/s units', () {
    expect(formatPlayerNetworkSpeed(null), '-- KB/s');
    expect(formatPlayerNetworkSpeed(0), '0 KB/s');
    expect(formatPlayerNetworkSpeed(1536), '1.5 KB/s');
    expect(formatPlayerNetworkSpeed(256 * 1024), '256 KB/s');
    expect(formatPlayerNetworkSpeed(1536 * 1024), '1.5 MB/s');
  });

  test('network speed follows the player control visibility contract', () {
    bool visible({
      bool miniMode = false,
      bool remoteMedia = true,
      bool localFile = false,
      bool loading = false,
      bool hasError = false,
      bool controlsLocked = false,
      bool controlsVisible = true,
      bool playing = true,
    }) => shouldShowPlayerNetworkSpeed(
      miniMode: miniMode,
      remoteMedia: remoteMedia,
      localFile: localFile,
      loading: loading,
      hasError: hasError,
      controlsLocked: controlsLocked,
      controlsVisible: controlsVisible,
      playing: playing,
    );

    expect(visible(), isTrue);
    expect(visible(controlsVisible: false), isFalse);
    expect(visible(controlsVisible: false, playing: false), isTrue);
    expect(visible(miniMode: true), isFalse);
    expect(visible(remoteMedia: false), isFalse);
    expect(visible(localFile: true), isFalse);
    expect(visible(controlsVisible: false, loading: true), isTrue);
    expect(visible(controlsVisible: false, hasError: true), isTrue);
    expect(visible(controlsLocked: true), isFalse);
  });

  testWidgets('network speed HUD has no rectangular panel and can hide', (
    tester,
  ) async {
    Future<void> pump({required bool visible, int? bytesPerSecond}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  PlayerNetworkSpeedHud(
                    visible: visible,
                    bytesPerSecond: bytesPerSecond,
                  ),
                ],
              ),
            ),
          ),
        );

    await pump(visible: true);
    expect(
      find.byKey(const ValueKey('player-network-speed-hud')),
      findsOneWidget,
    );
    expect(find.text('-- KB/s'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('player-network-speed-hud')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );

    await pump(visible: true, bytesPerSecond: 2 * 1024 * 1024);
    expect(find.text('2.0 MB/s'), findsOneWidget);

    await pump(visible: false, bytesPerSecond: 2 * 1024 * 1024);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('player-network-speed-hud')),
      findsNothing,
    );
  });

  testWidgets(
    'page speed HUD follows auto-hide, wakes on mouse, and samples do not extend it',
    (tester) async {
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      final fake = FakeVideoEngine();
      final session = _NetworkPlaybackSession(fake, sources);
      const identity = (sourceId: 'emby', localId: 'remote-film');
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: VideoPlayerPage(
              identity: identity,
              session: session,
              closeWindow: () async {},
              setFullscreen: (_) async {},
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('player-network-speed-hud')),
          findsOneWidget,
        );
        expect(find.text('-- KB/s'), findsOneWidget);

        final interaction = find.byKey(
          const ValueKey('player-interaction-region'),
        );
        final center = tester.getCenter(interaction);
        await mouse.addPointer(location: center);
        await tester.pump();

        session.emitSpeed(1024 * 1024);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('1.0 MB/s'), findsOneWidget);
        session.emitSpeed(2 * 1024 * 1024);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('2.0 MB/s'), findsOneWidget);
        session.emitSpeed(3 * 1024 * 1024);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('3.0 MB/s'), findsOneWidget);

        session.emitSpeed(4 * 1024 * 1024);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.byKey(const ValueKey('player-network-speed-hud')),
          findsNothing,
          reason: '网速采样刷新不应重置控制栏自动隐藏计时。',
        );
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('player-controls-layer')),
              )
              .opacity,
          0,
        );

        session.setLoading(true);
        await tester.pump();
        expect(find.text('-- KB/s'), findsOneWidget);
        expect(
          tester
              .widget<AnimatedOpacity>(
                find.byKey(const ValueKey('player-controls-layer')),
              )
              .opacity,
          1,
        );
        session.setLoading(false);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('player-network-speed-hud')),
          findsNothing,
        );

        await mouse.moveTo(center + const Offset(24, 0));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('player-network-speed-hud')),
          findsOneWidget,
        );
        expect(find.text('4.0 MB/s'), findsOneWidget);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        await fake.dispose();
        session.dispose();
        await sources.close();
      }
    },
  );
}
