import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_performance_settings.dart';
import 'package:reelnest/player/video_performance_settings_engine.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test('native performance profiles before load and during paused track playback', () async {
    final temporary = Directory.systemTemp;
    final sandbox = await temporary.createTemp('reelnest-performance-native-');
    try {
      await IOOverrides.runZoned(() async {
        MediaKit.ensureInitialized(libmpv: library);
        final player = Player(
          configuration: const PlayerConfiguration(muted: true),
        );
        final native = player.platform as NativePlayer;
        try {
          await native.setProperty('vid', 'auto');
          await native.setProperty('vo', 'null');
          final commands = MpvPerformanceCommands(
            command: native.command,
            read: native.getProperty,
          );
          const initial = VideoPerformanceSettings(
            hardwareDecodingMode: VideoHardwareDecodingMode.off,
          );
          await commands.apply(initial);
          expect(await commands.current(), initial);
          final file = await createTrackVideoFixture(
            p.join(sandbox.path, 'sample.mkv'),
          );
          await player.open(Media(file.path), play: false);
          final until = DateTime.now().add(const Duration(seconds: 8));
          while (player.state.duration == Duration.zero) {
            if (DateTime.now().isAfter(until)) {
              fail('Native readiness timed out');
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          await native.command(['set', 'aid', '2']);
          await native.command(['set', 'sid', '2']);
          final aid = await native.getProperty('aid'),
              sid = await native.getProperty('sid');
          final position = double.parse(await native.getProperty('time-pos'));
          for (final enabled in [false, true]) {
            for (final mode in VideoHardwareDecodingMode.values) {
              final value = VideoPerformanceSettings(
                hardwareDecodingMode: mode,
                memoryBufferingEnabled: enabled,
              );
              await commands.apply(value);
              expect(await commands.current(), value);
              expect(await native.getProperty('aid'), aid);
              expect(await native.getProperty('sid'), sid);
              expect(await native.getProperty('pause'), 'yes');
              expect(
                double.parse(await native.getProperty('time-pos')),
                closeTo(position, .02),
              );
            }
          }
          // Raw fixture has no hardware decoder: accepting a mode is not proof
          // of GPU decoding, which remains separately reported by hwdec-current.
          expect(await native.getProperty('hwdec-current'), 'no');
        } finally {
          await player.dispose();
        }
      }, getSystemTempDirectory: () => sandbox);
    } finally {
      expect(p.isWithin(temporary.path, sandbox.path), isTrue);
      expect(
        p.basename(sandbox.path),
        startsWith('reelnest-performance-native-'),
      );
      await sandbox.delete(recursive: true);
    }
  }, skip: library.isEmpty);
}
