/// AppSettings.MetadataMatchTolerance; the original default is loose.
enum TmdbMatchTolerance {
  loose('宽松', '更易匹配，命名混乱的库也能尽量覆盖（默认），可能偶有误配', .42, 16),
  standard('标准', '在准确度与覆盖率之间平衡', .58, 10),
  strict('严格', '仅高置信度才自动套用，最大限度避免误配', .74, 6);

  const TmdbMatchTolerance(
    this.displayName,
    this.summary,
    this.videoThreshold,
    this.searchLimit,
  );
  final String displayName, summary;
  final double videoThreshold;
  final int searchLimit;
  static TmdbMatchTolerance parse(String? value) =>
      values.firstWhere((entry) => entry.name == value, orElse: () => loose);
}
