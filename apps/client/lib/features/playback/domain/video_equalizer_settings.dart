/// The original video's shared five-band firequalizer presets. Music playback
/// remains a separate module; these settings apply only to the video session.
enum VideoEqualizerPreset {
  flat('纯平', [0, 0, 0, 0, 0]),
  pop('流行', [-1, 2, 4, 2, -1]),
  rock('摇滚', [4, 2, -1, 2, 4]),
  jazz('爵士', [3, 1, 1, 2, 3]),
  classical('古典', [4, 2, -1, 2, 3]),
  bassBoost('低音增强', [6, 4, 1, 0, 0]),
  vocal('人声', [-2, 0, 4, 3, 0]),
  trebleBoost('高音增强', [0, 0, 1, 4, 6]);

  const VideoEqualizerPreset(this.displayName, this.gainsDB);
  final String displayName;
  final List<double> gainsDB;
  static const frequencies = [60, 230, 910, 3600, 14000];

  String? get filterGraph => this == flat
      ? null
      : "firequalizer=gain_entry='${List.generate(5, (i) => 'entry(${frequencies[i]},${gainsDB[i].toStringAsFixed(1)})').join(';')}'";
}

class VideoEqualizerSettings {
  const VideoEqualizerSettings({
    this.enabled = false,
    this.preset = VideoEqualizerPreset.flat,
  });
  final bool enabled;
  final VideoEqualizerPreset preset;
  String? get filterGraph => enabled ? preset.filterGraph : null;

  VideoEqualizerSettings copyWith({
    bool? enabled,
    VideoEqualizerPreset? preset,
  }) => VideoEqualizerSettings(
    enabled: enabled ?? this.enabled,
    preset: preset ?? this.preset,
  );

  factory VideoEqualizerSettings.fromJson(Map<String, dynamic> json) =>
      VideoEqualizerSettings(
        enabled: json['enabled'] == true,
        preset:
            VideoEqualizerPreset.values
                .where((p) => p.name == json['preset'])
                .firstOrNull ??
            VideoEqualizerPreset.flat,
      );
  Map<String, dynamic> toJson() => {'enabled': enabled, 'preset': preset.name};

  @override
  bool operator ==(Object other) =>
      other is VideoEqualizerSettings &&
      enabled == other.enabled &&
      preset == other.preset;
  @override
  int get hashCode => Object.hash(enabled, preset);
}
