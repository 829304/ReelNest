/// The original mpv track-cycle/visibility commands preserve the selected
/// subtitle while hiding it, rather than changing sid to "no".
abstract interface class VideoTrackShortcutEngine {
  Future<void> cycleSubtitleTrack();
  Future<void> toggleSubtitleVisibility();
  Future<void> cycleAudioTrack();
}
