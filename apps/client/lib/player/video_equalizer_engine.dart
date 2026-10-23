import 'dart:convert';

import '../features/playback/domain/video_equalizer_settings.dart';

abstract interface class VideoEqualizerEngine {
  VideoEqualizerSettings get equalizerSettings;
  Future<void> setEqualizerSettings(VideoEqualizerSettings value);
}

class VideoEqualizerRollbackFailure implements Exception {
  const VideoEqualizerRollbackFailure();
}

/// Own just this labelled audio filter. Keep foreign af entries (including
/// their order/options) and mpv's rate/pitch pipeline intact; never set all af.
class MpvEqualizerCommands {
  MpvEqualizerCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;
  static const label = 'reelnest-equalizer';

  Future<({String? graph, String other})> _state() async {
    final raw = await read('af');
    final entries = raw.isEmpty ? const [] : jsonDecode(raw);
    if (entries is! List) throw const FormatException('Invalid audio filters');
    String? graph;
    final other = <Object>[];
    for (final entry in entries) {
      if (entry is! Map) throw const FormatException('Invalid audio filter');
      if (entry['label'] != label) {
        other.add(entry);
        continue;
      }
      final params = entry['params'];
      if (graph != null ||
          entry['name'] != 'lavfi' ||
          entry['enabled'] == false ||
          params is! Map ||
          params.length != 1 ||
          params['graph'] is! String) {
        throw const FormatException('Unexpected equalizer filter');
      }
      graph = params['graph'] as String;
    }
    return (graph: graph, other: jsonEncode(other));
  }

  Future<void> _set(String? graph) async {
    final before = await _state();
    if (before.graph != graph) {
      await command(
        graph == null
            ? ['af', 'remove', '@$label']
            : [
                'af',
                'add',
                '@$label:lavfi=graph=%${utf8.encode(graph).length}%$graph',
              ],
      );
    }
    final after = await _state();
    if (after.graph != graph || before.other != after.other) {
      throw StateError('Audio equalizer update rejected');
    }
  }

  Future<void> apply(VideoEqualizerSettings value) async {
    final before = await _state();
    try {
      await _set(value.filterGraph);
    } catch (error, stack) {
      try {
        await _set(before.graph);
        if ((await _state()).other != before.other) {
          throw StateError('Audio filters changed during rollback');
        }
      } catch (_) {
        throw const VideoEqualizerRollbackFailure();
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<VideoEqualizerSettings> actual(VideoEqualizerSettings fallback) async {
    final graph = (await _state()).graph;
    if (graph == fallback.filterGraph) return fallback;
    if (graph == null) return fallback.copyWith(enabled: false);
    return VideoEqualizerSettings(
      enabled: true,
      preset: VideoEqualizerPreset.values.firstWhere(
        (p) => p.filterGraph == graph,
      ),
    );
  }
}
