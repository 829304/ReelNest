import 'dart:convert';
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
import 'package:reelnest/features/playback/domain/video_performance_settings.dart';
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/player/video_performance_settings_engine.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final accelerated in [true, false]) {
    testWidgets(
      'performance settings preserve texture, filters and tracks (GPU=$accelerated)',
      (tester) async {
        MediaKit.ensureInitialized();
        final temporary = await RuntimeStoragePaths.current.temporary();
        final sandbox = await temporary.createTemp(
          'reelnest-performance-texture-',
        );
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
        const key = ValueKey('performance-texture');
        HttpServer? server;
        Future<ByteData> pixels() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 350)),
          );
          await tester.pump();
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(key))
              .toImage(pixelRatio: 1);
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
          } finally {
            image.dispose();
          }
        }

        double difference(ByteData a, ByteData b) {
          var total = 0;
          for (var i = 0; i < a.lengthInBytes; i += 4) {
            for (var c = 0; c < 3; c++) {
              total += (a.getUint8(i + c) - b.getUint8(i + c)).abs();
            }
          }
          return total / (a.lengthInBytes / 4 * 3);
        }

        try {
          final file = await createTrackVideoFixture(
            p.join(sandbox.path, 'sample.mkv'),
            smoothColors: true,
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 320,
                    height: 180,
                    child: engine.surface(),
                  ),
                ),
              ),
            ),
          );
          // Runs before load and after the controller's initial hwdec assignment.
          const initial = VideoPerformanceSettings(
            hardwareDecodingMode: VideoHardwareDecodingMode.off,
            memoryBufferingEnabled: false,
          );
          await engine.setPerformanceSettings(initial);
          final commands = MpvPerformanceCommands(
            command: native.command,
            read: native.getProperty,
          );
          expect(await commands.current(), initial);
          await engine.open(file.path, Duration.zero);
          expect(await commands.current(), initial);
          await engine.seek(const Duration(seconds: 1));
          await engine.selectAudio(2);
          await engine.selectSubtitle(2);
          final burst = List.generate(50, (_) => engine.refreshTracks());
          await engine.selectAudio(1);
          await Future.wait(burst);
          expect(engine.tracks.audioId, 1);
          expect(engine.tracks.subtitleId, 2);
          await engine.selectAudio(2);
          expect(engine.tracks.audioId, 2);
          await engine.setColorAdjustments(
            const VideoColorAdjustments(brightness: 10, gamma: 15),
          );
          await engine.setSharpenMode(VideoSharpenMode.medium);
          await engine.setDisplaySettings(
            const VideoDisplaySettings(flipMode: VideoFlipMode.horizontal),
          );
          final baseline = await pixels();
          final position = double.parse(await native.getProperty('time-pos'));
          final aid = await native.getProperty('aid'),
              sid = await native.getProperty('sid');
          final filters = jsonEncode(readMpvNodeProperty(native, 'vf'));
          final renderer = readMpvNodeProperty(
            native,
            'user-data/reelnest/render-api',
          );
          expect(renderer, accelerated ? 'opengl' : 'sw');
          for (final enabled in [true, false]) {
            for (final mode in VideoHardwareDecodingMode.values) {
              final value = VideoPerformanceSettings(
                hardwareDecodingMode: mode,
                memoryBufferingEnabled: enabled,
              );
              await engine.setPerformanceSettings(value);
              expect(await commands.current(), value);
              expect(engine.performanceSettings, value);
              expect(difference(baseline, await pixels()), lessThan(2));
              expect(await native.getProperty('pause'), 'yes');
              expect(
                double.parse(await native.getProperty('time-pos')),
                closeTo(position, .02),
              );
              expect(await native.getProperty('aid'), aid);
              expect(await native.getProperty('sid'), sid);
              expect(jsonEncode(readMpvNodeProperty(native, 'vf')), filters);
              expect(
                readMpvNodeProperty(native, 'user-data/reelnest/render-api'),
                renderer,
              );
              expect(engine.clock.error, isNull);
            }
          }
          // Loopback Range video exercises an actual HTTP resource without Emby
          // credentials or a claim about throughput on the user's real server.
          var requests = 0;
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests++;
            try {
              final size = await file.length();
              final range = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(
                request.headers.value(HttpHeaders.rangeHeader) ?? '',
              );
              final start = range == null ? 0 : int.parse(range[1]!);
              final end = range == null || range[2]!.isEmpty
                  ? size - 1
                  : int.parse(range[2]!).clamp(0, size - 1);
              request.response.headers.set(
                HttpHeaders.acceptRangesHeader,
                'bytes',
              );
              if (start >= size || end < start) {
                request.response.statusCode =
                    HttpStatus.requestedRangeNotSatisfiable;
                request.response.headers.set(
                  HttpHeaders.contentRangeHeader,
                  'bytes */$size',
                );
              } else {
                request.response.contentLength = end - start + 1;
                if (range != null) {
                  request.response.statusCode = HttpStatus.partialContent;
                  request.response.headers.set(
                    HttpHeaders.contentRangeHeader,
                    'bytes $start-$end/$size',
                  );
                }
                if (request.method != 'HEAD') {
                  await request.response.addStream(
                    file.openRead(start, end + 1),
                  );
                }
              }
              await request.response.close();
            } on HttpException {
              // mpv can abort a read when cancelling/replacing a demuxer request.
            } on SocketException {
              // Expected fixture disconnect while stopping or replacing a stream.
            }
          });
          await engine.setPerformanceSettings(const VideoPerformanceSettings());
          await engine.open(
            'http://127.0.0.1:${server.port}/sample.mkv',
            Duration.zero,
          );
          await pixels();
          expect(requests, greaterThan(0));
          expect(await commands.current(), const VideoPerformanceSettings());
          await engine.play();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)),
          );
          await engine.setPerformanceSettings(initial);
          expect(await commands.current(), initial);
          expect(await native.getProperty('pause'), 'no');
          await engine.pause();
          await engine.setPerformanceSettings(const VideoPerformanceSettings());
          expect(await native.getProperty('pause'), 'yes');
          expect(engine.clock.error, isNull);
          binding.reportData = {
            ...?binding.reportData,
            'performanceTextureGpu$accelerated': true,
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
            startsWith('reelnest-performance-texture-'),
          );
          await sandbox.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux,
    );
  }
}
