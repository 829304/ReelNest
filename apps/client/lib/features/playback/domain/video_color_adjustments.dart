/// Original VideoColorAdjustments: integer-valued -100...100; zero is neutral.
class VideoColorAdjustments {
  const VideoColorAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.gamma = 0,
    this.hue = 0,
  });

  static const neutral = VideoColorAdjustments();
  final double brightness, contrast, saturation, gamma, hue;
  bool get isNeutral => this == neutral;

  static double clamp(double value) =>
      value.isFinite ? value.clamp(-100, 100).roundToDouble() : 0;

  VideoColorAdjustments get normalized => VideoColorAdjustments(
    brightness: clamp(brightness),
    contrast: clamp(contrast),
    saturation: clamp(saturation),
    gamma: clamp(gamma),
    hue: clamp(hue),
  );

  VideoColorAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? gamma,
    double? hue,
  }) => VideoColorAdjustments(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    gamma: gamma ?? this.gamma,
    hue: hue ?? this.hue,
  );

  Map<String, double> toJson() {
    final value = normalized;
    return {
      'brightness': value.brightness,
      'contrast': value.contrast,
      'saturation': value.saturation,
      'gamma': value.gamma,
      'hue': value.hue,
    };
  }

  factory VideoColorAdjustments.fromJson(Map<String, dynamic> value) {
    double number(String name) => (value[name] as num?)?.toDouble() ?? 0;
    return VideoColorAdjustments(
      brightness: number('brightness'),
      contrast: number('contrast'),
      saturation: number('saturation'),
      gamma: number('gamma'),
      hue: number('hue'),
    ).normalized;
  }

  @override
  bool operator ==(Object other) =>
      other is VideoColorAdjustments &&
      brightness == other.brightness &&
      contrast == other.contrast &&
      saturation == other.saturation &&
      gamma == other.gamma &&
      hue == other.hue;
  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, gamma, hue);
}
