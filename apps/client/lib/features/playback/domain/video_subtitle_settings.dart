enum VideoSubtitleColorPreset {
  white('白色', '#FFFFFF'),
  yellow('黄色', '#F5D547'),
  cyan('青色', '#7FE3E8'),
  green('绿色', '#8FE388'),
  orange('橙色', '#F5A14B');

  const VideoSubtitleColorPreset(this.displayName, this.mpvColor);
  final String displayName, mpvColor;
}

const _unchangedFont = Object();

/// Port of VideoSubtitleStyle. No forced ASS override or bitmap recoloring.
class VideoSubtitleStyle {
  const VideoSubtitleStyle({
    this.fontName,
    this.bold = false,
    this.colorPreset = VideoSubtitleColorPreset.white,
    this.borderSize = 3,
    this.backgroundOpacity = 0,
  });
  static const standard = VideoSubtitleStyle();
  final String? fontName;
  final bool bold;
  final VideoSubtitleColorPreset colorPreset;
  final double borderSize, backgroundOpacity;
  bool get isStandard => this == standard;
  @override
  bool operator ==(Object other) =>
      other is VideoSubtitleStyle &&
      fontName == other.fontName &&
      bold == other.bold &&
      colorPreset == other.colorPreset &&
      borderSize == other.borderSize &&
      backgroundOpacity == other.backgroundOpacity;
  @override
  int get hashCode =>
      Object.hash(fontName, bold, colorPreset, borderSize, backgroundOpacity);

  VideoSubtitleStyle get normalized => copyWith(
    borderSize: borderSize.isFinite ? borderSize.clamp(0, 6) : 3,
    backgroundOpacity: backgroundOpacity.isFinite
        ? backgroundOpacity.clamp(0, .8)
        : 0,
  );
  VideoSubtitleStyle copyWith({
    Object? fontName = _unchangedFont,
    bool? bold,
    VideoSubtitleColorPreset? colorPreset,
    double? borderSize,
    double? backgroundOpacity,
  }) => VideoSubtitleStyle(
    fontName: identical(fontName, _unchangedFont)
        ? this.fontName
        : fontName as String?,
    bold: bold ?? this.bold,
    colorPreset: colorPreset ?? this.colorPreset,
    borderSize: borderSize ?? this.borderSize,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
  );
  Map<String, Object?> toJson() => {
    'fontName': fontName,
    'bold': bold,
    'colorPreset': colorPreset.name,
    'borderSize': normalized.borderSize,
    'backgroundOpacity': normalized.backgroundOpacity,
  };
  factory VideoSubtitleStyle.fromJson(
    Map<String, dynamic> value,
  ) => VideoSubtitleStyle(
    fontName: value['fontName'] is String ? value['fontName'] as String : null,
    bold: value['bold'] == true,
    colorPreset:
        VideoSubtitleColorPreset.values
            .where((c) => c.name == value['colorPreset'])
            .firstOrNull ??
        VideoSubtitleColorPreset.white,
    borderSize: (value['borderSize'] as num?)?.toDouble() ?? 3,
    backgroundOpacity: (value['backgroundOpacity'] as num?)?.toDouble() ?? 0,
  ).normalized;
}

/// AppSettings owns clamping/quantization; mpv receives the resulting values.
class VideoTimingSettings {
  const VideoTimingSettings({
    this.audioDelay = 0,
    this.subtitleDelay = 0,
    this.subtitleScale = 1,
    this.subtitlePosition = 100,
  });
  final double audioDelay, subtitleDelay, subtitleScale, subtitlePosition;
  @override
  bool operator ==(Object other) =>
      other is VideoTimingSettings &&
      audioDelay == other.audioDelay &&
      subtitleDelay == other.subtitleDelay &&
      subtitleScale == other.subtitleScale &&
      subtitlePosition == other.subtitlePosition;
  @override
  int get hashCode =>
      Object.hash(audioDelay, subtitleDelay, subtitleScale, subtitlePosition);
  static double syncDelay(double value) =>
      value.isFinite ? (value.clamp(-3, 3) * 10).round() / 10 : 0;
  static double scale(double value) =>
      value.isFinite ? (value.clamp(.75, 1.5) * 20).round() / 20 : 1;
  static double position(double value) =>
      value.isFinite ? value.roundToDouble().clamp(70, 100) : 100;
  VideoTimingSettings get normalized => VideoTimingSettings(
    audioDelay: syncDelay(audioDelay),
    subtitleDelay: syncDelay(subtitleDelay),
    subtitleScale: scale(subtitleScale),
    subtitlePosition: position(subtitlePosition),
  );
  VideoTimingSettings copyWith({
    double? audioDelay,
    double? subtitleDelay,
    double? subtitleScale,
    double? subtitlePosition,
  }) => VideoTimingSettings(
    audioDelay: audioDelay ?? this.audioDelay,
    subtitleDelay: subtitleDelay ?? this.subtitleDelay,
    subtitleScale: subtitleScale ?? this.subtitleScale,
    subtitlePosition: subtitlePosition ?? this.subtitlePosition,
  ).normalized;
}
