import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/player/video_network_speed.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'consecutive mpv players report incoming HTTP bytes through cache-speed',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-native-speed-',
      );
      final sample = await createTrackVideoFixture(
        p.join(sandbox.path, 'sample.mkv'),
      );
      final bytes = await sample.readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var stopped = false;
      final transfers = <Future<void>>[];
      Future<void> transfer(HttpRequest request) async {
        try {
          request.response.headers.contentType = ContentType(
            'video',
            'x-matroska',
          );
          request.response.contentLength = bytes.length;
          for (
            var start = 0;
            start < bytes.length && !stopped;
            start += 65536
          ) {
            request.response.add(
              bytes.sublist(start, (start + 65536).clamp(0, bytes.length)),
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 35));
          }
          await request.response.close();
        } on IOException {
          // Test decoder/HTTP teardown may close a response before its last chunk.
        }
      }

      final requests = server.listen((r) {
        transfers.add(transfer(r));
      });
      try {
        for (var instance = 0; instance < 2; instance++) {
          final player = Player(
            configuration: const PlayerConfiguration(
              muted: true,
              logLevel: MPVLogLevel.warn,
            ),
          );
          final native = player.platform as NativePlayer;
          final samples = <int>[];
          try {
            await native.observeProperty('cache-speed', (raw) async {
              final rate = parseVideoNetworkSpeed(raw);
              if (rate != null) samples.add(rate);
            });
            await player.open(
              Media('http://127.0.0.1:${server.port}/sample.mkv'),
              play: false,
            );
            final deadline = DateTime.now().add(const Duration(seconds: 7));
            while (!samples.any((rate) => rate > 0) &&
                DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            expect(
              samples.any((rate) => rate > 0),
              isTrue,
              reason: 'HTTP byte input must be measured rather than inferred from media bitrate',
            );
            expect(player.state.playing, isFalse);
            await native.unobserveProperty('cache-speed');
          } finally {
            await player.dispose();
          }
        }
      } finally {
        stopped = true;
        await server.close(force: true);
        await requests.cancel();
        await Future.wait(transfers);
        expect(
          p.isWithin(
            await Directory.systemTemp.resolveSymbolicLinks(),
            await sandbox.resolveSymbolicLinks(),
          ),
          isTrue,
        );
        expect(p.basename(sandbox.path), startsWith('reelnest-native-speed-'));
        await sandbox.delete(recursive: true);
      }
    },
    skip: library.isEmpty,
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
