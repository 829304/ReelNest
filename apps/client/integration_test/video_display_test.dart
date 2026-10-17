import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'display controls change real texture geometry and preserve playback',
    (tester) async {
      MediaKit.ensureInitialized();
      final temporary = await RuntimeStoragePaths.current.temporary();
      final sandbox = await temporary.createTemp('reelnest-native-display-');
      final player = Player(
        configuration: const PlayerConfiguration(muted: true, libass: true),
      );
      final engine = MediaKitVideoEngine(player: player);
      final native = player.platform as NativePlayer;
      final viewport = ValueNotifier(const Size(400, 400));
      const videoKey = ValueKey('native-display-surface');
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        await tester.pump();
      }

      Future<ByteData> pixels() async {
        await settle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(videoKey),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          expect(image.width, viewport.value.width.toInt());
          expect(image.height, viewport.value.height.toInt());
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }

      double light(ByteData data, {required bool top}) {
        var sum = 0;
        for (var y = top ? 20 : 180; y < (top ? 50 : 220); y++) {
          for (var x = 160; x < 240; x++) {
            final offset = (y * 400 + x) * 4;
            sum +=
                data.getUint8(offset) +
                data.getUint8(offset + 1) +
                data.getUint8(offset + 2);
          }
        }
        return sum / ((top ? 30 : 40) * 80 * 3);
      }

      double mirroredDifference(
        ByteData before,
        ByteData after,
        VideoFlipMode flip,
      ) {
        var difference = 0, samples = 0;
        for (var y = 120; y < 280; y += 7) {
          for (var x = 70; x < 330; x += 11) {
            final sx =
                flip == VideoFlipMode.horizontal || flip == VideoFlipMode.both
                ? 399 - x
                : x;
            final sy =
                flip == VideoFlipMode.vertical || flip == VideoFlipMode.both
                ? 399 - y
                : y;
            for (var channel = 0; channel < 3; channel++) {
              difference +=
                  (before.getUint8((sy * 400 + sx) * 4 + channel) -
                          after.getUint8((y * 400 + x) * 4 + channel))
                      .abs();
              samples++;
            }
          }
        }
        return difference / samples;
      }

      try {
        final file = await createTrackVideoFixture(
          p.join(sandbox.path, 'sample.mkv'),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: videoKey,
                child: ValueListenableBuilder<Size>(
                  valueListenable: viewport,
                  builder: (_, size, _) => SizedBox(
                    width: size.width,
                    height: size.height,
                    child: engine.surface(),
                  ),
                ),
              ),
            ),
          ),
        );
        await engine.open(file.path, Duration.zero);
        await native.setProperty('sub-visibility', 'no');
        await engine.play();
        await settle();
        await engine.pause();
        final baseline = await pixels();
        expect(
          light(baseline, top: true),
          lessThan(2),
          reason: '16:9 content has top bars in square viewport',
        );
        expect(
          light(baseline, top: false),
          greaterThan(10),
          reason: 'Texture capture must contain actual video',
        );
        final beforePosition = double.parse(
          await native.getProperty('time-pos'),
        );
        final hwdec = await native.getProperty('hwdec');
        await engine.setDisplaySettings(
          const VideoDisplaySettings(cropMode: VideoCropMode.fill),
        );
        final filled = await pixels();
        expect(
          light(filled, top: true),
          greaterThan(10),
          reason: 'panscan must visibly remove the viewport bars',
        );
        await engine.setDisplaySettings(
          const VideoDisplaySettings(
            aspectOverride: VideoAspectOverride.square,
          ),
        );
        expect(light(await pixels(), top: true), greaterThan(10));
        expect(engine.videoAspectRatio, closeTo(1, .02));
        await engine.setDisplaySettings(
          const VideoDisplaySettings(
            rotationMode: VideoRotationMode.clockwise90,
          ),
        );
        await settle();
        expect(engine.videoAspectRatio, closeTo(9 / 16, .02));
        // Square content avoids the odd-sized 225px source rectangle and its
        // asymmetric letterbox rounding when comparing vertical mirror pixels.
        await engine.setDisplaySettings(
          const VideoDisplaySettings(
            aspectOverride: VideoAspectOverride.square,
          ),
        );
        final mirrorBaseline = await pixels();
        for (final flip in [
          VideoFlipMode.horizontal,
          VideoFlipMode.vertical,
          VideoFlipMode.both,
        ]) {
          await engine.setDisplaySettings(
            VideoDisplaySettings(
              aspectOverride: VideoAspectOverride.square,
              flipMode: flip,
            ),
          );
          expect(
            mirroredDifference(mirrorBaseline, await pixels(), flip),
            lessThan(5),
            reason: '$flip must visibly mirror the frame',
          );
        }
        await engine.setDisplaySettings(
          const VideoDisplaySettings(
            aspectOverride: VideoAspectOverride.fourByThree,
            cropMode: VideoCropMode.balanced,
            deinterlaceMode: VideoDeinterlaceMode.auto,
            rotationMode: VideoRotationMode.counterclockwise90,
            flipMode: VideoFlipMode.both,
          ),
        );
        expect(await native.getProperty('deinterlace'), 'auto');
        expect(
          '${readMpvNodeProperty(native, 'vf')}',
          contains('reelnest-vflip'),
        );
        await engine.setDisplaySettings(
          const VideoDisplaySettings(deinterlaceMode: VideoDeinterlaceMode.on),
        );
        expect(await native.getProperty('deinterlace'), 'yes');
        await settle();
        expect(await native.getProperty('deinterlace-active'), 'yes');
        await engine.setDisplaySettings(const VideoDisplaySettings());
        final restored = await pixels();
        expect(light(restored, top: true), lessThan(2));
        expect(
          '${readMpvNodeProperty(native, 'vf')}',
          isNot(contains('reelnest-')),
        );
        expect(await native.getProperty('pause'), 'yes');
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(beforePosition, .02),
        );
        expect(await native.getProperty('hwdec'), hwdec);
        viewport.value = const Size(480, 270);
        await tester.pump();
        // Texture replacement and the first render at the new size cross the
        // platform thread; a Flutter layout alone does not mean mpv rendered it.
        final resizeDeadline = DateTime.now().add(const Duration(seconds: 4));
        while ((readMpvNodeProperty(native, 'osd-dimensions') as Map)['w'] !=
            480) {
          if (DateTime.now().isAfter(resizeDeadline)) {
            fail('Native viewport did not follow the resized Flutter surface');
          }
          await settle();
        }
        final resized = await pixels();
        expect(resized.lengthInBytes, 480 * 270 * 4);
        final dimensions = readMpvNodeProperty(native, 'osd-dimensions') as Map;
        expect(dimensions['w'], 480);
        expect(dimensions['h'], 270);
        viewport.value = const Size(400, 400);
        await tester.pump();
        expect(light(await pixels(), top: true), lessThan(2));
        await engine.play();
        await engine.setDisplaySettings(
          const VideoDisplaySettings(flipMode: VideoFlipMode.vertical),
        );
        expect(engine.clock.playing, isTrue);
        await engine.pause();
        binding.reportData = {
          'viewportCropVisible': true,
          'aspectAndRotation': true,
          'flipAndDeinterlace': true,
          'pausedPositionPreserved': true,
          'playingPreserved': true,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await engine.dispose();
        viewport.dispose();
        expect(
          p.isWithin(
            await temporary.resolveSymbolicLinks(),
            await sandbox.resolveSymbolicLinks(),
          ),
          isTrue,
        );
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-native-display-'),
        );
        await sandbox.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux,
  );
}
