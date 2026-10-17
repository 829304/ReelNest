import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final accelerated in [true, false]) {
    testWidgets(
      'paused viewport redraws without a decoder frame (GPU=$accelerated)',
      (tester) async {
        MediaKit.ensureInitialized();
        final temporary = await RuntimeStoragePaths.current.temporary();
        final sandbox = await temporary.createTemp('reelnest-native-viewport-');
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
        final viewport = ValueNotifier(const Size(400, 400));
        Future<void> renderSize(Size expected) async {
          viewport.value = expected;
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (true) {
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            final dimensions = readMpvNodeProperty(native, 'osd-dimensions');
            if (dimensions is Map &&
                dimensions['w'] == expected.width.toInt() &&
                dimensions['h'] == expected.height.toInt()) {
              return;
            }
            if (DateTime.now().isAfter(deadline)) {
              fail('Paused renderer did not adopt $expected: $dimensions');
            }
          }
        }

        try {
          final file = await createTrackVideoFixture(
            p.join(sandbox.path, 'sample.mkv'),
          );
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
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
          );
          await engine.open(file.path, Duration.zero);
          await engine.play();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await engine.pause();
          await renderSize(const Size(400, 400));
          final position = double.parse(await native.getProperty('time-pos'));
          for (final size in [
            const Size(480, 270),
            const Size(300, 450),
            const Size(400, 400),
          ]) {
            await renderSize(size);
            expect(await native.getProperty('pause'), 'yes');
            expect(
              double.parse(await native.getProperty('time-pos')),
              closeTo(position, .02),
            );
          }
          // Closing with a resize still queued must not leave work on a dead player.
          viewport.value = const Size(320, 240);
          await tester.pump();
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
            startsWith('reelnest-native-viewport-'),
          );
          await sandbox.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux,
    );
  }
}
