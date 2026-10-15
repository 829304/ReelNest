import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../domain/media_source.dart';

/// Original VideoFramePreviewGenerator's midpoint sampling, in whole seconds.
abstract final class VideoPreviewBuckets {
  static double interval(Duration duration, {required bool coarse}) {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return coarse ? 18 : 12;
    return math.max(
      (seconds / (coarse ? 84 : 96)).clamp(
        coarse ? 12.0 : 8.0,
        coarse ? 120.0 : 90.0,
      ),
      seconds / 1200,
    );
  }

  static Duration sample({
    required Duration time,
    required Duration duration,
    required bool coarse,
  }) {
    final step = interval(duration, coarse: coarse);
    final seconds = math.max(
      0,
      time.inMicroseconds / Duration.microsecondsPerSecond,
    );
    final end = math.max(
      0,
      duration.inMicroseconds / Duration.microsecondsPerSecond - .25,
    );
    return Duration(
      seconds: math
          .min((seconds / step).floor() * step + step * .5, end)
          .round(),
    );
  }
}

class VideoPreviewCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

/// Session-local, ephemeral resource. Never serialize, log or persist its URL.
class VideoPreviewResource {
  VideoPreviewResource({
    required this.identity,
    required this.location,
    this.offset = Duration.zero,
    this.cached = false,
  });
  final MediaIdentity identity;
  final String location;
  final Duration offset;
  final bool cached;
  final Object revision = Object();
  bool get remote => ['http', 'https'].contains(Uri.tryParse(location)?.scheme);
  @override
  String toString() => 'VideoPreviewResource';
}

class VideoPreviewFrame {
  VideoPreviewFrame(Uint8List bytes, this.sampleTime)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final Duration sampleTime;
  int get width => 312;
  int get height => 176;
  // Bound both the encoded data and the decoded Image.memory allocation.
  int get memoryCost => math.max(bytes.length, width * height * 4);
}

typedef VideoPreviewGenerator = Future<Uint8List?> Function(
  VideoPreviewResource resource,
  Duration sampleTime,
  VideoPreviewCancellation cancellation,
);
