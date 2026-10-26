import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/platform/external_player_gateway.dart';

void main() {
  const executable = String.fromEnvironment('EXTERNAL_PLAYER_PROBE_PATH');
  test(
    'Windows custom player receives one exact Unicode argument and detects immediate failure',
    () async {
      final gateway = DesktopExternalPlayerGateway();
      final root = p.dirname(executable);
      final capture = File(p.join(root, 'capture.bin'));
      final sandbox = await Directory(root)
          .createTemp('reelnest-launch-fixture-');
      List<String> decode(Uint8List bytes) {
        final data = ByteData.sublistView(bytes);
        var offset = 0;
        int number() {
          final value = data.getUint32(offset, Endian.little);
          offset += 4;
          return value;
        }

        final count = number();
        final result = <String>[];
        for (var i = 0; i < count; i++) {
          final length = number();
          final units = <int>[];
          for (var j = 0; j < length; j++) {
            units.add(data.getUint16(offset, Endian.little));
            offset += 2;
          }
          result.add(String.fromCharCodes(units));
        }
        return result;
      }

      try {
        final video = await File(p.join(sandbox.path, '电影 file & name.mkv'))
            .writeAsString('fixture');
        await gateway.launch(video.path, applicationPath: executable);
        expect(decode(await capture.readAsBytes()), [video.path]);
        const location =
            'https://example.invalid/电影.mp4?token=fixture&name=a%20b&quote=%22';
        await gateway.launch(location, applicationPath: executable);
        expect(decode(await capture.readAsBytes()), [location]);
        final failed = await File(p.join(sandbox.path, 'fail.mp4'))
            .writeAsString('fixture');
        await expectLater(
          gateway.launch(failed.path, applicationPath: executable),
          throwsA(isA<SourceFailure>()),
        );
        await expectLater(
          gateway.validateApplication(Platform.resolvedExecutable),
          throwsA(isA<SourceFailure>()),
        );
      } finally {
        expect(p.isWithin(root, sandbox.path), isTrue);
        expect(
          p.basename(sandbox.path),
          startsWith('reelnest-launch-fixture-'),
        );
        await sandbox.delete(recursive: true);
        if (await capture.exists()) await capture.delete();
      }
    },
    skip: !Platform.isWindows || executable.isEmpty
        ? 'Set EXTERNAL_PLAYER_PROBE_PATH for native launch verification'
        : false,
  );
}
