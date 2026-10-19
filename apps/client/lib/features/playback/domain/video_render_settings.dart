enum VideoDebandMode {
  off('关闭', 64, 16, 48),
  light('轻微', 32, 12, 24),
  strong('明显', 48, 18, 36);

  const VideoDebandMode(
    this.displayName,
    this.threshold,
    this.range,
    this.grain,
  );
  final String displayName;
  final int threshold, range, grain;
}

enum VideoToneMappingMode {
  auto('自动', 'auto'),
  bt2390('BT.2390', 'bt.2390'),
  hable('Hable', 'hable'),
  mobius('Mobius', 'mobius'),
  reinhard('Reinhard', 'reinhard'),
  clip('裁剪', 'clip');

  const VideoToneMappingMode(this.displayName, this.mpvValue);
  final String displayName, mpvValue;
}

/// Original VideoDebandPolicy / VideoToneMappingPolicy defaults.
class VideoRenderSettings {
  const VideoRenderSettings({
    this.debandMode = VideoDebandMode.off,
    this.toneMappingMode = VideoToneMappingMode.auto,
  });
  final VideoDebandMode debandMode;
  final VideoToneMappingMode toneMappingMode;

  VideoRenderSettings copyWith({
    VideoDebandMode? debandMode,
    VideoToneMappingMode? toneMappingMode,
  }) => VideoRenderSettings(
    debandMode: debandMode ?? this.debandMode,
    toneMappingMode: toneMappingMode ?? this.toneMappingMode,
  );

  Map<String, String> toJson() => {
    'debandMode': debandMode.name,
    'toneMappingMode': toneMappingMode.name,
  };

  factory VideoRenderSettings.fromJson(Map<String, dynamic> json) =>
      VideoRenderSettings(
        debandMode:
            VideoDebandMode.values
                .where((m) => m.name == json['debandMode'])
                .firstOrNull ??
            VideoDebandMode.off,
        toneMappingMode:
            VideoToneMappingMode.values
                .where((m) => m.name == json['toneMappingMode'])
                .firstOrNull ??
            VideoToneMappingMode.auto,
      );

  @override
  bool operator ==(Object other) =>
      other is VideoRenderSettings &&
      debandMode == other.debandMode &&
      toneMappingMode == other.toneMappingMode;
  @override
  int get hashCode => Object.hash(debandMode, toneMappingMode);
}
