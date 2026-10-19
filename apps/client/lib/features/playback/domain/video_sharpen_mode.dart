enum VideoSharpenMode {
  off('关闭', null),
  light('轻微', '0.4'),
  medium('适中', '0.8'),
  strong('明显', '1.2');

  const VideoSharpenMode(this.displayName, this.lumaAmount);
  final String displayName;

  /// Original VideoFilterChainPolicy unsharp=la, leaving chroma untouched.
  final String? lumaAmount;
}
