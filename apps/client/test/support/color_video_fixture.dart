import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

/// Generated YUV420 test video: color bars with luma/chroma gradients. Unlike
/// raw RGB fixtures, YUV exercises mpv's original hue/saturation conversion.
Future<File> createColorVideoFixture(
  String path, {
  bool wideGamut = false,
  bool detail = false,
  int width = 160,
  int height = 90,
}) async {
  final frame = Uint8List(width * height * 3 ~/ 2);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      frame[y * width + x] = detail
          ? (128 +
                    25 * math.sin(x * math.pi / 4) +
                    25 * math.cos(y * math.pi / 5))
                .round()
          : wideGamut
          ? 40 + (x * 140 ~/ width)
          : 95 + (x * 70 ~/ width);
    }
  }
  final chromaSize = width * height ~/ 4;
  for (var y = 0; y < height ~/ 2; y++) {
    for (var x = 0; x < width ~/ 2; x++) {
      final at = y * (width ~/ 2) + x;
      frame[width * height + at] = detail
          ? 128
          : wideGamut
          ? 65 + (y * 120 ~/ (height ~/ 2))
          : 100 + (y * 55 ~/ (height ~/ 2));
      frame[width * height + chromaSize + at] = detail
          ? 128
          : wideGamut
          ? 65 + (x * 120 ~/ (width ~/ 2))
          : 100 + (x * 55 ~/ (width ~/ 2));
    }
  }
  final data = BytesBuilder(copy: false)
    ..add('YUV4MPEG2 W$width H$height F4:1 Ip A1:1 C420jpeg\n'.codeUnits);
  for (var i = 0; i < 96; i++) {
    data.add('FRAME\n'.codeUnits);
    data.add(frame);
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(data.takeBytes());
}
