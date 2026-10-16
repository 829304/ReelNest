import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/player/video_engine.dart';
import 'package:reelnest/player/video_network_speed.dart';

void main() {
  test('native byte rate distinguishes unavailable, idle and active input', () {
    for (final raw in [
      '',
      'N/A',
      'null',
      '-1',
      'NaN',
      'Infinity',
      '1.5',
      '1e6',
    ]) {
      expect(parseVideoNetworkSpeed(raw), isNull, reason: raw);
    }
    expect(parseVideoNetworkSpeed('0'), 0);
    expect(parseVideoNetworkSpeed(' 1048576 '), 1048576);
    expect(parseVideoNetworkSpeed('9223372036854775808'), isNull);
    expect(const VideoClock().networkBytesPerSecond, isNull);
  });
}
