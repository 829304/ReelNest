import 'dart:math' as math;
import 'dart:isolate';

import 'package:characters/characters.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/media_source.dart';
import 'tmdb_match_tolerance.dart';
import 'tmdb_models.dart';

typedef ScoredTmdbMatch = ({TmdbCandidate candidate, double confidence});

/// Translation of MetadataMatchScorer and AppState.bestTMDBVideoMatch.
class TmdbMatchScorer {
  static String _replace(String text, String pattern) => text.replaceAll(
    RegExp(pattern, caseSensitive: false, unicode: true),
    ' ',
  );
  static String _spaces(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _brackets(String text) =>
      _replace(text, r'\([^)]*\)|\[[^\]]*\]|【[^】]*】');
  static const _number = '[0-9一二三四五六七八九十百千万两]+';
  static String _noise(String text) => _replace(
    text,
    [
      r'\bs\d{1,2}\s*e\d{1,3}\b',
      r'\bs\d{1,2}\b',
      r'\bseason\s*\d+\b',
      r'\b(?:ep|episode|e)\s*\d{1,3}\b',
      '第\\s*$_number\\s*[季部集话話]',
      '全\\s*$_number\\s*[集话話]',
      '全集|完结|完結|更新至\\s*$_number\\s*[集话話]?',
      r'\b(part|pt)\s*\d+\b',
      r'\b\d{3,4}p\b',
      r'\b(4k|8k|2160p|1080p|720p|480p|bluray|blu-ray|webrip|web-dl|webdl|hdtv|bdrip|dvdrip|x264|x265|h264|h265|hevc|avc|aac|flac|dts|truehd|atmos|remux|proper|repack|complete|hdr|hdr10|dv|dolby|chs|cht|jpn|kor|eng|multi|netflix|nf|amzn|amazon|hulu|disney|dsnp|bilibili|bglobal)\b',
    ].join('|'),
  );
  static String normalized(String raw) {
    if (raw.length > 1024) throw const SourceFailure('影视标题过长，请先手动修正资料。');
    var text = _noise(
      _brackets(_replace(raw.toLowerCase(), r'\.[a-z0-9]{2,5}$')),
    );
    text = _replace(text, r'[._/\-]+');
    return _spaces(
      text.replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' '),
    );
  }

  static String _series(String raw) {
    if (raw.length > 1024) throw const SourceFailure('影视标题过长，请先手动修正资料。');
    var text = _brackets(_replace(raw.toLowerCase(), r'\.[a-z0-9]{2,5}$'));
    for (final pattern in [
      r'\bs\d{1,2}\s*e\d{1,3}\b',
      r'[\s._-]+s\d{1,2}\b.*',
      r'\bseason\s*\d+\b',
      r'\b(?:ep|episode|e)\s*\d{1,3}\b',
      '第\\s*$_number\\s*[季部].*',
      '第\\s*$_number\\s*[集话話].*',
      r'[\s._-]+\d{1,4}\s*(?:v\d+)?$',
      r'[\s._-]+\d{1,4}\s*[集话話].*',
    ]) {
      final match = RegExp(
        pattern,
        caseSensitive: false,
        unicode: true,
      ).firstMatch(text);
      if (match != null) {
        text = text.substring(0, match.start);
        break;
      }
    }
    return _spaces(
      _replace(_replace(_noise(text), r'\b(19\d{2}|20\d{2})\b'), r'[._/\-]+'),
    );
  }

