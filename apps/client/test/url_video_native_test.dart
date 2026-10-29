import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';
import 'package:reelnest/player/mpv_video_frame_preview.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test('cancelling native URL cover aborts a stalled HTTP load', () async {
    MediaKit.ensureInitialized(libmpv: library);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final entered = Completer<void>();
    server.listen((request) {
      if (!entered.isCompleted) entered.complete();
    });
    final token = VideoPreviewCancellation();
    try {
      final work = generateMpvVideoPreview(
        VideoPreviewResource(
          identity: (sourceId: 'url-fixture', localId: 'stall'),
          location: 'http://127.0.0.1:${server.port}/stall',
        ),
        Duration.zero,
        token,
        coverRatio: .2,
      );
      await entered.future.timeout(const Duration(seconds: 3));
      token.cancel();
      expect(await work.timeout(const Duration(seconds: 2)), isNull);
    } finally {
      token.cancel();
      await server.close(force: true);
    }
  }, skip: library.isEmpty ? 'Set REELNEST_MPV_PATH for native checks' : false);
  test(
    'native URL cover decodes extensionless HTTP at proportional sample',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp(
        'reelnest-url-native-',
      );
      final file = await createTrackVideoFixture(
        p.join(directory.path, 'Film.mkv'),
      );
      final length = await file.length();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        try {
          var start = 0, end = length - 1;
          final range = request.headers.value(HttpHeaders.rangeHeader);
          if (range != null) {
            final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range)!;
            start = int.parse(match[1]!);
            end = match[2]!.isEmpty
                ? end
                : int.parse(match[2]!).clamp(start, end);
            request.response.statusCode = 206;
            request.response.headers.set(
              'Content-Range',
              'bytes $start-$end/$length',
            );
          }
          request.response.headers.set('Content-Type', 'video/x-matroska');
          request.response.headers.set('Accept-Ranges', 'bytes');
          request.response.contentLength = end - start + 1;
          if (request.method != 'HEAD') {
            await request.response.addStream(file.openRead(start, end + 1));
          }
          await request.response.close();
        } catch (_) {
          try {
            await request.response.close();
          } catch (_) {}
        }
      });
      try {
        final resource = VideoPreviewResource(
          identity: (sourceId: 'url-fixture', localId: 'opaque'),
          location: 'http://127.0.0.1:${server.port}/opaque?token=fixture',
        );
        final frame = await generateMpvVideoPreview(
          resource,
          Duration.zero,
          VideoPreviewCancellation(),
          coverRatio: .2,
        );
        expect(frame, isNotNull);
        expect(frame!.length, lessThan(1024 * 1024));
        expect(frame.take(4), [137, 80, 78, 71]);
        final codec = await ui.instantiateImageCodec(frame);
        final image = (await codec.getNextFrame()).image;
        expect((image.width, image.height), (160, 90));
        image.dispose();
        codec.dispose();
      } finally {
        await server.close(force: true);
        expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
        expect(p.basename(directory.path), startsWith('reelnest-url-native-'));
        await directory.delete(recursive: true);
      }
    },
    skip: library.isEmpty ? 'Set REELNEST_MPV_PATH for native checks' : false,
  );
}
