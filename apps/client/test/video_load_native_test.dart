import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/player/playback_diagnostics.dart';
import 'package:reelnest/player/video_load_monitor.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'real mpv readiness uses native video parameters and classifies a failed HTTP load',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-native-load-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        request.response.statusCode = 503;
        await request.response.close();
      });
      final player = Player(
        configuration: const PlayerConfiguration(
          muted: true,
          logLevel: MPVLogLevel.warn,
        ),
      );
      final native = player.platform as NativePlayer;
      PlaybackIssue? issue;
      final errors = player.stream.error.listen((text) {
        issue = PlaybackIssue.prefer(issue, PlaybackIssue.backend(text));
      });
      final logs = player.stream.log.listen((entry) {
        final classified = PlaybackIssue.backend(entry.text);
        if (classified.code == 'http') {
          issue = PlaybackIssue.prefer(issue, classified);
        }
      });
      Future<VideoLoadSnapshot> read({bool omitDuration = false}) =>
          readVideoLoadSnapshot(
            property: native.getProperty,
            duration: () =>
                omitDuration ? Duration.zero : player.state.duration,
            checkAlive: () {},
          );
      try {
        final file = await createTrackVideoFixture(
          p.join(sandbox.path, 'sample.mkv'),
        );
        await native.setProperty('vid', 'auto');
        await player.open(Media(file.path), play: false);
        await VideoLoadMonitor(timeout: const Duration(seconds: 5)).wait(
          // Force the duration-free branch while using actual decoder properties.
          read: () => read(omitDuration: true),
          backendIssue: () => issue,
        );
        expect(player.state.playing, isFalse);
        expect((await read(omitDuration: true)).hasVideo, isTrue);
        await player.stop();
        issue = null;
        await player.open(
          Media('http://127.0.0.1:${server.port}/unavailable'),
          play: false,
        );
        await expectLater(
          VideoLoadMonitor(timeout: const Duration(seconds: 5))
              .wait(read: read, backendIssue: () => issue),
          throwsA(isA<PlaybackIssue>()),
        );
        expect(issue, isNotNull);
        expect(issue!.status, 503);
      } finally {
        await errors.cancel();
        await logs.cancel();
        await player.dispose();
        await requests.cancel();
        await server.close(force: true);
        await sandbox.delete(recursive: true);
      }
    },
    skip: library.isEmpty,
    timeout: const Timeout(Duration(seconds: 25)),
  );
}
