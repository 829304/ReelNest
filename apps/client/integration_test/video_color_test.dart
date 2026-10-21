import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/player/mpv_owned_video_filters.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/color_video_fixture.dart';
import '../test/support/reference_software_colors.dart';
import '../test/support/track_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final gpuPixels = <String, ByteData>{};
  for (final accelerated in [true, false]) {
    testWidgets('color settings change paused texture pixels (GPU=$accelerated)', (
      tester,
    ) async {
      MediaKit.ensureInitialized();
      final temporary = await RuntimeStoragePaths.current.temporary();
      final sandbox = await temporary.createTemp('reelnest-native-colors-');
      final player = Player(
        configuration: const PlayerConfiguration(muted: true, libass: true),
      );
      final native = player.platform as NativePlayer;
      final engine = MediaKitVideoEngine(
        player: player,
        videoConfiguration: VideoControllerConfiguration(
          enableHardwareAcceleration: accelerated,
        ),
      );
      const surfaceKey = ValueKey('native-color-surface');
      Future<void> mount({double width = 320, double height = 180}) =>
          tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: surfaceKey,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: engine.surface(),
                  ),
                ),
              ),
            ),
          );
      Future<ByteData> pixels({int width = 320, int height = 180}) async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(surfaceKey))
            .toImage(pixelRatio: 1);
        try {
          expect(image.width, width);
          expect(image.height, height);
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }

      double difference(ByteData a, ByteData b) {
        var sum = 0, count = 0;
        for (var y = 25; y < 155; y += 3) {
          for (var x = 25; x < 295; x += 3) {
            for (var channel = 0; channel < 3; channel++) {
              final offset = (y * 320 + x) * 4 + channel;
              sum += (a.getUint8(offset) - b.getUint8(offset)).abs();
              count++;
            }
          }
        }
        return sum / count;
      }

      Future<void> verifyPreviousSoftwarePixels(
        VideoColorAdjustments value,
        ByteData optimized,
      ) async {
        if (accelerated) return;
        final filters = MpvOwnedVideoFilters(
          command: native.command,
          read: (name) async => jsonEncode(readMpvNodeProperty(native, name)),
        );
        await filters.update({
          'reelnest-color': MpvVideoFilter('reelnest-color', 'lavfi', {
            'graph': ReferenceSoftwareVideoColors.graph(
              value,
              await native.getProperty('video-params/colormatrix'),
            ),
          }),
        });
        expect(
          difference(optimized, await pixels()),
          lessThan(.5),
          reason:
              'Algebraic simplification preserves previous software pixels: ${value.toJson()}',
        );
        await engine.setColorAdjustments(value);
      }

      try {
        final file = await createColorVideoFixture(
          p.join(sandbox.path, 'sample.y4m'),
        );
        await mount();
        await engine.open(file.path, Duration.zero);
        await native.setProperty('sub-visibility', 'no');
        await engine.play();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        await engine.pause();
        expect(
          readMpvNodeProperty(native, 'user-data/reelnest/render-api'),
          accelerated ? 'opengl' : 'sw',
        );
        final baseline = await pixels();
        final position = double.parse(await native.getProperty('time-pos'));
        final hwdec = await native.getProperty('hwdec');
        for (final value in const [
          VideoColorAdjustments(brightness: 30),
          VideoColorAdjustments(contrast: 40),
          VideoColorAdjustments(saturation: -100),
          VideoColorAdjustments(gamma: 40),
          VideoColorAdjustments(hue: 60),
        ]) {
          await engine.setColorAdjustments(value);
          final changed = await pixels();
          await verifyPreviousSoftwarePixels(value, changed);
          expect(
            difference(baseline, changed),
            greaterThan(2),
            reason:
                'Each color property must visibly affect the texture: ${value.toJson()}',
          );
          final key = '${value.toJson()}';
          if (accelerated) {
            gpuPixels[key] = changed;
          } else {
            expect(
              difference(gpuPixels[key]!, changed),
              lessThan(3),
              reason: 'CPU colors match the original GPU conversion: $key',
            );
          }
          expect(await native.getProperty('pause'), 'yes');
          expect(
            double.parse(await native.getProperty('time-pos')),
            closeTo(position, .02),
          );
          await engine.setColorAdjustments(VideoColorAdjustments.neutral);
          expect(
            difference(baseline, await pixels()),
            lessThan(2),
            reason: 'Reset restores the same paused frame',
          );
        }
        const display = VideoDisplaySettings(
          aspectOverride: VideoAspectOverride.square,
          cropMode: VideoCropMode.balanced,
          rotationMode: VideoRotationMode.clockwise90,
          flipMode: VideoFlipMode.horizontal,
        );
        await engine.setDisplaySettings(display);
        final filters = '${readMpvNodeProperty(native, 'vf')}';
        await engine.setColorAdjustments(
          const VideoColorAdjustments(
            brightness: 5,
            contrast: -5,
            saturation: 10,
            gamma: 15,
            hue: -10,
          ),
        );
        expect(engine.displaySettings, display);
        final afterFilters = (readMpvNodeProperty(native, 'vf') as List)
            .where((f) => f is! Map || f['label'] != 'reelnest-color')
            .toList();
        expect('$afterFilters', filters);
        expect(await native.getProperty('video-rotate'), '90');
        expect(await native.getProperty('hwdec'), hwdec);
        await engine.play();
        await engine.setColorAdjustments(VideoColorAdjustments.neutral);
        expect(engine.clock.playing, isTrue);
        await engine.pause();
        await engine.setDisplaySettings(const VideoDisplaySettings());
        final wide = await createColorVideoFixture(
          p.join(sandbox.path, 'wide.y4m'),
          wideGamut: true,
        );
        await engine.open(wide.path, Duration.zero);
        await engine.play();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        await engine.pause();
        for (final value in const [
          VideoColorAdjustments(brightness: -40),
          VideoColorAdjustments(saturation: -100),
          VideoColorAdjustments(hue: 60, saturation: 100),
          VideoColorAdjustments(brightness: 20, contrast: -40, gamma: 40),
        ]) {
          await engine.setColorAdjustments(value);
          final changed = await pixels();
          await verifyPreviousSoftwarePixels(value, changed);
          final key = 'wide:${value.toJson()}';
          if (accelerated) {
            gpuPixels[key] = changed;
          } else {
            expect(
              difference(gpuPixels[key]!, changed),
              lessThan(3),
              reason: 'Wide chroma CPU/GPU equality: $key',
            );
          }
        }
        // Color processing precedes subtitle composition on both renderers.
        final subtitle = File(p.join(sandbox.path, 'white.ass'));
        await engine.setSharpenMode(VideoSharpenMode.medium);
        await subtitle.writeAsString(r'''[Script Info]
ScriptType: v4.00+
PlayResX: 320
PlayResY: 180
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,36,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:23.00,Default,,0,0,0,,{\an7\pos(40,130)\1c&HFFFFFF&\bord0\shad0\p1}m 0 0 l 80 0 80 20 0 20
''');
        await engine.addSubtitle(subtitle.path);
        await native.setProperty('sub-color', '#FFFFFFFF');
        await native.setProperty('sub-outline-size', '0');
        await native.setProperty('sub-shadow-offset', '0');
        await engine.setColorAdjustments(
          const VideoColorAdjustments(brightness: -100),
        );
        final subtitled = await pixels();
        var white = 0;
        for (var i = 0; i < subtitled.lengthInBytes; i += 4) {
          if (subtitled.getUint8(i) > 230 &&
              subtitled.getUint8(i + 1) > 230 &&
              subtitled.getUint8(i + 2) > 230) {
            white++;
          }
        }
        expect(
          white,
          greaterThan(15),
          reason: 'White subtitles stay white over black adjusted video',
        );
        final pausePosition = double.parse(
          await native.getProperty('time-pos'),
        );
        await mount(width: 400, height: 240);
        await pixels(width: 400, height: 240);
        await mount();
        expect(
          difference(subtitled, await pixels()),
          lessThan(2),
          reason:
              'Paused resize preserves adjusted colors and subtitle overlay',
        );
        expect(await native.getProperty('pause'), 'yes');
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(pausePosition, .02),
        );
        await native.setProperty('sub-visibility', 'no');
        expect(
          difference(await pixels(), ByteData(320 * 180 * 4)),
          lessThan(2),
        );
        await engine.setColorAdjustments(VideoColorAdjustments.neutral);
        await engine.setSharpenMode(VideoSharpenMode.off);
        final rgb = await createTrackVideoFixture(
          p.join(sandbox.path, 'rgb.mkv'),
          smoothColors: true,
        );
        await engine.open(rgb.path, Duration.zero);
        await native.setProperty('sub-visibility', 'no');
        await engine.play();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        );
        await engine.pause();
        // Use the same RGB frame and smooth gradients: mpv's GPU and SW
        // scalers differ at hard edges independently of color adjustment.
        await engine.seek(const Duration(milliseconds: 500));
        final rgbBefore = await pixels();
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(.5, .02),
        );
        if (accelerated) {
          gpuPixels['rgbBefore'] = rgbBefore;
        } else {
          expect(
            difference(gpuPixels['rgbBefore']!, rgbBefore),
            lessThan(2),
            reason: 'Compare the same RGB frame',
          );
        }
        await engine.setColorAdjustments(
          const VideoColorAdjustments(hue: 70, saturation: -100),
        );
        expect(
          difference(rgbBefore, await pixels()),
          lessThan(2),
          reason: 'Original RGB hue/saturation semantics are preserved',
        );
        await engine.setColorAdjustments(
          const VideoColorAdjustments(brightness: 30),
        );
        final rgbChanged = await pixels();
        expect(difference(rgbBefore, rgbChanged), greaterThan(2));
        if (accelerated) {
          gpuPixels['rgb'] = rgbChanged;
        } else {
          expect(difference(gpuPixels['rgb']!, rgbChanged), lessThan(3));
        }
        await engine.setColorAdjustments(VideoColorAdjustments.neutral);
        binding.reportData = {
          ...?binding.reportData,
          'colorTextureGpu$accelerated': true,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await engine.dispose();
        expect(
          p.isWithin(
            await temporary.resolveSymbolicLinks(),
            await sandbox.resolveSymbolicLinks(),
          ),
          isTrue,
        );
        expect(p.basename(sandbox.path), startsWith('reelnest-native-colors-'));
        await sandbox.delete(recursive: true);
      }
    }, skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux);
  }
}
