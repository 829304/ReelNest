/// AppSettings.AutomaticScanInterval. File scans and TMDB matching store their
/// own independent preferences using the same original interval choices.
enum AutomaticScanInterval {
  disabled('关闭', null),
  fifteenMinutes('每 15 分钟', Duration(minutes: 15)),
  hourly('每小时', Duration(hours: 1)),
  sixHours('每 6 小时', Duration(hours: 6)),
  daily('每天', Duration(days: 1));

  const AutomaticScanInterval(this.displayName, this.duration);
  final String displayName;
  final Duration? duration;

  static AutomaticScanInterval parse(String? value) => values.firstWhere(
    (interval) => interval.name == value,
    orElse: () => disabled,
  );
}
