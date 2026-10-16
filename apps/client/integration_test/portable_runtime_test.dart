import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows portable native temp and playback stay beside executable',
    (tester) async {
      final paths = RuntimeStoragePaths.current;
      await paths.prepare();
      final temporary = await paths.temporary();
      expect(
        p.equals(
          await Directory.systemTemp.resolveSymbolicLinks(),
          await temporary.resolveSymbolicLinks(),
        ),
        isTrue,
      );
      expect(p.equals(Platform.environment['TMP']!, temporary.path), isTrue);
      MediaKit.ensureInitialized();
      final fixture = await temporary.createTemp('native-portable-check-');
      final oldCwd = Directory.current;
      final player = Player(
        configuration: const PlayerConfiguration(muted: true, libass: true),
      );
      try {
        Directory.current = fixture;
        expect(
          (await RuntimeStoragePaths.current.logs()).path,
          p.join(File(Platform.resolvedExecutable).parent.path, 'log'),
        );
        final video = await createTrackVideoFixture(
          p.join(fixture.path, 'sample.mkv'),
        );
        await player.open(Media(video.path), play: false);
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (player.state.duration == Duration.zero &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        expect(player.state.duration, greaterThan(Duration.zero));
        expect(player.state.playing, isFalse);
      } finally {
        Directory.current = oldCwd;
        await player.dispose();
        expect(
          p.isWithin(
            await temporary.resolveSymbolicLinks(),
            await fixture.resolveSymbolicLinks(),
          ),
          isTrue,
        );
        expect(p.basename(fixture.path), startsWith('native-portable-check-'));
        await fixture.delete(recursive: true);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isWindows,
  );
}
