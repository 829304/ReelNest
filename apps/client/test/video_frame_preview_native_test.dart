import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_frame_preview.dart';
import 'package:reelnest/player/mpv_video_frame_preview.dart';

import 'support/track_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test(
    'separate native decoder returns bounded PNG without moving main player',
    () async {
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp(
        'reelnest-preview-native-',
      );
      final file = await createTrackVideoFixture(
        p.join(directory.path, 'Film.mkv'),
      );
      final main = Player(
        configuration: const PlayerConfiguration(muted: true),
      );
      try {
        await (main.platform as NativePlayer).setProperty('vid', 'auto');
        await main.open(
          Media(file.path, start: const Duration(seconds: 5)),
          play: false,
        );
        await main.setVolume(42);
        final loaded = DateTime.now().add(const Duration(seconds: 5));
        while (main.state.position < const Duration(milliseconds: 4500)) {
          if (DateTime.now().isAfter(loaded)) {
            fail('Main fixture did not finish loading');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final before = main.state.position;
        final resource = VideoPreviewResource(
          identity: (sourceId: 'native', localId: 'Film.mkv'),
          location: file.path,
        );
        final bytes = await generateMpvVideoPreview(
          resource,
          const Duration(seconds: 12),
          VideoPreviewCancellation(),
        );
        expect(bytes, isNotNull);
        expect(bytes!.length, lessThan(1024 * 1024));
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 312);
        expect(image.height, 176);
        image.dispose();
        codec.dispose();
        expect(main.state.playing, isFalse);
        expect(main.state.volume, 42);
        expect(
          (main.state.position - before).abs(),
          lessThan(const Duration(milliseconds: 500)),
        );
        final cancelled = VideoPreviewCancellation()..cancel();
        expect(
          await generateMpvVideoPreview(resource, Duration.zero, cancelled),
          isNull,
        );
      } finally {
        await main.dispose();
        expect(p.isWithin(Directory.systemTemp.path, directory.path), isTrue);
        expect(
          p.basename(directory.path),
          startsWith('reelnest-preview-native-'),
        );
        await directory.delete(recursive: true);
      }
    },
    skip: library.isEmpty ? 'Set REELNEST_MPV_PATH for native checks' : false,
  );
}
