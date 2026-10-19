enum VideoHardwareDecodingMode {
  safe('兼容', 'auto-safe'),
  automatic('自动', 'auto'),
  off('关闭', 'no');

  const VideoHardwareDecodingMode(this.displayName, this.mpvValue);
  final String displayName;
  final String mpvValue;
}

/// Original AppSettings defaults. Decoding is independent of the GL/SW renderer.
class VideoPerformanceSettings {
  const VideoPerformanceSettings({
    this.hardwareDecodingMode = VideoHardwareDecodingMode.safe,
    this.memoryBufferingEnabled = true,
  });

  final VideoHardwareDecodingMode hardwareDecodingMode;
  final bool memoryBufferingEnabled;

  VideoPerformanceSettings copyWith({
    VideoHardwareDecodingMode? hardwareDecodingMode,
    bool? memoryBufferingEnabled,
  }) => VideoPerformanceSettings(
    hardwareDecodingMode: hardwareDecodingMode ?? this.hardwareDecodingMode,
    memoryBufferingEnabled:
        memoryBufferingEnabled ?? this.memoryBufferingEnabled,
  );

  Map<String, Object> toJson() => {
    'hardwareDecodingMode': hardwareDecodingMode.name,
    'memoryBufferingEnabled': memoryBufferingEnabled,
  };

  factory VideoPerformanceSettings.fromJson(Map<String, dynamic> json) =>
      VideoPerformanceSettings(
        hardwareDecodingMode:
            VideoHardwareDecodingMode.values
                .where((m) => m.name == json['hardwareDecodingMode'])
                .firstOrNull ??
            VideoHardwareDecodingMode.safe,
        memoryBufferingEnabled: json['memoryBufferingEnabled'] is bool
            ? json['memoryBufferingEnabled'] as bool
            : true,
      );

  @override
  bool operator ==(Object other) =>
      other is VideoPerformanceSettings &&
      hardwareDecodingMode == other.hardwareDecodingMode &&
      memoryBufferingEnabled == other.memoryBufferingEnabled;

  @override
  int get hashCode => Object.hash(hardwareDecodingMode, memoryBufferingEnabled);
}
