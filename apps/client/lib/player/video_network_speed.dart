/// mpv cache-speed is an INT64 byte rate, not a video bitrate. Missing/invalid
/// observations remain unknown; zero is a valid idle network sample.
int? parseVideoNetworkSpeed(String raw) {
  final rate = int.tryParse(raw.trim());
  return rate != null && rate >= 0 ? rate : null;
}
