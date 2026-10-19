import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
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
  Future<void> _colorOperations = Future.value();
  Future<void> _sharpenOperations = Future.value();
  bool rejectSharpen = false;

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

  @override
  Future<void> updateColorAdjustments(
    VideoColorAdjustments Function(VideoColorAdjustments current) update,
  ) {
    final operation = _colorOperations.then((_) async {
      await Future<void>.delayed(Duration.zero);
      colorAdjustments = update(colorAdjustments).normalized;
      controlError = null;
      notifyListeners();
    });
    _colorOperations = operation;
    return operation;
  }

  @override
  Future<void> setSharpenMode(VideoSharpenMode mode) {
    final operation = _sharpenOperations.then((_) async {
      await Future<void>.delayed(Duration.zero);
      if (rejectSharpen) {
        controlError = '锐化设置应用失败，请重试。';
      } else {
        sharpenMode = mode;
        controlError = null;
      }
      notifyListeners();
    });
    _sharpenOperations = operation;
    return operation;
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
      expect(find.text('画面调整'), findsOneWidget);
      expect(find.text('亮度'), findsOneWidget);
      expect(find.text('对比度'), findsOneWidget);
      expect(find.text('饱和度'), findsOneWidget);
      expect(find.text('伽马'), findsOneWidget);
      expect(find.text('色相'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-color-brightness-increase')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('video-color-hue-reset')),
        findsOneWidget,
      );
      for (final mode in VideoSharpenMode.values) {
        expect(
          find.byKey(ValueKey('video-sharpen-${mode.name}')),
          findsOneWidget,
        );
      }

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

      final brightnessIncrease = find.byKey(
        const ValueKey('video-color-brightness-increase'),
      );
      final contrastDecrease = find.byKey(
        const ValueKey('video-color-contrast-decrease'),
      );
      await tester.ensureVisible(contrastDecrease);
      await tester.pumpAndSettle();
      for (var index = 0; index < 3; index++) {
        await tester.tap(brightnessIncrease);
      }
      for (var index = 0; index < 2; index++) {
        await tester.tap(contrastDecrease);
      }
      await tester.pumpAndSettle();
      expect(session.colorAdjustments.brightness, 15);
      expect(session.colorAdjustments.contrast, -10);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('video-color-brightness-value')),
          matching: find.text('+15'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('video-color-brightness-reset')),
      );
      final hueDecrease = find.byKey(
        const ValueKey('video-color-hue-decrease'),
      );
      final saturationIncrease = find.byKey(
        const ValueKey('video-color-saturation-increase'),
      );
      await tester.ensureVisible(hueDecrease);
      await tester.pumpAndSettle();
      for (var index = 0; index < 22; index++) {
        await tester.tap(hueDecrease);
        await tester.tap(saturationIncrease);
      }
      await tester.pumpAndSettle();
      expect(session.colorAdjustments.brightness, 0);
      expect(
        session.colorAdjustments.contrast,
        -10,
        reason: '恢复亮度默认值不应改动其他分量。',
      );
      expect(session.colorAdjustments.hue, -100);
      expect(session.colorAdjustments.saturation, 100);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('video-color-hue-value')),
          matching: find.text('-100'),
        ),
        findsOneWidget,
      );

      final sharpenStrong = find.byKey(const ValueKey('video-sharpen-strong'));
      await tester.ensureVisible(sharpenStrong);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('video-sharpen-light')));
      await tester.tap(find.byKey(const ValueKey('video-sharpen-medium')));
      await tester.tap(sharpenStrong);
      await tester.pumpAndSettle();
      expect(session.sharpenMode, VideoSharpenMode.strong);

      session.rejectSharpen = true;
      await tester.tap(find.byKey(const ValueKey('video-sharpen-off')));
      await tester.pumpAndSettle();
      expect(session.sharpenMode, VideoSharpenMode.strong);
      expect(find.text('锐化设置应用失败，请重试。'), findsOneWidget);
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
      expect(find.text('画面调整'), findsOneWidget);

      final hueIncrease = find.byKey(
        const ValueKey('video-color-hue-increase'),
      );
      await tester.ensureVisible(hueIncrease);
      await tester.pumpAndSettle();
      await tester.tap(hueIncrease);
      await tester.pumpAndSettle();
      expect(session.colorAdjustments.hue, 5);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('video-color-hue-value')),
          matching: find.text('+5'),
        ),
        findsOneWidget,
      );

      final sharpenStrong = find.byKey(const ValueKey('video-sharpen-strong'));
      await tester.ensureVisible(sharpenStrong);
      await tester.pumpAndSettle();
      await tester.tap(sharpenStrong);
      await tester.pumpAndSettle();
      expect(session.sharpenMode, VideoSharpenMode.strong);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await sources.close();
    }
  });
}
