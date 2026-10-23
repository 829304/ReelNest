import 'dart:typed_data';

enum VideoScreenshotMode {
  subtitles('带字幕'),
  video('纯视频'),
  window('窗口所见');

  const VideoScreenshotMode(this.label);
  final String label;

  static VideoScreenshotMode fromStorage(String? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? subtitles;
}

/// Safe messages only: no source URI, credentials, native log or filesystem
/// exception text may escape into the player toast.
class VideoScreenshotFailure implements Exception {
  const VideoScreenshotFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class VideoScreenshotLimits {
  // Full 8K frames fit, without permitting unbounded image allocations.
  static const maxDimension = 16384;
  static const maxPixels = 40 * 1024 * 1024;
  static const maxPngBytes = 128 * 1024 * 1024;

  static void dimensions(int width, int height) {
    if (width <= 0 ||
        height <= 0 ||
        width > maxDimension ||
        height > maxDimension ||
        width * height > maxPixels) {
      throw const VideoScreenshotFailure('画面尺寸不可用或过大，无法截图。');
    }
  }

  static void png(Uint8List bytes) {
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 33 ||
        bytes.length > maxPngBytes ||
        !List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v) ||
        bytes[12] != 73 ||
        bytes[13] != 72 ||
        bytes[14] != 68 ||
        bytes[15] != 82) {
      throw const VideoScreenshotFailure('未能取得有效的 PNG 画面，请重试。');
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(8) != 13) {
      throw const VideoScreenshotFailure('未能取得有效的 PNG 画面，请重试。');
    }
    dimensions(header.getUint32(16), header.getUint32(20));
  }
}
