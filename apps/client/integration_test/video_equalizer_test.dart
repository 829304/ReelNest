import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_equalizer_settings.dart';
import 'package:reelnest/player/media_kit_video_engine.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/player/video_equalizer_engine.dart';
import 'package:reelnest/storage/runtime_storage_paths.dart';

import '../test/support/track_video_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final accelerated in [true, false]) {
    testWidgets(
      'video equalizer preserves native playback pipeline (GPU=$accelerated)',
      (tester) async {
        MediaKit.ensureInitialized();
        final temporary = await RuntimeStoragePaths.current.temporary();
        final sandbox = await temporary.createTemp(
          'reelnest-equalizer-texture-',
        );
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
        HttpServer? server;
        var requests = 0;
        Future<void> settle() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pump();
        }

        Future<Map<String, String>> state() async => {
          for (final key in [
            'speed',
            'audio-pitch-correction',
            'volume',
            'audio-delay',
            'audio-device',
            'aid',
            'sid',
            'secondary-sid',
            'sub-visibility',
            'hwdec',
          ])
            key: await native.getProperty(key),
          'vf': jsonEncode(readMpvNodeProperty(native, 'vf')),
        };
        List<dynamic> af() => readMpvNodeProperty(native, 'af') as List;
        Future<void> exercise() async {
          debugPrint('equalizer: prepare controls GPU=$accelerated');
          await engine.play();
          await settle();
          await engine.pause();
          await engine.setRate(1.25);
          await engine.setPitchCorrection(false);
          await engine.setAudioDelay(.25);
          await engine.setVolume(67);
          await engine.setVolumeBoost(1.5);
          await engine.selectAudio(engine.tracks.audio.last.id);
          await native.command([
            'af',
            'add',
            '@fixture-audio:volume=volume=0.75',
          ]);
          await settle();
          final before = await state();
          final foreign = af().singleWhere(
            (e) => e['label'] == 'fixture-audio',
          );
          final at = double.parse(await native.getProperty('time-pos'));
          for (final preset in VideoEqualizerPreset.values) {
            debugPrint('equalizer: ${preset.name} GPU=$accelerated');
            final value = VideoEqualizerSettings(enabled: true, preset: preset);
            await engine.setEqualizerSettings(value);
            expect(engine.equalizerSettings, value);
            expect(await state(), before);
            expect(
              af().singleWhere((e) => e['label'] == 'fixture-audio'),
              foreign,
            );
            final owned = af().where(
              (e) => e['label'] == MpvEqualizerCommands.label,
            );
            expect(owned.length, preset == VideoEqualizerPreset.flat ? 0 : 1);
            if (owned.isNotEmpty) {
              expect(owned.single['params']['graph'], value.filterGraph);
            }
            expect(await native.getProperty('pause'), 'yes');
            expect(
              double.parse(await native.getProperty('time-pos')),
              closeTo(at, .02),
            );
          }
          const rock = VideoEqualizerSettings(
            enabled: true,
            preset: VideoEqualizerPreset.rock,
          );
          await engine.setEqualizerSettings(rock.copyWith(enabled: false));
          expect(af(), [foreign]);
          expect(engine.equalizerSettings.preset, VideoEqualizerPreset.rock);
          final beforeRequests = requests;
          await engine.play();
          await engine.setEqualizerSettings(rock);
          await engine.setPitchCorrection(true);
          await engine.setRate(1.5);
          await settle();
          expect(engine.clock.playing, isTrue);
          expect(engine.clock.error, isNull);
          expect((await state())['audio-pitch-correction'], 'yes');
          expect(
            af().where((e) => e['label'] == MpvEqualizerCommands.label),
            hasLength(1),
          );
          // This small HTTP fixture is fully buffered already. Filter changes
          // must not reopen the media or create another decoder/request.
          if (server != null) expect(requests, beforeRequests);
          await engine.pause();
          await engine.setEqualizerSettings(const VideoEqualizerSettings());
          expect(af(), [foreign]);
          await native.command(['af', 'remove', '@fixture-audio']);
        }

        try {
          final file = await createTrackVideoFixture(
            p.join(sandbox.path, 'sample.mkv'),
          );
          debugPrint('equalizer: mount GPU=$accelerated');
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
          await native.setProperty('options/ao', 'null');
          debugPrint('equalizer: open local GPU=$accelerated');
          await engine.open(file.path, Duration.zero);
          await exercise();
          final bytes = await file.readAsBytes();
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            requests++;
            final range = request.headers.value(HttpHeaders.rangeHeader);
            final match = range == null
                ? null
                : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
            final start = match == null ? 0 : int.parse(match[1]!);
            final end = match == null || match[2]!.isEmpty
                ? bytes.length - 1
                : int.parse(match[2]!).clamp(0, bytes.length - 1);
            request.response.headers.set(
              HttpHeaders.acceptRangesHeader,
              'bytes',
            );
            request.response.headers.contentType = ContentType(
              'video',
              'x-matroska',
            );
            if (start < 0 || start >= bytes.length || end < start) {
              request.response.statusCode =
                  HttpStatus.requestedRangeNotSatisfiable;
              request.response.headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes */${bytes.length}',
              );
            } else {
              if (match != null) {
                request.response.statusCode = HttpStatus.partialContent;
                request.response.headers.set(
                  HttpHeaders.contentRangeHeader,
                  'bytes $start-$end/${bytes.length}',
                );
              }
              request.response.contentLength = end - start + 1;
              request.response.add(bytes.sublist(start, end + 1));
            }
            await request.response.close();
          });
          debugPrint('equalizer: open HTTP GPU=$accelerated');
          await engine.open(
            'http://127.0.0.1:${server.port}/sample.mkv',
            Duration.zero,
          );
          await exercise();
          binding.reportData = {
            ...?binding.reportData,
            'equalizerGpu$accelerated': true,
          };
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await engine.dispose();
          await server?.close(force: true);
          expect(
            p.isWithin(
              await temporary.resolveSymbolicLinks(),
              await sandbox.resolveSymbolicLinks(),
            ),
            isTrue,
          );
          expect(
            p.basename(sandbox.path),
            startsWith('reelnest-equalizer-texture-'),
          );
          await sandbox.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux,
    );
  }
}
