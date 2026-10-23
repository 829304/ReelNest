import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/data/video_screenshot_store.dart';
import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/features/playback/domain/video_screenshot.dart';
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/color_video_fixture.dart';

typedef _Pixels = ({int width, int height, ByteData rgba});

Future<_Pixels> _pixels(Uint8List png) async {
  VideoScreenshotLimits.png(png);
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    try {
      return (
        width: frame.image.width,
        height: frame.image.height,
        rgba: (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!,
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

double _difference(_Pixels a, _Pixels b) {
  expect((a.width, a.height), (b.width, b.height));
  var total = 0;
  for (var i = 0; i < a.rgba.lengthInBytes; i += 4) {
    for (var c = 0; c < 3; c++) {
      total += (a.rgba.getUint8(i + c) - b.rgba.getUint8(i + c)).abs();
    }
    expect(a.rgba.getUint8(i + 3), 255);
  }
  return total / (a.width * a.height * 3);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final gpu in [true, false]) {
    testWidgets('three screenshot modes preserve native playback (GPU=$gpu)', (
      tester,
    ) async {
      MediaKit.ensureInitialized();
      final temporary = await RuntimeStoragePaths.current.temporary();
      await temporary.create(recursive: true);
      final sandbox = await temporary.createTemp(
        'reelnest-screenshot-texture-',
      );
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
      HttpServer? server;
      const key = ValueKey('screenshot-video-viewport');
      var width = 320.0, height = 240.0;
      Future<void> mount() => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: key,
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  engine.surface(),
                  const Positioned(
                    left: 0,
                    top: 0,
                    width: 20,
                    height: 20,
                    child: ColoredBox(color: Color(0xFFFF00FF)),
                  ), // UI/HUD sentinel excluded.
                ],
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        await tester.pump();
      }

      Future<Uint8List> capture(VideoScreenshotMode mode) async {
        debugPrint('screenshot: begin ${mode.name} GPU=$gpu');
        final future = engine.captureCurrentFrame(mode);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final result = await future;
        debugPrint('screenshot: ready ${mode.name} GPU=$gpu');
        return result;
      }

      try {
        final file = await createColorVideoFixture(
          p.join(sandbox.path, 'sample.y4m'),
        );
        await mount();
        await engine.open(file.path, Duration.zero);
        await engine.play();
        await settle();
        await engine.pause();
        expect(
          readMpvNodeProperty(native, 'user-data/reelnest/render-api'),
          gpu ? 'opengl' : 'sw',
        );
        final sub = File(p.join(sandbox.path, 'white.ass'));
        await sub.writeAsString(r'''[Script Info]
ScriptType: v4.00+
PlayResX: 320
PlayResY: 180
[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,24,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:23.00,Default,,0,0,0,,{\an7\pos(20,140)\1c&HFFFFFF&\bord0\shad0\p1}m 0 0 l 100 0 100 25 0 25
''');
        await engine.addSubtitle(sub.path);
        await settle();
        final before = {
          for (final name in [
            'pause',
            'time-pos',
            'sid',
            'secondary-sid',
            'sub-visibility',
            'hwdec',
            'video-rotate',
            'panscan',
          ])
            name: await native.getProperty(name),
        };
        final without = await _pixels(await capture(VideoScreenshotMode.video));
        final withSubs = await _pixels(
          await capture(VideoScreenshotMode.subtitles),
        );
        expect((without.width, without.height), (160, 90));
        expect(
          _difference(without, withSubs),
          greaterThan(1),
          reason: 'Subtitles and video must remain distinct.',
        );
        final window = await _pixels(await capture(VideoScreenshotMode.window));
        final ratio = View.of(tester.element(find.byKey(key))).devicePixelRatio;
        expect(
          (window.width, window.height),
          ((width * ratio).ceil(), (height * ratio).ceil()),
        );
        expect(window.rgba.getUint8(0), lessThan(8));
        expect(window.rgba.getUint8(1), lessThan(8));
        expect(
          window.rgba.getUint8(2),
          lessThan(8),
          reason: 'Letterbox remains black; magenta UI overlay excluded.',
        );
        for (final name in before.keys) {
          expect(
            await native.getProperty(name),
            before[name],
            reason: 'Capture must not change $name',
          );
        }
        final noSubs = await capture(VideoScreenshotMode.video);
        final store = VideoScreenshotStore(
          directory: () async => Directory(p.join(sandbox.path, 'screenshots')),
        );
        final saved = await store.save('Fixture / Movie', noSubs);
        expect(await File(saved).readAsBytes(), noSubs);
        await engine.selectSubtitle(null);
        await settle();
        expect(
          _difference(
            await _pixels(await capture(VideoScreenshotMode.video)),
            await _pixels(await capture(VideoScreenshotMode.subtitles)),
          ),
          lessThan(.5),
        );

        // Real processing/display options remain intact while capturing. A
        // window PNG follows the viewport even while paused after resize.
        debugPrint('screenshot: apply colors GPU=$gpu');
        await engine.setColorAdjustments(
          const VideoColorAdjustments(brightness: 10, gamma: 15),
        );
        debugPrint('screenshot: apply sharpen GPU=$gpu');
        await engine.setSharpenMode(VideoSharpenMode.medium);
        const display = VideoDisplaySettings(
          rotationMode: VideoRotationMode.clockwise90,
          flipMode: VideoFlipMode.horizontal,
          cropMode: VideoCropMode.balanced,
        );
        debugPrint('screenshot: rotate/crop GPU=$gpu');
        await engine.setDisplaySettings(display);
        debugPrint('screenshot: resize GPU=$gpu');
        width = 240;
        height = 320;
        await mount();
        await settle();
        final filters = jsonEncode(readMpvNodeProperty(native, 'vf'));
        final pausePosition = double.parse(
          await native.getProperty('time-pos'),
        );
        final rotated = await _pixels(
          await capture(VideoScreenshotMode.window),
        );
        expect(
          (rotated.width, rotated.height),
          ((width * ratio).ceil(), (height * ratio).ceil()),
        );
        for (final mode in VideoScreenshotMode.values) {
          VideoScreenshotLimits.png(await capture(mode));
          expect(await native.getProperty('pause'), 'yes');
          expect(
            double.parse(await native.getProperty('time-pos')),
            closeTo(pausePosition, .02),
          );
          expect(jsonEncode(readMpvNodeProperty(native, 'vf')), filters);
          expect(engine.displaySettings, display);
          expect(await native.getProperty('video-rotate'), '90');
        }
        await engine.play();
        final playingBefore = double.parse(
          await native.getProperty('time-pos'),
        );
        for (final mode in VideoScreenshotMode.values) {
          VideoScreenshotLimits.png(await capture(mode));
          expect(engine.clock.playing, isTrue);
          expect(await native.getProperty('pause'), 'no');
        }
        expect(
          double.parse(await native.getProperty('time-pos')),
          greaterThanOrEqualTo(playingBefore),
        );
        await engine.pause();
        // Exercise repeated allocation/retirement after an offscreen capture;
        // this reproduced the Windows stale texture callback crash.
        for (var n = 0; n < 8; n++) {
          await engine.setDisplaySettings(
            VideoDisplaySettings(
              rotationMode: n.isEven
                  ? VideoRotationMode.source
                  : VideoRotationMode.clockwise90,
            ),
          );
          width = n.isEven ? 320 : 240;
          height = n.isEven ? 240 : 320;
          await mount();
          await settle();
          VideoScreenshotLimits.png(await capture(VideoScreenshotMode.window));
        }
        await engine.setDisplaySettings(const VideoDisplaySettings());
        await engine.setColorAdjustments(VideoColorAdjustments.neutral);
        await engine.setSharpenMode(VideoSharpenMode.off);
        width = 320;
        height = 240;
        await mount();
        // A real loopback Range resource exercises the remote media path.
        // Capture reads the existing decoder; it does not open another stream.
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        server.listen((request) async {
          requests++;
          try {
            final length = await file.length();
            final range = RegExp(
              r'^bytes=(\d+)-(\d*)$',
            ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
            final start = range == null ? 0 : int.parse(range[1]!);
            final end = range == null || range[2]!.isEmpty
                ? length - 1
                : int.parse(range[2]!).clamp(start, length - 1);
            request.response.headers.set(
              HttpHeaders.acceptRangesHeader,
              'bytes',
            );
            if (range != null) {
              request.response.statusCode = HttpStatus.partialContent;
              request.response.headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes $start-$end/$length',
              );
            }
            request.response.contentLength = end - start + 1;
            await request.response.addStream(file.openRead(start, end + 1));
          } catch (_) {
            // A decoder may cancel readahead when the fixture closes.
          } finally {
            await request.response.close();
          }
        });
        await engine.open(
          'http://127.0.0.1:${server.port}/sample.y4m',
          Duration.zero,
        );
        await engine.play();
        await settle();
        await engine.pause();
        final beforeCaptureRequests = requests;
        expect(beforeCaptureRequests, greaterThan(0));
        for (final mode in VideoScreenshotMode.values) {
          VideoScreenshotLimits.png(await capture(mode));
        }
        expect(
          requests,
          beforeCaptureRequests,
          reason: 'Screenshots must not create another HTTP media stream.',
        );
        binding.reportData = {
          ...?binding.reportData,
          'screenshotGpu$gpu': true,
        };
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await engine.dispose();
        await server?.close(force: true);
        expect(
          p.isWithin(
            await temporary.resolveSymbolicLinks(),
            await sandbox.resolveSymbolicLinks(),
          ),
          isTrue,
        );
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-screenshot-texture-'),
        );
        await sandbox.delete(recursive: true);
      }
    }, skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux);
  }
}
