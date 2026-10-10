import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal Matroska: 24s raw BGR video, two silent PCM audio streams and two
/// UTF-8 subtitle streams. No network, copyrighted media or FFmpeg dependency.
Future<File> createTrackVideoFixture(String path) async {
  List<int> number(int value) {
    final bytes = <int>[];
    do {
      bytes.insert(0, value & 255);
      value >>= 8;
    } while (value > 0);
    return bytes;
  }

  List<int> length(int value) {
    var width = 1;
    while (value >= (1 << (7 * width)) - 1) {
      width++;
    }
    final bytes = List<int>.generate(
      width,
      (i) => (value >> ((width - i - 1) * 8)) & 255,
    );
    bytes[0] |= 1 << (8 - width);
    return bytes;
  }

  List<int> element(int id, List<int> body) => [
    ...number(id),
    ...length(body.length),
    ...body,
  ];
  List<int> uint(int id, int value) => element(id, number(value));
  List<int> string(int id, String text) => element(id, utf8.encode(text));
  List<int> float(int id, double value) =>
      element(id, (ByteData(8)..setFloat64(0, value)).buffer.asUint8List());
  const width = 160, height = 90, frameSize = width * height * 3;
  final format = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setUint32(4, width, Endian.little)
    ..setUint32(8, height, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 24, Endian.little)
    ..setUint32(20, frameSize, Endian.little);
  List<int> track(
    int id,
    int type,
    String codec,
    String lang,
    String name,
    List<int> attributes,
  ) => element(0xAE, [
    ...uint(0xD7, id),
    ...uint(0x73C5, id),
    ...uint(0x83, type),
    ...uint(0x88, id == 2 || id == 4 ? 1 : 0),
    ...string(0x86, codec),
    ...string(0x22B59C, lang),
    ...string(0x536E, name),
    ...attributes,
  ]);
  final tracks = element(0x1654AE6B, [
    ...track(1, 1, 'V_MS/VFW/FOURCC', 'und', 'Video', [
      ...element(0x63A2, format.buffer.asUint8List()),
      ...uint(0x23E383, 250000000),
      ...element(0xE0, [...uint(0xB0, width), ...uint(0xBA, height)]),
    ]),
    for (final id in [2, 3])
      ...track(
        id,
        2,
        'A_PCM/INT/LIT',
        id == 2 ? 'eng' : 'jpn',
        id == 2 ? 'English main' : 'Japanese main',
        [
          ...element(0xE1, [
            ...float(0xB5, 8000),
            ...uint(0x9F, 1),
            ...uint(0x6264, 16),
          ]),
        ],
      ),
    for (final id in [4, 5])
      ...track(
        id,
        17,
        'S_TEXT/UTF8',
        id == 4 ? 'eng' : 'chi',
        id == 4 ? 'English' : '简体中文',
        [],
      ),
  ]);
  List<int> block(int id, int ms, List<int> data) => [
    0x80 | id,
    (ms >> 8) & 255,
    ms & 255,
    0x80,
    ...data,
  ];
  final clusters = BytesBuilder(copy: false);
  for (var second = 0; second < 24; second++) {
    final body = BytesBuilder(copy: false)..add(uint(0xE7, second * 1000));
    for (var frame = 0; frame < 4; frame++) {
      final pixels = Uint8List(frameSize);
      for (var at = 0; at < pixels.length; at += 3) {
        pixels[at] = (second * 10) % 256;
        pixels[at + 1] = (at ~/ 3) % 256;
        pixels[at + 2] = frame * 60;
      }
      body.add(element(0xA3, block(1, frame * 250, pixels)));
      for (final id in [2, 3]) {
        body.add(element(0xA3, block(id, frame * 250, Uint8List(4000))));
      }
    }
    for (final id in [4, 5]) {
      body.add(
        element(0xA0, [
          ...element(
            0xA1,
            block(
              id,
              0,
              utf8.encode(id == 4 ? 'English internal subtitle' : '内嵌中文字幕'),
            ),
          ),
          ...uint(0x9B, 1000),
        ]),
      );
    }
    clusters.add(element(0x1F43B675, body.takeBytes()));
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes([
    ...element(0x1A45DFA3, [
      ...uint(0x4286, 1),
      ...uint(0x42F7, 1),
      ...uint(0x42F2, 4),
      ...uint(0x42F3, 8),
      ...string(0x4282, 'matroska'),
      ...uint(0x4287, 4),
      ...uint(0x4285, 2),
    ]),
    ...element(0x18538067, [
      ...element(0x1549A966, [
        ...uint(0x2AD7B1, 1000000),
        ...float(0x4489, 24000),
        ...string(0x4D80, 'ReelNest test'),
        ...string(0x5741, 'ReelNest test'),
      ]),
      ...tracks,
      ...clusters.takeBytes(),
    ]),
  ]);
}
