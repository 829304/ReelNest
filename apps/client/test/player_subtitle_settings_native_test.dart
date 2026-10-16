import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_subtitle_settings.dart';
import 'package:reelnest/player/video_subtitle_settings_engine.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'real mpv applies style and timing without seek or playback changes',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-native-subtitle-',
      );
      final player = Player(
        configuration: const PlayerConfiguration(muted: true, libass: true),
      );
      final native = player.platform as NativePlayer;
      final commands = MpvSubtitleSettingsCommands(
        command: (args) => native.command(args),
        read: (name) => native.getProperty(name),
      );
      Future<void> waitFor(Future<bool> Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Native subtitle readiness timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }

      try {
        final video = await createTrackVideoFixture(
          p.join(sandbox.path, 'sample.mkv'),
        );
        await native.setProperty('vid', 'auto');
        await player.open(Media(video.path), play: false);
        await waitFor(() async => player.state.duration > Duration.zero);
        final assOverride = await native.getProperty('sub-ass-override');
        await native.setProperty('sid', '1');
        await player.seek(const Duration(milliseconds: 2100));
        await player.play();
        await waitFor(
          () async => (await native.getProperty('sub-text')).isNotEmpty,
        );
        await player.pause();
        final beforePosition = double.parse(
          await native.getProperty('time-pos'),
        );
        final plain = await player.screenshot(
          format: null,
          includeLibassSubtitles: true,
        );
        expect(plain, isNotNull);
        const style = VideoSubtitleStyle(
          fontName: 'Arial',
          bold: true,
          colorPreset: VideoSubtitleColorPreset.yellow,
          borderSize: 5,
          backgroundOpacity: .45,
        );
        await commands.applyStyle(style);
        await commands.apply({
          'audio-delay': .3,
          'sub-delay': -.2,
          'sub-scale': 1.5,
          'sub-pos': 80.0,
        });
        expect(await native.getProperty('sub-font'), 'Arial');
        expect(await native.getProperty('sub-bold'), 'yes');
        expect(await native.getProperty('sub-color'), '#FFF5D547');
        expect(await native.getProperty('sub-back-color'), '#73000000');
        expect(double.parse(await native.getProperty('audio-delay')), .3);
        expect(double.parse(await native.getProperty('sub-delay')), -.2);
        expect(double.parse(await native.getProperty('sub-scale')), 1.5);
        expect(double.parse(await native.getProperty('sub-pos')), 80);
        expect(await native.getProperty('pause'), 'yes');
        expect(
          double.parse(await native.getProperty('time-pos')),
          closeTo(beforePosition, .01),
        );
        expect(await native.getProperty('sub-ass-override'), assOverride);
        final styled = await player.screenshot(
          format: null,
          includeLibassSubtitles: true,
        );
        expect(styled, isNotNull);
        expect(
          listEquals(plain, styled),
          isFalse,
          reason: 'Text styling must change the rendered subtitle frame',
        );
        await commands.applyStyle(VideoSubtitleStyle.standard);
        await commands.apply({
          'audio-delay': 0.0,
          'sub-delay': 0.0,
          'sub-scale': 1.0,
          'sub-pos': 100.0,
        });
        expect(await native.getProperty('sub-font'), 'sans-serif');
        expect(await native.getProperty('sub-bold'), 'no');
        expect(await native.getProperty('sub-color'), '#FFFFFFFF');
        expect(await native.getProperty('sub-back-color'), '#00000000');
        expect(await native.getProperty('pause'), 'yes');
      } finally {
        await player.dispose();
        expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-native-subtitle-'),
        );
        await sandbox.delete(recursive: true);
      }
    },
    skip: library.isEmpty,
    timeout: const Timeout(Duration(seconds: 25)),
  );
}
