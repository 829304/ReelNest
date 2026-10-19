import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_sharpen_mode.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/player/mpv_owned_video_filters.dart';
import 'package:reelnest/player/video_sharpen_engine.dart';

import 'support/color_video_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test('native original unsharp presets and pinned denoise capability', () async {
    final temporary = Directory.systemTemp;
    final sandbox = await temporary.createTemp('reelnest-sharpen-native-');
    try {
      // media_kit debug mode stores native addresses in a PID-named temp file.
      // Give this process a fresh namespace, including when Windows reuses a
      // PID from an earlier test. Do not delete another process's temp files.
      await IOOverrides.runZoned(() async {
        MediaKit.ensureInitialized(libmpv: library);
        final player = Player(
          configuration: const PlayerConfiguration(muted: true),
        );
        final native = player.platform as NativePlayer;
        final messages = <String>[];
        final logs = player.stream.log.listen((e) {
          if (e.text.contains('hqdn3d')) messages.add(e.text);
        });
        try {
          final file = await createColorVideoFixture(
            p.join(sandbox.path, 'sample.y4m'),
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
          final filters = MpvOwnedVideoFilters(
            command: native.command,
            read: (name) async => jsonEncode(readMpvNodeProperty(native, name)),
          );
          final sharpen = MpvSharpenCommands(filters: filters);
          for (final mode in VideoSharpenMode.values) {
            await sharpen.apply(mode);
            expect(await sharpen.current(), mode);
          }
          await sharpen.apply(VideoSharpenMode.off);
          expect(await filters.snapshot(), isEmpty);
          // This probe runs only against the isolated fixture player, never user
          // media. The pinned Windows LGPL archive excludes this GPL-only filter.
          if (Platform.isWindows) {
            try {
              await native.command([
                'vf',
                'add',
                '@fixture-denoise:hqdn3d=2:1.5:3:2.25',
              ]);
            } catch (_) {}
            await Future<void>.delayed(const Duration(milliseconds: 150));
            expect(
              messages.any(
                (m) =>
                    m.contains('No such filter') ||
                    m.contains('not found') ||
                    m.contains("'hqdn3d' isn't supported"),
              ),
              isTrue,
              reason: '$messages',
            );
            if ((readMpvNodeProperty(native, 'vf') as List).any(
              (e) => e['label'] == 'fixture-denoise',
            )) {
              await native.command(['vf', 'remove', '@fixture-denoise']);
            }
          }
          expect(await native.getProperty('pause'), 'yes');
        } finally {
          await logs.cancel();
          await player.dispose();
        }
      }, getSystemTempDirectory: () => sandbox);
    } finally {
      expect(p.isWithin(temporary.path, sandbox.path), isTrue);
      expect(p.basename(sandbox.path), startsWith('reelnest-sharpen-native-'));
      await sandbox.delete(recursive: true);
    }
  }, skip: library.isEmpty);
}
