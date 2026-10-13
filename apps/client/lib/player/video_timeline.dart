import 'dart:convert';

class VideoChapter {
  const VideoChapter({
    required this.index,
    required this.title,
    required this.time,
  });
  final int index;
  final String title;
  final Duration time;

  static List<VideoChapter> decode(String raw) {
    if (raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid chapter list');
    final result = <VideoChapter>[];
    for (var index = 0; index < decoded.length; index++) {
      final entry = decoded[index];
      if (entry is! Map) continue;
      final seconds = double.tryParse('${entry['time']}');
      if (seconds == null ||
          !seconds.isFinite ||
          seconds < 0 ||
          seconds > 9223372036854) {
        continue;
      }
      final rawTitle = entry['title'];
      final title = rawTitle is String ? rawTitle.trim() : null;
      result.add(
        VideoChapter(
          index: index,
          title: title == null || title.isEmpty ? '章节 ${index + 1}' : title,
          time: Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond).round(),
          ),
        ),
      );
    }
    result.sort((a, b) {
      final order = a.time.compareTo(b.time);
      return order == 0 ? a.index.compareTo(b.index) : order;
    });
    return List.unmodifiable(result);
  }
}

/// Optional native capability; session ownership and serialization remain in
/// PlaybackSession. The UI never sends mpv commands directly.
abstract interface class VideoTimelineEngine {
  List<VideoChapter> get chapters;
  Stream<List<VideoChapter>> get chapterChanges;
  Future<void> refreshChapters();
  Future<void> setLoopCurrentItem(bool enabled);
  Future<void> setABLoop(Duration? start, Duration? end);
  Future<void> stepFrame({required bool backward});
}

/// Narrow, testable libmpv adapter, matching VideoLoop/FrameCommandEngine.swift.
class MpvTimelineCommands {
  MpvTimelineCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;

  Future<void> setLoopCurrentItem(bool enabled) async {
    final value = enabled ? 'inf' : 'no';
    await command(['set', 'loop-file', value]);
    final actual = await read('loop-file');
    if (!(enabled ? actual == 'inf' : actual == 'no' || actual == '0')) {
      throw StateError('Loop property rejected');
    }
  }

  Future<void> setABLoop(Duration? start, Duration? end) async {
    if ((start != null && start < Duration.zero) ||
        (end != null && (start == null || end <= start))) {
      throw ArgumentError('Invalid A–B range');
    }
    String value(Duration? time) => time == null
        ? 'no'
        : (time.inMicroseconds / Duration.microsecondsPerSecond).toString();
    // Clear B before replacing A: never leave an old active range spanning the
    // newly selected start while the two native property writes are in flight.
    await command(['set', 'ab-loop-b', 'no']);
    await command(['set', 'ab-loop-a', value(start)]);
    await command(['set', 'ab-loop-b', value(end)]);
    for (final entry in {'ab-loop-a': start, 'ab-loop-b': end}.entries) {
      final actual = await read(entry.key);
      final seconds = double.tryParse(actual);
      if (entry.value == null
          ? actual != 'no'
          : seconds == null ||
                !seconds.isFinite ||
                (seconds -
                            entry.value!.inMicroseconds /
                                Duration.microsecondsPerSecond)
                        .abs() >=
                    .001) {
        throw StateError('A–B property rejected');
      }
    }
  }

  Future<void> stepFrame({required bool backward}) =>
      command([backward ? 'frame-back-step' : 'frame-step']);
}
