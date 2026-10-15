enum VideoScrubberPreviewMode {
  off('关闭'),
  performance('流畅优先'),
  balanced('画面优先');

  const VideoScrubberPreviewMode(this.label);

  final String label;

  static VideoScrubberPreviewMode parse(Object? value) =>
      values.where((mode) => mode.name == value).firstOrNull ?? performance;
}
