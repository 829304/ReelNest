import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/domain/video_performance_settings.dart';
import 'package:reelnest/features/playback/domain/video_render_settings.dart';
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
  Future<void> _performanceOperations = Future.value();
  Future<void> _renderOperations = Future.value();
  bool rejectSharpen = false;
  bool rejectPerformance = false;
  bool rejectRender = false;

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
  Future<void> updateRenderSettings({
    VideoDebandMode? debandMode,
    VideoToneMappingMode? toneMappingMode,
  }) {
    final operation = _renderOperations.then((_) async {
      await Future<void>.delayed(Duration.zero);
      if (rejectRender) {
        controlError = '视频渲染设置应用失败，请重试。';
      } else {
        renderSettings = renderSettings.copyWith(
          debandMode: debandMode,
          toneMappingMode: toneMappingMode,
        );
        controlError = null;
      }
      notifyListeners();
    });
    _renderOperations = operation;
    return operation;
  }

  @override
  Future<void> updatePerformanceSettings({
    bool? memoryBufferingEnabled,
    VideoHardwareDecodingMode? hardwareDecodingMode,
  }) {
    final operation = _performanceOperations.then((_) async {
      await Future<void>.delayed(Duration.zero);
      if (rejectPerformance) {
        controlError = '播放性能设置应用失败，请重试。';
      } else {
        performanceSettings = performanceSettings.copyWith(
          memoryBufferingEnabled: memoryBufferingEnabled,
          hardwareDecodingMode: hardwareDecodingMode,
        );
        controlError = null;
      }
      notifyListeners();
    });
    _performanceOperations = operation;
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
      Future<void> reveal(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
      }

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
      expect(find.text('播放性能'), findsOneWidget);
      expect(find.text('弱网内存缓冲'), findsOneWidget);
      expect(find.text('硬件解码'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('video-memory-buffering-toggle')),
        findsOneWidget,
      );
      for (final mode in VideoHardwareDecodingMode.values) {
        expect(
          find.byKey(ValueKey('video-hardware-decoding-${mode.name}')),
          findsOneWidget,
        );
      }
      expect(find.text('去色带'), findsOneWidget);
      expect(find.text('HDR 映射'), findsOneWidget);
      for (final mode in VideoDebandMode.values) {
        expect(
          find.byKey(ValueKey('video-deband-${mode.name}')),
          findsOneWidget,
        );
      }
      for (final mode in VideoToneMappingMode.values) {
        expect(
          find.byKey(ValueKey('video-tone-mapping-${mode.name}')),
          findsOneWidget,
        );
      }

      final aspectSixteenByNine = find.byKey(
        const ValueKey('video-aspect-sixteenByNine'),
      );
      await reveal(aspectSixteenByNine);
      await tester.tap(aspectSixteenByNine);
      final cropFill = find.byKey(const ValueKey('video-crop-fill'));
      await reveal(cropFill);
      await tester.tap(cropFill);
      final deinterlaceAuto = find.byKey(
        const ValueKey('video-deinterlace-auto'),
      );
      await reveal(deinterlaceAuto);
      await tester.tap(deinterlaceAuto);
      final rotationClockwise = find.byKey(
        const ValueKey('video-rotation-clockwise90'),
      );
      await reveal(rotationClockwise);
      await tester.tap(rotationClockwise);
      final flipHorizontal = find.byKey(
        const ValueKey('video-flip-horizontal'),
      );
      await reveal(flipHorizontal);
      await tester.tap(flipHorizontal);
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
      await reveal(brightnessIncrease);
      for (var index = 0; index < 3; index++) {
        await tester.tap(brightnessIncrease);
      }
      await reveal(contrastDecrease);
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

      final brightnessReset = find.byKey(
        const ValueKey('video-color-brightness-reset'),
      );
      await reveal(brightnessReset);
      await tester.tap(brightnessReset);
      final hueDecrease = find.byKey(
        const ValueKey('video-color-hue-decrease'),
      );
      final saturationIncrease = find.byKey(
        const ValueKey('video-color-saturation-increase'),
      );
      await reveal(hueDecrease);
      for (var index = 0; index < 22; index++) {
        await tester.tap(hueDecrease);
      }
      await reveal(saturationIncrease);
      for (var index = 0; index < 22; index++) {
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
      final sharpenLight = find.byKey(const ValueKey('video-sharpen-light'));
      final sharpenMedium = find.byKey(const ValueKey('video-sharpen-medium'));
      await reveal(sharpenLight);
      expect(sharpenMedium.hitTestable(), findsOneWidget);
      expect(sharpenStrong.hitTestable(), findsOneWidget);
      await tester.tap(sharpenLight);
      await tester.tap(sharpenMedium);
      await tester.tap(sharpenStrong);
      await tester.pumpAndSettle();
      expect(session.sharpenMode, VideoSharpenMode.strong);

      final memoryBufferingToggle = find.byKey(
        const ValueKey('video-memory-buffering-toggle'),
      );
      final hardwareAutomatic = find.byKey(
        const ValueKey('video-hardware-decoding-automatic'),
      );
      await reveal(memoryBufferingToggle);
      expect(hardwareAutomatic.hitTestable(), findsOneWidget);
      await tester.tap(memoryBufferingToggle);
      await tester.tap(hardwareAutomatic);
      await tester.pumpAndSettle();
      expect(session.performanceSettings.memoryBufferingEnabled, isFalse);
      expect(
        session.performanceSettings.hardwareDecodingMode,
        VideoHardwareDecodingMode.automatic,
      );

      final toneMappingHable = find.byKey(
        const ValueKey('video-tone-mapping-hable'),
      );
      final debandLight = find.byKey(const ValueKey('video-deband-light'));
      await reveal(toneMappingHable);
      expect(debandLight.hitTestable(), findsOneWidget);
      await tester.tap(debandLight);
      await tester.tap(toneMappingHable);
      await tester.pumpAndSettle();
      expect(session.renderSettings.debandMode, VideoDebandMode.light);
      expect(
        session.renderSettings.toneMappingMode,
        VideoToneMappingMode.hable,
      );

      session.rejectRender = true;
      final debandStrong = find.byKey(const ValueKey('video-deband-strong'));
      await reveal(debandStrong);
      await tester.tap(debandStrong);
      await tester.pumpAndSettle();
      expect(session.renderSettings.debandMode, VideoDebandMode.light);
      expect(find.text('视频渲染设置应用失败，请重试。'), findsOneWidget);

      session.rejectPerformance = true;
      final hardwareOff = find.byKey(
        const ValueKey('video-hardware-decoding-off'),
      );
      await reveal(hardwareOff);
      await tester.tap(hardwareOff);
      await tester.pumpAndSettle();
      expect(
        session.performanceSettings.hardwareDecodingMode,
        VideoHardwareDecodingMode.automatic,
      );
      expect(find.text('播放性能设置应用失败，请重试。'), findsOneWidget);

      session.rejectSharpen = true;
      final sharpenOff = find.byKey(const ValueKey('video-sharpen-off'));
      await reveal(sharpenOff);
      await tester.tap(sharpenOff);
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
      Future<void> reveal(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
      }

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

      final dialogRect = tester.getRect(
        find.byKey(const ValueKey('player-settings-dialog')),
      );
      expect(dialogRect.left, 12);
      expect(dialogRect.top, 12);
      expect(dialogRect.right, 668);
      expect(dialogRect.bottom, 370);

      final tooltipContext = tester.element(find.byTooltip('关闭设置'));
      final tooltipDecoration =
          Theme.of(tooltipContext).tooltipTheme.decoration! as BoxDecoration;
      expect(tooltipDecoration.color, const Color(0xF21A1D22));

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
      await reveal(hueIncrease);
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
      await reveal(sharpenStrong);
      await tester.tap(sharpenStrong);
      await tester.pumpAndSettle();
      expect(session.sharpenMode, VideoSharpenMode.strong);

      final memoryBufferingToggle = find.byKey(
        const ValueKey('video-memory-buffering-toggle'),
      );
      final hardwareOff = find.byKey(
        const ValueKey('video-hardware-decoding-off'),
      );
      await reveal(memoryBufferingToggle);
      await tester.tap(memoryBufferingToggle);
      await reveal(hardwareOff);
      await tester.tap(hardwareOff);
      await tester.pumpAndSettle();
      expect(session.performanceSettings.memoryBufferingEnabled, isFalse);
      expect(
        session.performanceSettings.hardwareDecodingMode,
        VideoHardwareDecodingMode.off,
      );

      final toneMappingClip = find.byKey(
        const ValueKey('video-tone-mapping-clip'),
      );
      final debandStrong = find.byKey(const ValueKey('video-deband-strong'));
      await reveal(toneMappingClip);
      expect(debandStrong.hitTestable(), findsOneWidget);
      await tester.tap(debandStrong);
      await tester.tap(toneMappingClip);
      await tester.pumpAndSettle();
      expect(session.renderSettings.debandMode, VideoDebandMode.strong);
      expect(session.renderSettings.toneMappingMode, VideoToneMappingMode.clip);

      session.rejectRender = true;
      final debandOff = find.byKey(const ValueKey('video-deband-off'));
      await reveal(debandOff);
      await tester.tap(debandOff);
      await tester.pumpAndSettle();
      expect(session.renderSettings.debandMode, VideoDebandMode.strong);
      expect(
        find.byKey(const ValueKey('player-settings-control-error')),
        findsOneWidget,
      );
      expect(
        find
            .byKey(const ValueKey('player-settings-control-error'))
            .hitTestable(),
        findsOneWidget,
        reason: '设置失败提示应固定在当前视野，而不是留在长列表末尾。',
      );
      expect(find.text('视频渲染设置应用失败，请重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await sources.close();
    }
  });
}
