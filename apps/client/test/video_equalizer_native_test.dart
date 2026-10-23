import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/features/playback/domain/video_equalizer_settings.dart';
import 'package:reelnest/player/mpv_node_property.dart';
import 'package:reelnest/player/video_equalizer_engine.dart';

Future<File> _tones(String path) async {
  const frames = 96000, rate = 48000;
  final data = ByteData(44 + frames * 2);
  void text(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    final v = VideoEqualizerPreset.frequencies.fold<double>(
      0,
      (sum, f) => sum + .025 * math.sin(2 * math.pi * f * i / rate),
    );
    data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return File(path).writeAsBytes(data.buffer.asUint8List());
}

List<double> _amplitudes(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 12, channels = 0, rate = 0, bits = 0, kind = 0;
  Uint8List? samples;
  while (offset + 8 <= bytes.length) {
    final key = ascii.decode(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final at = offset + 8;
    if (key == 'fmt ') {
      kind = data.getUint16(at, Endian.little);
      channels = data.getUint16(at + 2, Endian.little);
      rate = data.getUint32(at + 4, Endian.little);
      bits = data.getUint16(at + 14, Endian.little);
      if (kind == 0xfffe) kind = data.getUint16(at + 24, Endian.little);
    } else if (key == 'data') {
      samples = Uint8List.sublistView(
        bytes,
        at,
        math.min(at + size, bytes.length),
      );
      break;
    }
    offset = at + size + size % 2;
  }
  expect(channels, 1);
  expect(rate, 48000);
  expect(kind, 1);
  expect(bits, 16);
  final pcm = ByteData.sublistView(samples!);
  final start = rate ~/ 2,
      count = math.min(rate, pcm.lengthInBytes ~/ 2 - start);
  expect(count, greaterThan(24000));
  return [
    for (final f in VideoEqualizerPreset.frequencies)
      (() {
        var sin = 0.0, cos = 0.0;
        for (var i = 0; i < count; i++) {
          final v = pcm.getInt16((start + i) * 2, Endian.little) / 32768;
          final phase = 2 * math.pi * f * i / rate;
          sin += v * math.sin(phase);
          cos += v * math.cos(phase);
        }
        return 2 * math.sqrt(sin * sin + cos * cos) / count;
      })(),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const library = String.fromEnvironment('REELNEST_MPV_PATH');
  test('original firequalizer presets change actual PCM at all five bands', () async {
    final temporary = Directory.systemTemp;
    final sandbox = await temporary.createTemp('reelnest-equalizer-native-');
    try {
      await IOOverrides.runZoned(() async {
        MediaKit.ensureInitialized(libmpv: library);
        final input = await _tones(p.join(sandbox.path, 'tones.wav'));
        Future<List<double>> render(VideoEqualizerPreset preset) async {
          final output = File(p.join(sandbox.path, '${preset.name}.wav'));
          final player = Player(
            configuration: const PlayerConfiguration(muted: false),
          );
          final native = player.platform as NativePlayer;
          try {
            await native.setProperty('options/ao', 'pcm');
            await native.setProperty('options/ao-pcm-file', output.path);
            await native.setProperty('options/audio-format', 's16');
            await native.setProperty('options/audio-channels', 'mono');
            await player.setVolume(100);
            final commands = MpvEqualizerCommands(
              command: native.command,
              read: (name) async =>
                  jsonEncode(readMpvNodeProperty(native, name)),
            );
            final value = VideoEqualizerSettings(enabled: true, preset: preset);
            await commands.apply(value);
            expect(await commands.actual(value), value);
            await player.open(Media(input.path));
            final until = DateTime.now().add(const Duration(seconds: 10));
            while (!player.state.completed) {
              if (DateTime.now().isAfter(until)) {
                fail('PCM render timed out: $preset');
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
          } finally {
            await player.dispose();
          }
          return _amplitudes(await output.readAsBytes());
        }

        final baseline = await render(VideoEqualizerPreset.flat);
        for (final preset in VideoEqualizerPreset.values.skip(1)) {
          final actual = await render(preset);
          for (var i = 0; i < 5; i++) {
            final db = 20 * math.log(actual[i] / baseline[i]) / math.ln10;
            expect(
              db,
              closeTo(preset.gainsDB[i], .8),
              reason:
                  '${preset.name} ${VideoEqualizerPreset.frequencies[i]}Hz: $db dB',
            );
          }
        }
      }, getSystemTempDirectory: () => sandbox);
    } finally {
      expect(p.isWithin(temporary.path, sandbox.path), isTrue);
      expect(
        p.basename(sandbox.path),
        startsWith('reelnest-equalizer-native-'),
      );
      await sandbox.delete(recursive: true);
    }
  }, skip: library.isEmpty);
}
