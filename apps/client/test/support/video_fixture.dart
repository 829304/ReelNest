import 'dart:io';
import 'dart:typed_data';

/// Small valid, uncompressed AVI: moving RGB bars, 160x90, 4fps, 24 seconds.
/// Generated locally, no downloaded media or actual library is needed.
Future<File> createVideoFixture(String path) async {
  const width = 160, height = 90, fps = 4, frames = 96;
  const frameSize = width * height * 3;
  Uint8List integers(List<int> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setUint32(i * 4, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  List<int> chunk(String tag, List<int> body) => [
    ...tag.codeUnits,
    ...integers([body.length]),
    ...body,
    if (body.length.isOdd) 0,
  ];
  List<int> list(String tag, List<int> body) =>
      chunk('LIST', [...tag.codeUnits, ...body]);
  final avih = chunk(
    'avih',
    integers([
      1000000 ~/ fps,
      frameSize * fps,
      0,
      0,
      frames,
      0,
      1,
      frameSize,
      width,
      height,
      0,
      0,
      0,
      0,
    ]),
  );
  final strh = chunk('strh', [
    ...'vidsDIB '.codeUnits,
    ...integers([0, 0, 0, 1, fps, 0, frames, frameSize, 0xffffffff, 0]),
    0,
    0,
    0,
    0,
    width,
    0,
    height,
    0,
  ]);
  final format = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setUint32(4, width, Endian.little)
    ..setUint32(8, height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little)
    ..setUint32(20, frameSize, Endian.little);
  final header = list('hdrl', [
    ...avih,
    ...list('strl', [...strh, ...chunk('strf', format.buffer.asUint8List())]),
  ]);
  final movie = BytesBuilder(copy: false);
  for (var frame = 0; frame < frames; frame++) {
    final pixels = Uint8List(frameSize);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final offset = (y * width + x) * 3;
        pixels[offset] = (x * 2 + frame * 5) % 256;
        pixels[offset + 1] = (y * 2 + frame * 2) % 256;
        pixels[offset + 2] = (frame * 7) % 256;
      }
    }
    movie.add(chunk('00db', pixels));
  }
  final body = [
    ...'AVI '.codeUnits,
    ...header,
    ...list('movi', movie.takeBytes()),
  ];
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(chunk('RIFF', body));
}
