import 'dart:convert';

class VideoFilterRollbackFailure implements Exception {
  const VideoFilterRollbackFailure();
}

class MpvVideoFilter {
  const MpvVideoFilter(this.label, this.name, [this.parameters = const {}]);
  final String label, name;
  final Map<String, String> parameters;

  String get argument =>
      '@$label:$name${parameters.isEmpty ? '' : '=${parameters.entries.map((e) => '${e.key}=%${utf8.encode(e.value).length}%${e.value}').join(':')}'}';

  bool same(MpvVideoFilter other) =>
      label == other.label &&
      name == other.name &&
      parameters.length == other.parameters.length &&
      parameters.entries.every((e) => other.parameters[e.key] == e.value);
}

/// All app-owned vf stages share one order, independently of click order.
/// Unknown/base quality filters retain their data and relative order. Only
/// owned entries are removed/replaced; never overwrite the entire vf string.
class MpvOwnedVideoFilters {
  MpvOwnedVideoFilters({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;
  static const names = {
    'reelnest-hflip': 'hflip',
    'reelnest-vflip': 'vflip',
    'reelnest-sharpen': 'unsharp',
    // CPU equivalent of the GPU color stage, after every video filter.
    'reelnest-color': 'lavfi',
  };

  Future<({List<MpvVideoFilter> owned, String other})> _state() async {
    final raw = await read('vf');
    final list = raw.isEmpty ? const [] : jsonDecode(raw);
    if (list is! List) throw const FormatException('Invalid video filters');
    final owned = <MpvVideoFilter>[], other = <Object>[];
    final labels = <String>{};
    for (final entry in list) {
      if (entry is! Map) throw const FormatException('Invalid video filter');
      final label = entry['label'];
      if (!names.containsKey(label)) {
        other.add(entry);
        continue;
      }
      if (!labels.add(label as String) ||
          entry['name'] != names[label] ||
          entry['enabled'] == false) {
        throw const FormatException('Unexpected owned video filter');
      }
      final params = entry['params'];
      if (params != null && params is! Map) {
        throw const FormatException('Invalid filter parameters');
      }
      owned.add(
        MpvVideoFilter(label, names[label]!, {
          if (params is Map)
            for (final e in params.entries) e.key as String: e.value as String,
        }),
      );
    }
    return (owned: owned, other: jsonEncode(other));
  }

  Future<List<MpvVideoFilter>> snapshot() async => (await _state()).owned;

  bool _same(List<MpvVideoFilter> a, List<MpvVideoFilter> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i].same(b[i])).every((v) => v);

  Future<void> restore(List<MpvVideoFilter> target) async {
    final before = await _state();
    final current = before.owned;
    var prefix = 0;
    while (prefix < current.length &&
        prefix < target.length &&
        current[prefix].label == target[prefix].label) {
      prefix++;
    }
    // Preserve the common prefix; same-label add updates parameters in place.
    for (var i = 0; i < prefix; i++) {
      if (!current[i].same(target[i])) {
        await command(['vf', 'add', target[i].argument]);
      }
    }
    for (final filter in current.skip(prefix).toList().reversed) {
      await command(['vf', 'remove', '@${filter.label}']);
    }
    for (final filter in target.skip(prefix)) {
      await command(['vf', 'add', filter.argument]);
    }
    final after = await _state();
    if (!_same(after.owned, target) || before.other != after.other) {
      throw StateError('Video filter update rejected');
    }
  }

  Future<void> update(Map<String, MpvVideoFilter?> changes) async {
    final before = await snapshot();
    final target = {for (final f in before) f.label: f};
    for (final entry in changes.entries) {
      if (!names.containsKey(entry.key) ||
          (entry.value != null &&
              (entry.value!.label != entry.key ||
                  entry.value!.name != names[entry.key]))) {
        throw ArgumentError('Invalid owned video filter');
      }
      if (entry.value == null) {
        target.remove(entry.key);
      } else {
        target[entry.key] = entry.value!;
      }
    }
    try {
      await restore([
        for (final label in names.keys)
          if (target.containsKey(label)) target[label]!,
      ]);
    } catch (error, stack) {
      try {
        await restore(before);
      } catch (_) {
        throw const VideoFilterRollbackFailure();
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}
