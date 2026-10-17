enum VideoAspectOverride {
  source('跟随片源', 'no'),
  square('1:1', '1:1'),
  fourByThree('4:3', '4:3'),
  sixteenByNine('16:9', '16:9'),
  sixteenByTen('16:10', '16:10'),
  twentyOneByNine('21:9', '21:9'),
  cinemaScope('2.39:1', '2.39:1');

  const VideoAspectOverride(this.displayName, this.mpvValue);
  final String displayName, mpvValue;
}

enum VideoCropMode {
  none('关闭', 0),
  gentle('轻微', .18),
  balanced('平衡', .42),
  fill('填满', 1);

  const VideoCropMode(this.displayName, this.panscan);
  final String displayName;
  final double panscan;
}

enum VideoDeinterlaceMode {
  off('关闭', 'no'),
  auto('自动', 'auto'),
  on('开启', 'yes');

  const VideoDeinterlaceMode(this.displayName, this.mpvValue);
  final String displayName, mpvValue;
}

enum VideoRotationMode {
  source('跟随源文件', 0),
  clockwise90('顺时针 90', 90),
  rotate180('180', 180),
  counterclockwise90('逆时针 90', 270);

  const VideoRotationMode(this.displayName, this.degrees);
  final String displayName;
  // 0 adds no rotation; mpv's "no" would discard the file's rotation metadata.
  final int degrees;
}

enum VideoFlipMode {
  none('关闭'),
  horizontal('水平'),
  vertical('垂直'),
  both('双向');

  const VideoFlipMode(this.displayName);
  final String displayName;
}

/// Original VideoPlaybackPropertyPolicy defaults, shared by every video source.
class VideoDisplaySettings {
  const VideoDisplaySettings({
    this.aspectOverride = VideoAspectOverride.source,
    this.cropMode = VideoCropMode.none,
    this.deinterlaceMode = VideoDeinterlaceMode.off,
    this.rotationMode = VideoRotationMode.source,
    this.flipMode = VideoFlipMode.none,
  });

  final VideoAspectOverride aspectOverride;
  final VideoCropMode cropMode;
  final VideoDeinterlaceMode deinterlaceMode;
  final VideoRotationMode rotationMode;
  final VideoFlipMode flipMode;

  VideoDisplaySettings copyWith({
    VideoAspectOverride? aspectOverride,
    VideoCropMode? cropMode,
    VideoDeinterlaceMode? deinterlaceMode,
    VideoRotationMode? rotationMode,
    VideoFlipMode? flipMode,
  }) => VideoDisplaySettings(
    aspectOverride: aspectOverride ?? this.aspectOverride,
    cropMode: cropMode ?? this.cropMode,
    deinterlaceMode: deinterlaceMode ?? this.deinterlaceMode,
    rotationMode: rotationMode ?? this.rotationMode,
    flipMode: flipMode ?? this.flipMode,
  );

  @override
  bool operator ==(Object other) =>
      other is VideoDisplaySettings &&
      aspectOverride == other.aspectOverride &&
      cropMode == other.cropMode &&
      deinterlaceMode == other.deinterlaceMode &&
      rotationMode == other.rotationMode &&
      flipMode == other.flipMode;
  @override
  int get hashCode => Object.hash(
    aspectOverride,
    cropMode,
    deinterlaceMode,
    rotationMode,
    flipMode,
  );
}
