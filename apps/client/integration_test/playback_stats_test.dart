import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_playback_stats_reader.dart';
import 'package:reelnest/player/video_playback_stats.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'texture playback statistics are read-only across seek and replacement',
    (tester) async {
      MediaKit.ensureInitialized();
      final temp = await RuntimeStoragePaths.current.temporary();
      final sandbox = await temp.createTemp('reelnest-native-stats-');
      final player = Player(
        configuration: const PlayerConfiguration(muted: true, libass: true),
      );
      final engine = MediaKitVideoEngine(player: player);
      final native = player.platform as NativePlayer;
      final sampler = VideoStatsSampler();
      HttpServer? server;
      StreamSubscription<HttpRequest>? requests;
      final transfers = <Future<void>>[];
      try {
        final file = await createTrackVideoFixture(
          p.join(sandbox.path, 'sample.mkv'),
        );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(width: 640, height: 360, child: engine.surface()),
            ),
          ),
        );
        await engine.open(file.path, Duration.zero);
        await engine.play();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 2)),
        );
        await engine.pause();
        final beforePosition = await native.getProperty('time-pos');
        final beforeHwdec = await native.getProperty('hwdec');
        final beforeDelay = await native.getProperty('audio-delay');
        final stats = await engine.readPlaybackStats();
        expect(stats.estimatedFps, greaterThan(0));
        expect(stats.decoderDroppedFrames, isNotNull);
        expect(stats.outputDroppedFrames, isNotNull);
        expect(stats.forwardCacheBytes, isNotNull);
        expect(
          stats.hardwareDecoder,
          'no',
          reason: 'Raw BGR fixture uses software decoding',
        );
        expect(await native.getProperty('pause'), 'yes');
        expect(await native.getProperty('time-pos'), beforePosition);
        expect(await native.getProperty('hwdec'), beforeHwdec);
        expect(await native.getProperty('audio-delay'), beforeDelay);
        await native.setProperty('aid', 'no');
        expect((await engine.readPlaybackStats()).avSyncSeconds, isNull);
        await native.setProperty('aid', 'auto');
        // Only capability booleans go into the test report, not media identifiers
        // or a persisted stream of playback statistics.
        binding.reportData = {
          'textureStatsCapabilities': {
            'estimatedFps': stats.estimatedFps != null,
            'decoderDrops': stats.decoderDroppedFrames != null,
            'outputDrops': stats.outputDroppedFrames != null,
            'hardwareDecoder': stats.hardwareDecoder != null,
            'renderPasses': stats.renderPasses.isNotEmpty,
            'forwardBytes': stats.forwardCacheBytes != null,
            'forwardSeconds': stats.forwardCacheSeconds != null,
            'avSync': stats.avSyncSeconds != null,
          },
        };
        sampler.bind(engine, resourceKey: 'first');
        await tester.pump();
        await engine.seek(const Duration(seconds: 4));
        await engine.play();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await engine.pause();
        expect(await engine.readPlaybackStats(), isA<VideoPlaybackStats>());
        sampler.bind(null);
        expect(sampler.value.estimatedFps, isNull);
        await engine.open(file.path, const Duration(seconds: 1));
        expect(await engine.readPlaybackStats(), isA<VideoPlaybackStats>());
        sampler.bind(engine, resourceKey: 'replacement');
        await tester.pump();
        sampler.bind(null);
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final size = await file.length();
        Future<void> transfer(HttpRequest request) async {
          try {
            final range = RegExp(
              r'^bytes=(\d+)-(\d*)$',
            ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
            final start = range == null ? 0 : int.parse(range[1]!);
            final end = range == null || range[2]!.isEmpty
                ? size - 1
                : int.parse(range[2]!).clamp(0, size - 1);
            if (start >= size || end < start) {
              request.response.statusCode =
                  HttpStatus.requestedRangeNotSatisfiable;
              await request.response.close();
              return;
            }
            request.response.headers.contentType = ContentType(
              'video',
              'x-matroska',
            );
            request.response.headers.set(
              HttpHeaders.acceptRangesHeader,
              'bytes',
            );
            if (range != null) {
              request.response.statusCode = HttpStatus.partialContent;
              request.response.headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes $start-$end/$size',
              );
            }
            request.response.contentLength = end - start + 1;
            if (request.method != 'HEAD') {
              await request.response.addStream(file.openRead(start, end + 1));
            }
            await request.response.close();
          } on IOException {
            // A decoder seek or teardown may close an in-flight test transfer.
          }
        }

        requests = server.listen((request) => transfers.add(transfer(request)));
        await engine.open(
          'http://127.0.0.1:${server.port}/fixture.mkv',
          Duration.zero,
        );
        final online = await engine.readPlaybackStats();
        expect(online.forwardCacheBytes, isNotNull);
        expect(online.forwardCacheSeconds, isNotNull);
        expect(await native.getProperty('pause'), 'yes');
        binding.reportData!['httpForwardCacheAvailable'] =
            online.forwardCacheBytes != null &&
            online.forwardCacheSeconds != null;
        // Native API must tolerate an already disposed player without touching
        // its C handle; a dismissed panel may have a sample pending.
      } finally {
        sampler.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await engine.dispose();
        await server?.close(force: true);
        await requests?.cancel();
        await Future.wait(transfers);
        expect((await readMpvPlaybackStats(native)).estimatedFps, isNull);
        expect(
          p.isWithin(
            await temp.resolveSymbolicLinks(),
            await sandbox.resolveSymbolicLinks(),
          ),
          isTrue,
        );
        expect(p.basename(sandbox.path), startsWith('reelnest-native-stats-'));
        await sandbox.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux,
  );
}
