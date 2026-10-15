import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';
import 'package:reelnest/player/mpv_video_frame_preview.dart';

void main() {
  test(
    'range bridge clamps requests and keeps auth only on upstream',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      final paths = <Uri>[];
      final ranges = <String?>[];
      server.listen((request) async {
        paths.add(request.uri);
        ranges.add(request.headers.value('Range'));
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', 'bytes 4-11/100');
        request.response.contentLength = 8;
        request.response.add(List.generate(8, (i) => i + 4));
        await request.response.close();
      });
      final proxy = await BoundedVideoPreviewProxy.open(
        Uri.parse('http://127.0.0.1:${server.port}/stream.mkv?api_key=secret'),
        VideoPreviewCancellation(),
        maxRangeBytes: 8,
        maxTotalBytes: 16,
      );
      addTearDown(() async {
        client.close(force: true);
        await proxy.close();
        await server.close(force: true);
      });
      final request = await client.getUrl(proxy.uri)
        ..headers.set('Range', 'bytes=4-99');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(await response.expand((chunk) => chunk).toList(), [
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
      ]);
      expect(ranges, ['bytes=4-11']);
      expect(paths.single.queryParameters['api_key'], 'secret');
      expect(proxy.uri.toString(), isNot(contains('secret')));
      expect(proxy.receivedBytes, 8);
      final wrong = await client.getUrl(proxy.uri.replace(path: '/wrong'));
      final rejected = await wrong.close();
      await rejected.drain<void>();
      expect(rejected.statusCode, 404);
      expect(paths.length, 1);
    },
  );

  for (final status in [200, 302, 206]) {
    test(
      'rejects ignored ranges, redirects and mismatched content range ($status)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = HttpClient();
        server.listen((request) async {
          request.response.statusCode = status;
          if (status == 302) {
            request.response.headers.set(
              'Location',
              'http://example.invalid/secret',
            );
          }
          if (status == 206) {
            request.response.headers.set('Content-Range', 'bytes 1-7/100');
          }
          request.response.add(List.filled(1024, 42));
          await request.response.close();
        });
        final proxy = await BoundedVideoPreviewProxy.open(
          Uri.parse('http://127.0.0.1:${server.port}/stream.mkv'),
          VideoPreviewCancellation(),
          maxRangeBytes: 8,
        );
        addTearDown(() async {
          client.close(force: true);
          await proxy.close();
          await server.close(force: true);
        });
        final response = await (await client.getUrl(proxy.uri)).close();
        expect(response.statusCode, 502);
        await response.drain<void>();
        expect(proxy.receivedBytes, 0);
      },
    );
  }

  test(
    'actual chunked bytes are bounded even with no Content-Length',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      var written = 0;
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.statusCode = 206;
        request.response.headers.set('Content-Range', 'bytes 0-7/10000');
        try {
          for (var i = 0; i < 100; i++) {
            request.response.add(List.filled(65536, 42));
            written++;
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
        } catch (_) {
          /* Expected upstream disconnect. */
        }
        try {
          await request.response.close();
        } catch (_) {}
      });
      final proxy = await BoundedVideoPreviewProxy.open(
        Uri.parse('http://127.0.0.1:${server.port}/stream.mkv'),
        VideoPreviewCancellation(),
        maxRangeBytes: 8,
        maxTotalBytes: 16,
      );
      addTearDown(() async {
        client.close(force: true);
        await proxy.close();
        await server.close(force: true);
      });
      try {
        final response = await (await client.getUrl(proxy.uri)).close();
        await response.drain<void>();
      } catch (_) {
        /* Bridge closes a lying stream immediately. */
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(written, lessThan(100));
      expect(proxy.receivedBytes, lessThanOrEqualTo(16));
    },
  );

  test(
    'cancellation interrupts stalled headers and closes loopback listener',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      final reached = Completer<void>();
      server.listen((request) {
        reached.complete();
      });
      final cancellation = VideoPreviewCancellation();
      final proxy = await BoundedVideoPreviewProxy.open(
        Uri.parse('http://127.0.0.1:${server.port}/stream.mkv'),
        cancellation,
      );
      addTearDown(() async {
        client.close(force: true);
        await proxy.close();
        await server.close(force: true);
      });
      final response = (await client.getUrl(proxy.uri))
          .close()
          .then((r) => r.drain<void>())
          .catchError((Object _) {});
      await reached.future.timeout(const Duration(seconds: 2));
      cancellation.cancel();
      await response.timeout(const Duration(seconds: 2));
      expect(proxy.receivedBytes, 0);
      expect(
        () async => (await client.getUrl(proxy.uri)).close(),
        throwsA(isA<SocketException>()),
      );
    },
  );
}
