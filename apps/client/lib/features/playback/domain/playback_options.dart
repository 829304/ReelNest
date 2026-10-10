class PlaybackOptions {
  const PlaybackOptions({
    this.defaultRate = 1,
    this.skipSeconds = 5,
    this.rewindSeconds = 5,
    this.rememberPosition = true,
    this.rememberRate = true,
    this.useLaunchVolume = false,
    this.launchVolume = 80,
    this.autoMarkWatched = true,
    this.watchedThreshold = .9,
    this.pitchCorrection = true,
  });
  final double defaultRate,
      skipSeconds,
      rewindSeconds,
      launchVolume,
      watchedThreshold;
  final bool rememberPosition,
      rememberRate,
      useLaunchVolume,
      autoMarkWatched,
      pitchCorrection;

  PlaybackOptions copyWith({
    double? defaultRate,
    double? skipSeconds,
    double? rewindSeconds,
    double? launchVolume,
    double? watchedThreshold,
    bool? rememberPosition,
    bool? rememberRate,
    bool? useLaunchVolume,
    bool? autoMarkWatched,
    bool? pitchCorrection,
  }) => PlaybackOptions(
    defaultRate: defaultRate ?? this.defaultRate,
    skipSeconds: skipSeconds ?? this.skipSeconds,
    rewindSeconds: rewindSeconds ?? this.rewindSeconds,
    launchVolume: launchVolume ?? this.launchVolume,
    watchedThreshold: watchedThreshold ?? this.watchedThreshold,
    rememberPosition: rememberPosition ?? this.rememberPosition,
    rememberRate: rememberRate ?? this.rememberRate,
    useLaunchVolume: useLaunchVolume ?? this.useLaunchVolume,
    autoMarkWatched: autoMarkWatched ?? this.autoMarkWatched,
    pitchCorrection: pitchCorrection ?? this.pitchCorrection,
  );
  Map<String, Object> toJson() => {
    'defaultRate': defaultRate,
    'skipSeconds': skipSeconds,
    'rewindSeconds': rewindSeconds,
    'launchVolume': launchVolume,
    'rememberPosition': rememberPosition,
    'rememberRate': rememberRate,
    'useLaunchVolume': useLaunchVolume,
    'autoMarkWatched': autoMarkWatched,
    'pitchCorrection': pitchCorrection,
  };
  factory PlaybackOptions.fromJson(Map<String, dynamic> data) {
    double number(String key, double fallback, double min, double max) {
      final value = data[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    bool flag(String key, bool fallback) =>
        data[key] is bool ? data[key] as bool : fallback;
    return PlaybackOptions(
      defaultRate: number('defaultRate', 1, .5, 3),
      skipSeconds: number('skipSeconds', 5, 5, 30),
      rewindSeconds: (number('rewindSeconds', 5, 0, 30) / 5).round() * 5.0,
      launchVolume: number('launchVolume', 80, 0, 100),
      rememberPosition: flag('rememberPosition', true),
      rememberRate: flag('rememberRate', true),
      useLaunchVolume: flag('useLaunchVolume', false),
      autoMarkWatched: flag('autoMarkWatched', true),
      pitchCorrection: flag('pitchCorrection', true),
    );
  }
}
