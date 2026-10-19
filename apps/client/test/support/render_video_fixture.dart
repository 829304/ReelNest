import 'dart:io';
import 'dart:typed_data';

/// Banded 10-bit neutral YUV ramp. HDR transfer/primaries are tagged separately
/// by the integration fixture's mpv format filter, without an encoder dependency.
Future<File> createRenderVideoFixture(String path) async {
  const width = 320, height = 180;
  final frame = ByteData(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      frame.setUint16(
        (y * width + x) * 2,
        64 + (x ~/ 8) * 876 ~/ 39,
        Endian.little,
      );
    }
  }
  for (var at = width * height * 2; at < frame.lengthInBytes; at += 2) {
    frame.setUint16(at, 512, Endian.little);
  }
  final data = BytesBuilder(copy: false)
    ..add('YUV4MPEG2 W$width H$height F4:1 Ip A1:1 C420p10\n'.codeUnits);
  for (var i = 0; i < 96; i++) {
    data.add('FRAME\n'.codeUnits);
    data.add(frame.buffer.asUint8List());
  }
  return File(path).writeAsBytes(data.takeBytes());
}
