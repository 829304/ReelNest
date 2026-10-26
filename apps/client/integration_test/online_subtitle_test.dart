import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/data/online_subtitle_service.dart';
import 'package:reelnest/features/playback/data/online_subtitle_store.dart';
import 'package:reelnest/features/playback/domain/online_subtitle.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/color_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final gpu in [true, false]) {
    testWidgets(
      'online download and same-path replacement preserve native playback GPU=$gpu',
      (tester) async {
        MediaKit.ensureInitialized();
        final temporary = await RuntimeStoragePaths.current.temporary();
        await temporary.create(recursive: true);
        final root = await temporary.createTemp('reelnest-online-native-test-');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final base = Uri.parse('http://127.0.0.1:${server.port}/');
        var text = 'FIRST SUBTITLE';
        var fileRequests = 0;
        server.listen((request) async {
          if (request.uri.path == '/api/search/1') {
            request.response.write(
              '<results><subtitle><id>7</id><release>Film</release></subtitle></results>',
            );
          } else if (request.uri.path == '/subtitles/7/download') {
            fileRequests++;
            expect(request.headers.value('Api-Key'), isNull);
            request.response.write('1\n00:00:00,000 --> 00:00:20,000\n$text\n');
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        });
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
        Future<void> waitFor(
          String property,
          bool Function(String) matches,
        ) async {
          for (var n = 0; n < 60; n++) {
            final value = await native.getProperty(property);
            if (matches(value)) return;
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          fail('Native $property did not reach expected state');
        }

        try {
          final video = await createColorVideoFixture(
            p.join(root.path, 'Film.y4m'),
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: engine.surface(),
                ),
              ),
            ),
          );
          await engine.open(video.path, const Duration(seconds: 1));
          await engine.pause();
          await engine.setRate(1.25);
          await waitFor(
            'time-pos',
            (value) => (double.tryParse(value) ?? -1) >= 1,
          );
          final before = <String, String>{};
          for (final property in ['path', 'time-pos', 'pause', 'speed']) {
            before[property] = await native.getProperty(property);
          }
          final service = OnlineSubtitleService(
            podnapisiBase: base,
            allowInsecureForTesting: true,
          );
          final results = await service.search(
            const OnlineSubtitleQuery(title: 'Film'),
            const OnlineSubtitleSettings(),
            ScanCancellation(),
          );
          expect(results.results.length, 1);
          final store = OnlineSubtitleStore();
          final output = p.setExtension(video.path, '.srt');
          for (final caption in ['FIRST SUBTITLE', 'REPLACED SUBTITLE']) {
            text = caption;
            final payload = await service.download(
              results.results.single,
              const OnlineSubtitleSettings(),
              ScanCancellation(),
            );
            await store.save(payload, output, ScanCancellation());
            await engine.addSubtitle(output);
            await waitFor('sub-text', (value) => value.contains(caption));
            expect(await File(output).readAsString(), contains(caption));
            for (final property in before.keys) {
              expect(
                await native.getProperty(property),
                before[property],
                reason: 'Subtitle loading must not change $property',
              );
            }
            expect(
              engine.tracks.subtitles.where((t) => t.external),
              hasLength(1),
            );
          }
          expect(fileRequests, 2);
          debugPrint(
            'online subtitles GPU=$gpu: HTTP download, atomic replacement, native sub-reload and playback invariants passed',
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          await engine.dispose();
          await server.close(force: true);
          expect(p.isWithin(temporary.path, root.path), isTrue);
          expect(
            p.basename(root.path),
            startsWith('reelnest-online-native-test-'),
          );
          await root.delete(recursive: true);
        }
      },
    );
  }
}
