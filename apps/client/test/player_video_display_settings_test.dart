import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/presentation/player_behavior_settings.dart';
import 'package:reelnest/features/playback/presentation/player_video_display_settings.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

class _DisplaySettingsSession extends PlaybackSession {
  _DisplaySettingsSession(SourceRepository sources)
    : super(
        sources: sources,
        records: PlaybackRepository(sources.database),
        createEngine: FakeVideoEngine.new,
      );

  Future<void> _operations = Future.value();

  @override
  Future<void> updateDisplaySettings(
    VideoDisplaySettings Function(VideoDisplaySettings current) update,
  ) {
    final operation = _operations.then((_) async {
      await Future<void>.delayed(Duration.zero);
      displaySettings = update(displaySettings);
      controlError = null;
      notifyListeners();
    });
    _operations = operation;
    return operation;
  }

  void showError(String message) {
    controlError = message;
    notifyListeners();
  }
}

void main() {
  testWidgets('video display choices merge rapid updates and report failures', (
    tester,
  ) async {
    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    final session = _DisplaySettingsSession(sources);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SingleChildScrollView(
              child: SizedBox(
                width: 720,
                child: PlayerVideoDisplaySettings(
                  session: session,
                  palette: const PlayerPalette(lightContent: true),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('画面比例'), findsOneWidget);
      expect(find.text('黑边裁切'), findsOneWidget);
      expect(find.text('去隔行'), findsOneWidget);
      expect(find.text('画面旋转'), findsOneWidget);
      expect(find.text('镜像翻转'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-aspect-cinemaScope')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('video-crop-fill')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-deinterlace-on')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('video-rotation-counterclockwise90')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('video-flip-both')), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('video-aspect-sixteenByNine')),
      );
      await tester.tap(find.byKey(const ValueKey('video-crop-fill')));
      await tester.tap(find.byKey(const ValueKey('video-deinterlace-auto')));
      await tester.tap(
        find.byKey(const ValueKey('video-rotation-clockwise90')),
      );
      await tester.tap(find.byKey(const ValueKey('video-flip-horizontal')));
      await tester.pumpAndSettle();

      expect(
        session.displaySettings.aspectOverride,
        VideoAspectOverride.sixteenByNine,
      );
      expect(session.displaySettings.cropMode, VideoCropMode.fill);
      expect(
        session.displaySettings.deinterlaceMode,
        VideoDeinterlaceMode.auto,
      );
      expect(
        session.displaySettings.rotationMode,
        VideoRotationMode.clockwise90,
      );
      expect(session.displaySettings.flipMode, VideoFlipMode.horizontal);

      session.showError('画面设置应用失败，请重试。');
      await tester.pump();
      expect(find.text('画面设置应用失败，请重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await sources.close();
    }
  });

  testWidgets('video tab remains usable at the minimum player window size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(680, 382);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {},
    );
    final session = _DisplaySettingsSession(sources);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlayerBehaviorSettings(
                context,
                session,
                const PlayerPalette(lightContent: true),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('player-settings-tab-video')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('player-video-display-settings')),
        findsOneWidget,
      );
      expect(find.text('画面显示'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await sources.close();
    }
  });
}
