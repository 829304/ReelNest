import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../platform/hidden_file_access.dart';

class SidecarSubtitle {
  const SidecarSubtitle(this.path, this.displayName, this.languageHint);
  final String path;
  final String displayName;
  final String? languageHint;

  /// Same matching/priority rules as SidecarSubtitleFile.find. Never reads
  /// subtitle bodies into Dart memory; decoding belongs to mpv/libass.
  static Future<List<SidecarSubtitle>> find(String videoPath) async {
    final base = p.basenameWithoutExtension(videoPath).toLowerCase();
    final candidates = <({int priority, String path})>[];
    try {
      final entries = await Directory(p.dirname(videoPath))
          .list(followLinks: false)
          .toList();
      final hidden = await hiddenFilePaths(entries.map((e) => e.path).toList());
      for (final file in entries) {
        if (file is! File ||
            !{
              '.srt',
              '.ass',
              '.ssa',
              '.vtt',
            }.contains(p.extension(file.path).toLowerCase())) {
          continue;
        }
        if (hidden.contains(file.path)) continue;
        final stem = p.basenameWithoutExtension(file.path).toLowerCase();
        final first = _tokens(stem).firstOrNull;
        final priority = stem == base
            ? 0
            : ['.', '-', '_'].any((s) => stem.startsWith('$base$s'))
            ? 1
            : {'subtitle', 'subtitles', 'subs'}.contains(first)
            ? 2
            : 3;
        if (priority < 3) candidates.add((priority: priority, path: file.path));
      }
    } on FileSystemException {
      return const [];
    }
    candidates.sort(
      (a, b) => a.priority != b.priority
          ? a.priority.compareTo(b.priority)
          : _naturalCompare(p.basename(a.path), p.basename(b.path)),
    );
    return candidates
        .map((c) {
          final name = p.basename(c.path);
          final lower = name.toLowerCase();
          final tokens = _tokens(lower).toSet();
          final hint =
              tokens.intersection({'zh', 'chs', 'hans'}).isNotEmpty ||
                  lower.contains('简')
              ? '中文'
              : tokens.intersection({'cht', 'hant'}).isNotEmpty ||
                    lower.contains('繁')
              ? '繁体中文'
              : tokens.contains('en')
              ? '英文'
              : tokens.intersection({'jp', 'ja'}).isNotEmpty
              ? '日文'
              : null;
          return SidecarSubtitle(c.path, name, hint);
        })
        .toList(growable: false);
  }

  static List<String> _tokens(String text) => text
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((s) => s.isNotEmpty)
      .toList();
  static int _naturalCompare(String a, String b) {
    final parts = RegExp(r'\d+|\D+');
    final lhs = parts
        .allMatches(a.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final rhs = parts
        .allMatches(b.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    for (var i = 0; i < lhs.length && i < rhs.length; i++) {
      final x = int.tryParse(lhs[i]), y = int.tryParse(rhs[i]);
      final comparison = x != null && y != null
          ? x.compareTo(y)
          : lhs[i].compareTo(rhs[i]);
      if (comparison != 0) return comparison;
    }
    final result = lhs.length.compareTo(rhs.length);
    return result == 0 ? a.compareTo(b) : result;
  }
}
