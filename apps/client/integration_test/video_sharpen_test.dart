import 'dart:io';
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
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/color_video_fixture.dart';
import '../test/support/track_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ByteData? rgbGpu;
  for (final accelerated in [true, false]) {
    testWidgets(
      'original sharpen pixels and filter combinations (GPU=$accelerated)',
      (tester) async {
        MediaKit.ensureInitialized();
        final temporary = await RuntimeStoragePaths.current.temporary();
        final sandbox = await temporary.createTemp('reelnest-sharpen-texture-');
        final player = Player(
          configuration: const PlayerConfiguration(muted: true),
        );
        final native = player.platform as NativePlayer;
        final engine = MediaKitVideoEngine(
          player: player,
          videoConfiguration: VideoControllerConfiguration(
            enableHardwareAcceleration: accelerated,
          ),
        );
        const key = ValueKey('sharpen-texture');
        Future<void> mount({double width = 320, double height = 180}) =>
            tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: RepaintBoundary(
                    key: key,
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
            () => Future<void>.delayed(const Duration(milliseconds: 350)),
          );
          await tester.pump();
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(key))
              .toImage(pixelRatio: 1);
          try {
            expect(image.width, width);
            expect(image.height, height);
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
          } finally {
            image.dispose();
          }
        }

        double difference(ByteData a, ByteData b) {
          var sum = 0, count = 0;
          for (var y = 25; y < 155; y += 2) {
            for (var x = 25; x < 295; x += 2) {
              for (var c = 0; c < 3; c++) {
                final at = (y * 320 + x) * 4 + c;
                sum += (a.getUint8(at) - b.getUint8(at)).abs();
                count++;
              }
            }
          }
          return sum / count;
        }

        List<String> labels() => (readMpvNodeProperty(native, 'vf') as List)
            .map((e) => '${e['label']}')
            .toList();
        try {
          final file = await createColorVideoFixture(
            p.join(sandbox.path, 'sample.y4m'),
            detail: true,
            width: 320,
            height: 180,
          );
          await mount();
          await engine.open(file.path, Duration.zero);
          await engine.play();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 600)),
          );
          await engine.pause();
          final baseline = await pixels();
          final position = double.parse(await native.getProperty('time-pos'));
          final hwdec = await native.getProperty('hwdec');
          var previousDifference = 0.0;
          for (final mode in [
            VideoSharpenMode.light,
            VideoSharpenMode.medium,
            VideoSharpenMode.strong,
          ]) {
            await engine.setSharpenMode(mode);
            final changed = difference(baseline, await pixels());
            expect(
              changed,
              greaterThan(previousDifference + .1),
              reason: 'Stronger original unsharp preset increases visible sharpening',
            );
            previousDifference = changed;
            expect(await native.getProperty('pause'), 'yes');
            expect(
              double.parse(await native.getProperty('time-pos')),
              closeTo(position, .02),
            );
            await engine.setSharpenMode(VideoSharpenMode.off);
            expect(
              difference(baseline, await pixels()),
              lessThan(1),
              reason: 'Off returns to untouched paused video',
            );
          }
          // Keep a foreign/base stage while changing all owned filters.
          await native.command([
            'vf',
            'add',
            '@fixture-format:format=fmt=yuv420p',
          ]);
          const colors = VideoColorAdjustments(
            brightness: 12,
            contrast: -10,
            gamma: 20,
            saturation: -20,
            hue: 15,
          );
          const display = VideoDisplaySettings(flipMode: VideoFlipMode.both);
          await engine.setColorAdjustments(colors);
          await engine.setSharpenMode(VideoSharpenMode.medium);
          await engine.setDisplaySettings(display);
          final expected = [
            'fixture-format',
            'reelnest-hflip',
            'reelnest-vflip',
            'reelnest-sharpen',
            if (!accelerated) 'reelnest-color',
          ];
          expect(labels(), expected);
          final first = await pixels();
          await engine.setColorAdjustments(VideoColorAdjustments.neutral);
          await engine.setDisplaySettings(const VideoDisplaySettings());
          await engine.setSharpenMode(VideoSharpenMode.off);
          await engine.setSharpenMode(VideoSharpenMode.medium);
          await engine.setDisplaySettings(display);
          await engine.setColorAdjustments(colors);
          expect(labels(), expected);
          expect(
            difference(first, await pixels()),
            lessThan(1),
            reason: 'Operation order does not change the resulting video',
          );
          await mount(width: 400, height: 240);
          await pixels(width: 400, height: 240);
          await mount();
          expect(difference(first, await pixels()), lessThan(2));
          expect(await native.getProperty('pause'), 'yes');
          expect(
            double.parse(await native.getProperty('time-pos')),
            closeTo(position, .02),
          );
          expect(await native.getProperty('hwdec'), hwdec);
          await engine.setSharpenMode(VideoSharpenMode.off);
          expect(engine.colorAdjustments, colors);
          expect(engine.displaySettings, display);
          expect(
            labels(),
            expected.where((label) => label != 'reelnest-sharpen').toList(),
          );
          await engine.play();
          await engine.setSharpenMode(VideoSharpenMode.strong);
          await pixels();
          expect(engine.clock.playing, isTrue);
          expect(engine.clock.error, isNull);
          await engine.pause();
          await engine.setColorAdjustments(VideoColorAdjustments.neutral);
          await engine.setDisplaySettings(const VideoDisplaySettings());
          await engine.setSharpenMode(VideoSharpenMode.off);
          await native.command(['vf', 'remove', '@fixture-format']);
          final rgb = await createTrackVideoFixture(
            p.join(sandbox.path, 'rgb.mkv'),
            smoothColors: true,
          );
          await engine.open(rgb.path, Duration.zero);
          await engine.play();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 600)),
          );
          await engine.pause();
          await engine.setSharpenMode(VideoSharpenMode.medium);
          await pixels();
          final matrixBeforeColor = await native.getProperty(
            'video-out-params/colormatrix',
          );
          await engine.setColorAdjustments(
            const VideoColorAdjustments(saturation: -100, hue: 60),
          );
          final rgbColors = await pixels();
          if (accelerated) {
            rgbGpu = rgbColors;
          } else {
            expect(
              difference(rgbGpu!, rgbColors),
              lessThan(3),
              reason:
                  'RGB -> unsharp -> color must match GPU; intermediate matrix=$matrixBeforeColor',
            );
          }
          await engine.setSharpenMode(VideoSharpenMode.off);
          final rgbNoSharp = await pixels();
          await engine.setColorAdjustments(VideoColorAdjustments.neutral);
          expect(
            difference(rgbNoSharp, await pixels()),
            lessThan(2),
            reason: 'Disabling unsharp restores original RGB hue/saturation semantics',
          );
          await engine.setColorAdjustments(
            const VideoColorAdjustments(saturation: -100, hue: 60),
          );
          await engine.setSharpenMode(VideoSharpenMode.medium);
          expect(
            difference(rgbColors, await pixels()),
            lessThan(1),
            reason: 'Colors-before-sharpen and sharpen-before-colors use the same intermediate matrix',
          );
          binding.reportData = {
            ...?binding.reportData,
            'sharpenTextureGpu$accelerated': true,
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
          expect(
            p.basename(sandbox.path),
            startsWith('reelnest-sharpen-texture-'),
          );
          await sandbox.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux,
    );
  }
}
