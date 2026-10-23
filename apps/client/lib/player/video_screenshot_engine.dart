import 'dart:typed_data';

import '../features/playback/domain/video_screenshot.dart';

/// Capture the current player's frame, never a new decoder or network request.
abstract interface class VideoScreenshotEngine {
  Future<Uint8List> captureCurrentFrame(VideoScreenshotMode mode);
}
