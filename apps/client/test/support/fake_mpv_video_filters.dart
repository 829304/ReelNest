import 'dart:convert';

/// Stateful command double. Native integration tests separately validate mpv's
/// labelled replacement and byte-length quoting behavior.
class FakeMpvVideoFilters {
  final filters = <Map<String, dynamic>>[];
  final properties = <String, String>{
    'video-aspect-override': 'no',
    'panscan': '0',
    'deinterlace': 'no',
    'video-rotate': '0',
    'brightness': '0',
    'contrast': '0',
    'saturation': '0',
    'gamma': '0',
    'hue': '0',
    'video-params/colormatrix': 'bt.709',
  };
  final calls = <List<String>>[];
  bool Function(List<String>)? reject;
  Future<String> read(String name) async =>
      name == 'vf' ? jsonEncode(filters) : properties[name]!;

  static Map<String, dynamic> parse(String argument) {
    final colon = argument.indexOf(':');
    final label = argument.substring(1, colon);
    final body = argument.substring(colon + 1), equal = body.indexOf('=');
    final name = equal < 0 ? body : body.substring(0, equal);
    final parameters = <String, String>{};
    if (equal >= 0) {
      final bytes = utf8.encode(body.substring(equal + 1));
      var at = 0;
      while (at < bytes.length) {
        final keyEnd = bytes.indexOf(61, at);
        final key = utf8.decode(bytes.sublist(at, keyEnd));
        at = keyEnd + 1;
        if (bytes[at] != 37) throw StateError('Expected mpv byte quoting');
        final countEnd = bytes.indexOf(37, at + 1);
        final count = int.parse(utf8.decode(bytes.sublist(at + 1, countEnd)));
        at = countEnd + 1;
        parameters[key] = utf8.decode(bytes.sublist(at, at + count));
        at += count;
        if (at < bytes.length && bytes[at++] != 58) {
          throw StateError('Invalid parameter delimiter');
        }
      }
    }
    return {
      'label': label,
      'name': name,
      if (parameters.isNotEmpty) 'params': parameters,
    };
  }

  Future<void> command(List<String> args) async {
    calls.add(args);
    if (reject?.call(args) ?? false) {
      throw StateError('Fixture command rejected');
    }
    if (args.first == 'set') {
      properties[args[1]] = args[2];
      return;
    }
    if (args[1] == 'remove') {
      filters.removeWhere((f) => f['label'] == args[2].substring(1));
    } else {
      final filter = parse(args[2]);
      final at = filters.indexWhere((f) => f['label'] == filter['label']);
      if (at < 0) {
        filters.add(filter);
      } else {
        filters[at] = filter;
      }
    }
  }
}
