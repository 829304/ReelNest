import 'package:path/path.dart' as p;

import '../../../player/video_tracks.dart';

/// TrackLanguageMatcher.swift: metadata before title/filename, script-aware
/// Chinese matching, then selected track and lower mpv ID as tie breakers.
abstract final class TrackLanguageMatcher {
  static VideoTrack? best(List<VideoTrack> tracks, String language) {
    final ranked = <({VideoTrack track, int score})>[];
    for (final track in tracks) {
      final score = [
        _score(track.language, language),
        _score(track.title, language) - 8,
        _score(
              track.externalFilename == null
                  ? null
                  : p.basename(track.externalFilename!),
              language,
            ) -
            10,
      ].reduce((a, b) => a > b ? a : b);
      if (score > 0) ranked.add((track: track, score: score));
    }
    ranked.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      if (a.track.selected != b.track.selected) {
        return a.track.selected ? -1 : 1;
      }
      return a.track.id.compareTo(b.track.id);
    });
    return ranked.isEmpty ? null : ranked.first.track;
  }

  static String _normalize(String text) =>
      text.trim().toLowerCase().replaceAll(RegExp(r'[_\. ]'), '-');
  static int _score(String? text, String preference) {
    final preferred = _identities(_normalize(preference));
    if (preferred.isEmpty || text == null || text.trim().isEmpty) return 0;
    final normalized = _normalize(text);
    var best = 0;
    for (final candidate in _identities(normalized)) {
      final wanted = preferred.first;
      if (candidate.base != wanted.base) continue;
      final int score;
      if (normalized == _normalize(preference)) {
        score = 120;
      } else if (candidate.script != null && wanted.script != null) {
        score = candidate.script == wanted.script
            ? 105
            : (candidate.base == 'zh' ? 62 : 0);
      } else {
        score = 88;
      }
      if (score > best) best = score;
    }
    return best;
  }

  static List<({String base, String? script})> _identities(String text) {
    final result = <({String base, String? script})>[];
    final tokens = text
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((s) => s.isNotEmpty)
        .toSet();
    bool token(List<String> values) => values.any(tokens.contains);
    bool contains(List<String> values) => values.any(text.contains);
    void add(String base, [String? script]) {
      final id = (base: base, script: script);
      if (!result.contains(id)) result.add(id);
    }

    if (contains(['简', 'simplified', 'zh-cn', 'zh-hans', 'zh-sg']) ||
        token(['chs', 'sc', 'cn'])) {
      add('zh', 'hans');
    }
    if (contains(['繁', 'traditional', 'zh-tw', 'zh-hk', 'zh-mo', 'zh-hant']) ||
        token(['cht', 'tc', 'tw', 'hk'])) {
      add('zh', 'hant');
    }
    if (contains(['中文', '汉语', '漢語', '普通话', '國語', '国语', 'mandarin']) ||
        token(['zh', 'zho', 'chi', 'cmn', 'chinese'])) {
      add('zh');
    }
    if (token(['en', 'eng']) || text.contains('english')) add('en');
    if (token(['ja', 'jpn', 'jp']) ||
        contains(['japanese', '日本語', '日语', '日文'])) {
      add('ja');
    }
    if (token(['ko', 'kor', 'kr']) || contains(['korean', '한국어', '韩语', '韓語'])) {
      add('ko');
    }
    const aliases = {
      'fre': 'fr',
      'fra': 'fr',
      'french': 'fr',
      'ger': 'de',
      'deu': 'de',
      'german': 'de',
      'spa': 'es',
      'spanish': 'es',
      'por': 'pt',
      'portuguese': 'pt',
      'ita': 'it',
      'italian': 'it',
      'rus': 'ru',
      'russian': 'ru',
      'vie': 'vi',
      'vietnamese': 'vi',
      'tha': 'th',
      'thai': 'th',
      'ind': 'id',
      'indonesian': 'id',
      'msa': 'ms',
      'may': 'ms',
      'malay': 'ms',
    };
    for (final value in tokens) {
      if (value.length == 2) {
        add(value);
      } else if (aliases[value] != null) {
        add(aliases[value]!);
      }
    }
    return result;
  }
}
