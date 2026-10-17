import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_display_settings.dart';
import 'package:reelnest/player/video_display_settings_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'native display options preserve independent video filter stages',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-display-native-',
      );
      final player = Player(
        configuration: const PlayerConfiguration(muted: true),
      );
      final native = player.platform as NativePlayer;
      try {
        final file = await createTrackVideoFixture(
          p.join(sandbox.path, 'sample.mkv'),
        );
        await native.setProperty('vid', 'auto');
        await native.setProperty('vo', 'null');
        await player.open(Media(file.path), play: false);
        final until = DateTime.now().add(const Duration(seconds: 8));
        while (player.state.duration == Duration.zero) {
          if (DateTime.now().isAfter(until)) {
            fail('Native video readiness timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        Future<String> read(String name) async => name == 'vf'
            ? jsonEncode(readMpvNodeProperty(native, name))
            : native.getProperty(name);
        final commands = MpvDisplaySettingsCommands(
          command: native.command,
          read: read,
        );
        await native.command([
          'vf',
          'add',
          '@fixture-format:format=fmt=yuv420p',
        ]);
        for (final flip in VideoFlipMode.values) {
          await commands.apply(VideoDisplaySettings(flipMode: flip));
          expect(await read('vf'), contains('fixture-format'));
        }
        for (final mode in VideoDeinterlaceMode.values) {
          await commands.apply(VideoDisplaySettings(deinterlaceMode: mode));
          expect(await native.getProperty('deinterlace'), mode.mpvValue);
        }
        expect(await native.getProperty('pause'), 'yes');
      } finally {
        await player.dispose();
        expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-display-native-'),
        );
        await sandbox.delete(recursive: true);
      }
    },
    skip: library.isEmpty,
  );
}
