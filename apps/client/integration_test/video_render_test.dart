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
import 'package:reelnest/features/playback/domain/video_render_settings.dart';
import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/player/video_render_settings_engine.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/render_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final gpu in [true, false]) {
    testWidgets('deband and HDR texture capability (GPU=$gpu)', (tester) async {
      MediaKit.ensureInitialized();
      final temporary = await RuntimeStoragePaths.current.temporary();
      final sandbox = await temporary.createTemp('reelnest-render-texture-');
      final player = Player(
        configuration: const PlayerConfiguration(muted: true, libass: true),
      );
      final native = player.platform as NativePlayer;
      final engine = MediaKitVideoEngine(
        player: player,
        videoConfiguration: VideoControllerConfiguration(
          enableHardwareAcceleration: gpu,
        ),
      );
      final commands = MpvRenderSettingsCommands(
        command: native.command,
        read: native.getProperty,
      );
      const key = ValueKey('render-texture');
      Future<ByteData> pixels() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)),
        );
        await tester.pump();
        final image = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage(pixelRatio: 1);
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        } finally {
          image.dispose();
        }
      }

      double difference(ByteData a, ByteData b) {
        var sum = 0, count = 0;
        for (var y = 5; y < 175; y++) {
          for (var x = 5; x < 315; x++) {
            for (var c = 0; c < 3; c++) {
              final at = (y * 320 + x) * 4 + c;
              sum += (a.getUint8(at) - b.getUint8(at)).abs();
              count++;
            }
          }
        }
        return sum / count;
      }

      try {
        final file = await createRenderVideoFixture(
          p.join(sandbox.path, 'ramp.y4m'),
        );
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
        await mount();
        await engine.open(file.path, Duration.zero);
        await native.command(['set', 'dither-depth', 'no']);
        if (gpu) {
          await engine.setRenderSettings(const VideoRenderSettings());
        } else {
          await expectLater(
            engine.setRenderSettings(const VideoRenderSettings()),
            throwsA(isA<VideoRenderUnavailable>()),
          );
          await commands.apply(const VideoRenderSettings());
        }
        final position = double.parse(await native.getProperty('time-pos'));
        final original = await pixels();
        final changes = <String, double>{};
        for (final mode in [VideoDebandMode.light, VideoDebandMode.strong]) {
          final settings = VideoRenderSettings(debandMode: mode);
          // Bypass the production SW gate only in this isolated capability
          // probe to distinguish accepted properties from working pixels.
          if (gpu) {
            await engine.setRenderSettings(settings);
          } else {
            await commands.apply(settings);
          }
          expect(await commands.current(), settings);
          changes['deband-${mode.name}'] = difference(original, await pixels());
        }
        await commands.apply(const VideoRenderSettings());
        expect(difference(original, await pixels()), lessThan(.5));
        await native.command([
          'vf',
          'add',
          '@fixture-hdr:format=gamma=pq:primaries=bt.2020:colormatrix=bt.2020-ncl:max-luma=1000',
        ]);
        await pixels();
        expect(await native.getProperty('video-out-params/gamma'), 'pq');
        final hdr = <VideoToneMappingMode, ByteData>{};
        for (final mode in VideoToneMappingMode.values) {
          final settings = VideoRenderSettings(toneMappingMode: mode);
          if (gpu) {
            await engine.setRenderSettings(settings);
          } else {
            await commands.apply(settings);
          }
          expect(await commands.current(), settings);
          hdr[mode] = await pixels();
        }
        for (final mode in VideoToneMappingMode.values) {
          changes['hdr-${mode.name}-vs-clip'] = difference(
            hdr[mode]!,
            hdr[VideoToneMappingMode.clip]!,
          );
        }
        if (gpu) {
          expect(changes['deband-light'], greaterThan(.05));
          expect(changes['deband-strong'], greaterThan(.05));
          expect(changes['hdr-reinhard-vs-clip'], greaterThan(3));
          expect(changes['hdr-hable-vs-clip'], greaterThan(3));
          expect(
            difference(
              hdr[VideoToneMappingMode.auto]!,
              hdr[VideoToneMappingMode.bt2390]!,
            ),
            lessThan(.5),
          );
          // Combined VO properties must not rebuild vf, change decoder mode,
          // overwrite color controls or disturb the paused media position.
          const colors = VideoColorAdjustments(brightness: 10, gamma: 15);
          await engine.setColorAdjustments(colors);
          await engine.setSharpenMode(VideoSharpenMode.medium);
          await engine.setDisplaySettings(
            const VideoDisplaySettings(flipMode: VideoFlipMode.horizontal),
          );
          final filters = jsonEncode(readMpvNodeProperty(native, 'vf'));
          final hwdec = await native.getProperty('hwdec');
          const combination = VideoRenderSettings(
            debandMode: VideoDebandMode.light,
            toneMappingMode: VideoToneMappingMode.hable,
          );
          await engine.setRenderSettings(combination);
          final combined = await pixels();
          await engine.setRenderSettings(const VideoRenderSettings());
          await engine.setRenderSettings(combination);
          expect(difference(combined, await pixels()), lessThan(1));
          expect(jsonEncode(readMpvNodeProperty(native, 'vf')), filters);
          expect(await native.getProperty('hwdec'), hwdec);
          expect(engine.colorAdjustments, colors);
          expect(double.parse(await native.getProperty('gamma')), 15);
          await mount(width: 400, height: 240);
          await pixels();
          await mount();
          expect(difference(combined, await pixels()), lessThan(1));
          await engine.setColorAdjustments(VideoColorAdjustments.neutral);
          await engine.setSharpenMode(VideoSharpenMode.off);
          await engine.setDisplaySettings(const VideoDisplaySettings());
          // HLG is a distinct input transfer, not a PQ option alias.
          await native.command([
            'vf',
            'add',
            '@fixture-hdr:format=gamma=hlg:primaries=bt.2020:colormatrix=bt.2020-ncl:max-luma=1000',
          ]);
          await pixels();
          expect(await native.getProperty('video-out-params/gamma'), 'hlg');
          await engine.setRenderSettings(
            const VideoRenderSettings(
              toneMappingMode: VideoToneMappingMode.hable,
            ),
          );
          final hlg = await pixels();
          await engine.setRenderSettings(
            const VideoRenderSettings(
              toneMappingMode: VideoToneMappingMode.clip,
            ),
          );
          changes['hlg-hable-vs-clip'] = difference(hlg, await pixels());
          expect(changes['hlg-hable-vs-clip'], greaterThan(1));
          await engine.setRenderSettings(
            const VideoRenderSettings(
              toneMappingMode: VideoToneMappingMode.hable,
            ),
          );
          final subtitle = File(p.join(sandbox.path, 'white.ass'));
          await subtitle.writeAsString('''[Script Info]
ScriptType: v4.00+
PlayResX: 320
PlayResY: 180
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,28,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,2,0,0,10,1
[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:00.00,0:00:23.00,Default,WHITE
''');
          int white(ByteData data) {
            var result = 0;
            for (var y = 125; y < 175; y++) {
              for (var x = 130; x < 190; x++) {
                final at = (y * 320 + x) * 4;
                if (data.getUint8(at) > 230 &&
                    data.getUint8(at + 1) > 230 &&
                    data.getUint8(at + 2) > 230) {
                  result++;
                }
              }
            }
            return result;
          }

          await engine.addSubtitle(subtitle.path);
          expect(
            white(await pixels()),
            greaterThan(white(hlg) + 20),
            reason: 'HDR mapping does not dim white ASS captions',
          );
          final selectedSubtitle = await native.getProperty('sid');
          await engine.setRenderSettings(
            const VideoRenderSettings(
              toneMappingMode: VideoToneMappingMode.bt2390,
            ),
          );
          expect(white(await pixels()), greaterThan(white(hlg) + 20));
          expect(await native.getProperty('sid'), selectedSubtitle);
          await native.command(['set', 'sub-visibility', 'no']);
          // Removing the HDR metadata restores SDR: selecting a tone curve
          // should not reinterpret ordinary SDR content as HDR.
          await native.command(['vf', 'remove', '@fixture-hdr']);
          await engine.setRenderSettings(
            const VideoRenderSettings(
              toneMappingMode: VideoToneMappingMode.hable,
            ),
          );
          final sdr = await pixels();
          await engine.setRenderSettings(
            const VideoRenderSettings(
              toneMappingMode: VideoToneMappingMode.clip,
            ),
          );
          expect(difference(sdr, await pixels()), lessThan(.5));
        } else {
          expect(
            changes.values.every((v) => v < .01),
            isTrue,
            reason: '$changes',
          );
          await commands.apply(const VideoRenderSettings());
          await expectLater(
            engine.setRenderSettings(
              const VideoRenderSettings(debandMode: VideoDebandMode.light),
            ),
            throwsA(isA<VideoRenderUnavailable>()),
          );
          expect(await commands.current(), const VideoRenderSettings());
        }
        expect(await native.getProperty('pause'), 'yes');
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(position, .02),
        );
        if (gpu) {
          await engine.play();
          await engine.setRenderSettings(const VideoRenderSettings());
          expect(await native.getProperty('pause'), 'no');
          await engine.pause();
        }
        binding.reportData = {...?binding.reportData, 'renderGpu$gpu': changes};
        debugPrint('RENDER_CAPABILITY_GPU_$gpu $changes');
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
          startsWith('reelnest-render-texture-'),
        );
        await sandbox.delete(recursive: true);
      }
    }, skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux);
  }
}
