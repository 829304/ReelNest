import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/player/video_timeline.dart';

import 'support/track_video_fixture.dart';

/// Opt-in real decoder test. No window, user media or Emby credentials needed.
/// Supply the already-built libmpv with --dart-define=REELNEST_MPV_PATH=...
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'real mpv reads embedded chapters, steps frames and performs A–B/whole-file loops',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final sandbox = await Directory.systemTemp.createTemp(
        'reelnest-native-precision-',
      );
      final player = Player(
        configuration: const PlayerConfiguration(muted: true),
      );
      final native = player.platform as NativePlayer;
      final commands = MpvTimelineCommands(
        command: (args) => native.command(args),
        read: (name) => native.getProperty(name),
      );
      Future<void> waitFor(
        String stage,
        Future<bool> Function() condition,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 8));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Native decoder condition timed out: $stage; position=${await native.getProperty('time-pos')}; pause=${await native.getProperty('pause')}; vid=${await native.getProperty('vid')}; duration=${player.state.duration}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      Future<double> position() async =>
          double.tryParse(await native.getProperty('time-pos')) ?? -1;
      try {
        final video = await createTrackVideoFixture(
          p.join(sandbox.path, 'chapters.mkv'),
          withChapters: true,
        );
        // VideoController normally enables this. The headless decoder test
        // intentionally has no Flutter surface, so enable video explicitly.
        await native.setProperty('vid', 'auto');
        await player.open(Media(video.path), play: false);
        await waitFor(
          'duration',
          () async => player.state.duration > Duration.zero,
        );
        final chapters = VideoChapter.decode(
          await native.getProperty('chapter-list'),
        );
        expect(chapters.map((c) => c.title), ['Opening', 'Second chapter']);
        expect(chapters.map((c) => c.time), [
          Duration.zero,
          const Duration(seconds: 8),
        ]);

        await player.seek(const Duration(seconds: 2));
        await waitFor('seek', () async => (await position() - 2).abs() < .3);
        final before = await position();
        await commands.stepFrame(backward: false);
        await waitFor('next frame', () async => await position() > before + .1);
        final after = await position();
        await commands.stepFrame(backward: true);
        await waitFor(
          'previous frame',
          () async => await position() < after - .1,
        );
        expect(await native.getProperty('pause'), 'yes');

        await commands.setABLoop(
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        );
        await player.seek(const Duration(milliseconds: 1750));
        await player.play();
        await waitFor(
          'A–B loop',
          () async => await position() >= 1 && await position() < 1.5,
        );
        expect(player.state.completed, isFalse);
        await player.pause();
        await commands.setABLoop(null, null);

        await commands.setLoopCurrentItem(true);
        await player.seek(const Duration(milliseconds: 23500));
        await waitFor('seek near EOF', () async => await position() > 23);
        await player.play();
        await waitFor(
          'whole-file loop',
          () async => await position() >= 0 && await position() < 2,
        );
        expect(player.state.completed, isFalse);
        await commands.setLoopCurrentItem(false);
      } finally {
        await player.dispose();
        expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-native-precision-'),
        );
        await sandbox.delete(recursive: true);
      }
    },
    skip: library.isEmpty
        ? 'Set REELNEST_MPV_PATH to run real decoder checks'
        : false,
  );
}
