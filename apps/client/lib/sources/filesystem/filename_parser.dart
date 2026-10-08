import 'package:characters/characters.dart';
import 'package:path/path.dart' as p;

import '../../domain/source_media_type.dart';

enum ParsedMediaKind { movie, episode }

class ParsedMediaFile {
  const ParsedMediaFile({
    required this.kind,
    required this.title,
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.seriesDirectoryPath,
  });

  final ParsedMediaKind kind;
  final String title;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? seriesDirectoryPath;
}

/// Translation of MediaLibCore/Services/FilenameParser.swift. Path semantics
/// default to the host; a context lets the same fixtures cover all desktops.
class FilenameParser {
  FilenameParser({p.Context? paths}) : _paths = paths ?? p.context;

  final p.Context _paths;

  static final _seasonEpisode = RegExp(
    r'(.*?)[\s._-]*S(\d{1,2})[\s._-]*E(\d{1,3})',
    caseSensitive: false,
  );
  static final _chineseEpisode = RegExp(
    r'(.*?)[\s._-]*第\s*(\d{1,2})\s*[季部][\s._-]*第\s*(\d{1,3})\s*[集话話]',
  );
  static final _episode = RegExp(
    r'(.*?)[\s._-]*(?:EP|E)(\d{1,3})(?:\D|$)',
    caseSensitive: false,
  );
  static final _number = RegExp(
    r'(.*?)(?:^|[\s._-])(\d{1,3})(?:\D|$)',
    caseSensitive: false,
  );
  static final _season = RegExp(r'Season\s*(\d{1,2})', caseSensitive: false);
  static final _chineseSeason = RegExp(r'第\s*(\d{1,2})\s*[季部]');
  static final _year = RegExp(r'(?:^|\D)(19\d{2}|20\d{2})(?:\D|$)');
  static final _brackets = RegExp(r'\[[^\]]*\]|\([^\)]*\)|【[^】]*】');
  static final _yearSuffix = RegExp(r'\s*[\(\[]?(19\d{2}|20\d{2})[\)\]]?\s*$');
  static final _movieYear = RegExp(
    r'[\s._-]*[\(\[]?(?<![\p{L}\d])(19\d{2}|20\d{2})(?![\p{L}\d])[\)\]]?',
    caseSensitive: false,
    unicode: true,
  );
  static final _resolution = RegExp(r'^\d{3,4}p$');
  static final _emojiPresentation = RegExp(
    // Dart 3.13.5's lint rejects this binary Unicode property, although both
    // the Dart VM and Flutter VM accept it. Covered by emoji/digit fixtures.
    // ignore: valid_regexps
    r'\p{Emoji_Presentation}',
    unicode: true,
  );
  static final _separators = RegExp(r'[\s._]+');
  static const _noise = {
    '1080p',
    '2160p',
    '720p',
    '480p',
    '4k',
    '8k',
    'bluray',
    'blu-ray',
    'bdrip',
    'web-dl',
    'webdl',
    'webrip',
    'hdr',
    'hdr10',
    'dv',
    'dolby',
    'vision',
    'x264',
    'x265',
    'h264',
    'h265',
    'hevc',
    'avc',
    'aac',
    'dts',
    'truehd',
    'atmos',
    'chs',
    'cht',
    'eng',
    'jpn',
    'kor',
    '字幕',
    '中字',
    '国配',
    '双语',
  };

  ParsedMediaFile parse(
    String path, {
    SourceMediaType preferredType = SourceMediaType.auto,
    String? sourcePath,
  }) {
    final filename = _paths.basenameWithoutExtension(path);
    final parent = _paths.dirname(path);
    final parentName = _paths.basename(parent);
    final grandParentName = _paths.basename(_paths.dirname(parent));
    final directory = seriesDirectory(path, sourcePath: sourcePath);
    final directoryTitle = directory == null
        ? ''
        : _cleanTitle(_paths.basename(directory).replaceAll(_yearSuffix, ''));

    if (preferredType != SourceMediaType.movie) {
      final normalized = _normalize(filename);
      final fallbackName = _seasonNumber(parentName) != null
          ? grandParentName
          : parentName;
      for (final pattern in [_seasonEpisode, _chineseEpisode, _episode]) {
        final match = pattern.firstMatch(normalized);
        if (match == null) continue;
        final prefix = match.group(1)!.trim();
        final explicitSeason = match.groupCount == 3;
        return ParsedMediaFile(
          kind: ParsedMediaKind.episode,
          title: directoryTitle.isNotEmpty
              ? directoryTitle
              : _cleanTitle(prefix.isEmpty ? fallbackName : prefix),
          seasonNumber: explicitSeason
              ? int.parse(match.group(2)!)
              : _seasonNumber(parentName) ?? 1,
          episodeNumber: int.parse(match.group(explicitSeason ? 3 : 2)!),
          seriesDirectoryPath: directory,
        );
      }
      if (_isSeasonFolder(parentName)) {
        final match = _number.firstMatch(normalized);
        if (match != null) {
          return ParsedMediaFile(
            kind: ParsedMediaKind.episode,
            title: directoryTitle.isNotEmpty
                ? directoryTitle
                : _cleanTitle(fallbackName),
            seasonNumber: _seasonNumber(parentName) ?? 1,
            episodeNumber: int.parse(match.group(2)!),
            seriesDirectoryPath: directory,
          );
        }
      }
    }

    final normalized = _normalize(filename);
    var title = _cleanTitle(normalized.replaceAll(_movieYear, ' '));
    // Swift String.count counts grapheme clusters, not UTF-16 code units.
    if (title.characters.length <= 2) {
      final keepingYear = _cleanTitle(normalized);
      title = keepingYear.isEmpty ? _cleanTitle(parentName) : keepingYear;
    }
    return ParsedMediaFile(
      kind: ParsedMediaKind.movie,
      title: title,
      year: _lastYear(normalized) ?? _lastYear(parentName),
    );
  }

  String? seriesDirectory(String path, {String? sourcePath}) {
    final parent = _paths.normalize(_paths.dirname(path));
    final candidate = _isSeasonFolder(_paths.basename(parent))
        ? _paths.normalize(_paths.dirname(parent))
        : parent;
    // The selected root itself is not a show folder. Context.equals also
    // respects Windows path case, unlike a POSIX string comparison.
    return sourcePath != null && _paths.equals(candidate, sourcePath)
        ? null
        : candidate;
  }

  static int? _seasonNumber(String value) {
    final match = _season.firstMatch(value) ?? _chineseSeason.firstMatch(value);
    return match == null ? null : int.parse(match.group(1)!);
  }

  static bool _isSeasonFolder(String value) =>
      _seasonNumber(value) != null ||
      value.toLowerCase().contains('specials') ||
      value.toLowerCase().contains('season');

  static int? _lastYear(String value) {
    final matches = _year.allMatches(value);
    return matches.isEmpty ? null : int.parse(matches.last.group(1)!);
  }

  static String _normalize(String value) =>
      value.replaceAll('　', ' ').replaceAll('.', ' ').replaceAll('_', ' ');

  static String _cleanTitle(String value) => value
      .replaceAll(_brackets, ' ')
      .replaceAll('-', ' ')
      .split(_separators)
      .map((token) => token.replaceAll(_emojiPresentation, ''))
      .where(
        (token) =>
            token.isNotEmpty &&
            !_noise.contains(token.toLowerCase()) &&
            !_resolution.hasMatch(token.toLowerCase()),
      )
      .join(' ')
      .trim();
}