  static List<String> _titles(String raw) => unique([
    normalized(raw),
    _series(raw),
    _replace(normalized(raw), r'\b\d{4}\b'),
    ...raw.split(RegExp('[|｜:：]')).map(normalized),
  ]);
  static List<String> queries(
    IndexedMedia item, {
    Iterable<String> folders = const [],
  }) => unique([
    for (final title in [
      item.title,
      if (item.originalTitle != null) item.originalTitle!,
      ...folders,
    ]) ...[
      _series(title),
      normalized(title),
      _replace(normalized(title), r'\b\d{4}\b'),
      title.trim(),
      ...title.split(RegExp('[|｜:：]')).map(normalized),
    ],
  ]);
  static List<String> unique(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values.map(_spaces))
        if (value.characters.length >= 2 &&
            seen.add(
              unorm
                  .nfd(value)
                  .replaceAll(RegExp(r'\p{M}', unicode: true), '')
                  .toLowerCase(),
            ))
          value,
    ];
  }

  static bool specific(String query) {
    final value = normalized(query);
    return value.characters.length >= 3 &&
        !RegExp(r'^\d+$').hasMatch(value) &&
        !const {
          'season',
          'series',
          'show',
          'tv',
          'anime',
          'movie',
          'episode',
          '第 季',
          '第 集',
          '全集',
          '完结',
          '完結',
        }.contains(value);
  }

  static double similarity(String a, String b) {
    if (a == b) return 1;
    final lhs = a.characters.toList(), rhs = b.characters.toList();
    if (lhs.isEmpty || rhs.isEmpty) return 0;
    var previous = List.generate(rhs.length + 1, (i) => i);
    for (var i = 1; i <= lhs.length; i++) {
      final current = List.filled(rhs.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= rhs.length; j++) {
        current[j] = math.min(
          math.min(previous[j] + 1, current[j - 1] + 1),
          previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1),
        );
      }
      previous = current;
    }
    return 1 - previous.last / math.max(lhs.length, rhs.length);
  }

  static double _titleSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final aa = a.replaceAll(' ', ''), bb = b.replaceAll(' ', '');
    var score = math.max(similarity(a, b), similarity(aa, bb));
    if (aa.contains(bb) || bb.contains(aa)) {
      score = math.max(
        score,
        .72 +
            .22 *
                math.min(aa.characters.length, bb.characters.length) /
                math.max(aa.characters.length, bb.characters.length),
      );
    }
    final lhs = a.split(' ').where((s) => s.characters.length > 1).toSet();
    final rhs = b.split(' ').where((s) => s.characters.length > 1).toSet();
    if (lhs.isNotEmpty && rhs.isNotEmpty) {
      score = math.max(
        score,
        2 * lhs.intersection(rhs).length / (lhs.length + rhs.length),
      );
    }
    return score;
  }

  static double _best(Iterable<String> lhs, List<String> rhs) => [
    for (final a in lhs)
      for (final b in rhs) _titleSimilarity(a, b),
  ].fold(0, math.max);
  static ScoredTmdbMatch? _bestMatch(
    IndexedMedia item,
    List<TmdbCandidate> results,
    Map<int, List<String>> matchedQueries,
  ) {
    ScoredTmdbMatch? best;
    final local = [
      ..._titles(item.title),
      if (item.originalTitle != null) ..._titles(item.originalTitle!),
    ];
    for (final candidate in results) {
      final remote = [
        ..._titles(candidate.title),
        if (candidate.originalTitle != null)
          ..._titles(candidate.originalTitle!),
      ];
      var score = math.max(
        _best(local, remote),
        .98 *
            _best((matchedQueries[candidate.id] ?? []).expand(_titles), remote),
      );
      if (item.year != null && candidate.year != null) {
        if (item.year == candidate.year) {
          score += .075;
        } else if ((item.year! - candidate.year!).abs() > 1) {
          score -= .16;
        }
      }
      score = score.clamp(0, 1);
      if (best == null || score > best.confidence) {
        best = (candidate: candidate, confidence: score);
      }
    }
    if (best != null &&
        results.length == 1 &&
        (matchedQueries[best.candidate.id]?.isNotEmpty ?? false) &&
        best.confidence >= .28) {
      return (
        candidate: best.candidate,
        confidence: math.max(best.confidence, .50),
      );
    }
    return best;
  }

  /// Keep edit-distance work away from the Flutter UI isolate. This static
  /// boundary captures only value objects, never a repository or HTTP client.
  static Future<ScoredTmdbMatch?> bestAsync(
    IndexedMedia item,
    List<TmdbCandidate> results,
    Map<int, List<String>> matchedQueries,
    Set<int> singletonIDs,
    TmdbMatchTolerance tolerance,
  ) => Isolate.run(
    () => best(item, results, matchedQueries, singletonIDs, tolerance),
  );

  static ScoredTmdbMatch? best(
    IndexedMedia item,
    List<TmdbCandidate> results,
    Map<int, List<String>> matchedQueries,
    Set<int> singletonIDs,
    TmdbMatchTolerance tolerance,
  ) {
    final best = _bestMatch(item, results, matchedQueries);
    ScoredTmdbMatch? singleton;
    for (final result in results.where((r) => singletonIDs.contains(r.id))) {
      final scored = _bestMatch(item, [result], matchedQueries)!;
      if (singleton == null || scored.confidence >= singleton.confidence) {
        singleton = scored;
      }
    }
    if (singleton != null &&
        singleton.confidence >= (singletonIDs.length == 1 ? 0 : .30)) {
      final distinctWins =
          best != null &&
          best.candidate.id != singleton.candidate.id &&
          best.confidence >= tolerance.videoThreshold &&
          singleton.confidence < best.confidence * .82;
      if (!distinctWins) {
        return (
          candidate: singleton.candidate,
          confidence: math.max(singleton.confidence, .52),
        );
      }
    }
    return best;
  }
}
