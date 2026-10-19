import '../features/playback/domain/video_sharpen_mode.dart';
import 'mpv_owned_video_filters.dart';

abstract interface class VideoSharpenEngine {
  VideoSharpenMode get sharpenMode;
  Future<void> setSharpenMode(VideoSharpenMode mode);
}

class VideoSharpenRollbackFailure implements Exception {
  const VideoSharpenRollbackFailure();
}

class MpvSharpenCommands {
  MpvSharpenCommands({required this.filters});
  final MpvOwnedVideoFilters filters;
  static const label = 'reelnest-sharpen';

  Future<VideoSharpenMode> current() async {
    final owned = (await filters.snapshot()).where((f) => f.label == label);
    if (owned.isEmpty) return VideoSharpenMode.off;
    final amount = double.tryParse(owned.single.parameters['la'] ?? '');
    return VideoSharpenMode.values.firstWhere(
      (m) =>
          m.lumaAmount != null &&
          amount != null &&
          (double.parse(m.lumaAmount!) - amount).abs() < .0001,
    );
  }

  Future<void> apply(VideoSharpenMode mode) async {
    try {
      await filters.update({
        label: mode == VideoSharpenMode.off
            ? null
            : MpvVideoFilter(label, 'unsharp', {'la': mode.lumaAmount!}),
      });
      if (await current() != mode) throw StateError('Sharpen filter rejected');
    } on VideoFilterRollbackFailure {
      throw const VideoSharpenRollbackFailure();
    }
  }
}
