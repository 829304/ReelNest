import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'remote_media_metadata.dart';

/// EmbyService.normalizedProviderRating / seedUserRating.
/// Community scores stay on the server's 10-point scale.
abstract final class RemoteRatingPolicy {
  static double? normalizedProviderRating(num? value) {
    final rating = value?.toDouble();
    return rating != null && rating.isFinite && rating > 0 && rating <= 10
        ? rating
        : null;
  }

  static double? initialUserRating(RemoteMediaMetadata? metadata) {
    final rating = metadata?.initialUserRating;
    return rating != null && rating.isFinite && rating > 0 && rating <= 5
        ? rating
        : seedUserRating(metadata?.rating);
  }

  static double? seedUserRating(num? value) {
    final rating = normalizedProviderRating(value);
    return rating == null ? null : (rating / 2).round().clamp(1, 5).toDouble();
  }
}

/// RemoteLibraryClassificationPolicy.swift. Ordered substring rules are
/// deliberate: e.g. anime movies precede movies, home movies precede movies.
abstract final class RemoteLibraryClassificationPolicy {
  static String inferredMediaType({
    required String type,
    String? libraryName,
    Iterable<String> genres = const [],
    String? collectionType,
  }) =>
      inferFromLibraryName(libraryName) ??
      inferFromGenre(genres.join(', ')) ??
      inferFromCollectionType(collectionType) ??
      (type == 'episode' ? 'tvShow' : type);

  static String? inferFromLibraryName(String? value) => _match(value, _names);
  static String? inferFromGenre(String? value) => _match(value, _genres);
  static String? inferFromCollectionType(String? value) {
    final text = _normalize(value);
    if (text.contains('movies') || text == 'movie') return 'movie';
    if (text.contains('homevideos') ||
        text.contains('home video') ||
        text.contains('homevideo')) {
      return 'homeVideo';
    }
    if (text.contains('music')) return 'music';
    if (text.contains('tvshows') || text.contains('series')) return 'tvShow';
    return null;
  }

  static String? _match(String? value, List<(String, List<String>)> rules) {
    final text = _normalize(value);
    for (final (type, keywords) in rules) {
      if (keywords.any(text.contains)) return type;
    }
    return null;
  }

  static final _accents = RegExp(r'[\u0300-\u036f]');
  static String _normalize(String? value) {
    if (value == null) return '';
    var text = value;
    try {
      text = Uri.decodeComponent(text);
    } on ArgumentError {
      // Foundation returns the original text if percent decoding fails.
    } on FormatException {
      // Invalid percent-encoded UTF-8 has the same fallback.
    }
    // Fold full-width ASCII without compatibility-folding unrelated symbols.
    text = String.fromCharCodes(
      text.runes.map(
        (rune) => rune >= 0xff01 && rune <= 0xff5e
            ? rune - 0xfee0
            : rune == 0x3000
            ? 0x20
            : rune,
      ),
    );
    return unorm.nfd(text).replaceAll(_accents, '').toLowerCase();
  }

  static const _names = <(String, List<String>)>[
    (
      'anime',
      [
        '动漫',
        '动画',
        '番剧',
        '新番',
        '国漫',
        '日漫',
        'anime',
        'animation',
        'bangumi',
        'cartoon',
      ],
    ),
    ('documentary', ['纪录', '纪实', 'documentary', 'docu']),
    (
      'variety',
      ['综艺', '真人秀', '脱口秀', 'variety', 'reality', 'talk show', 'talkshow'],
    ),
    (
      'homeVideo',
      [
        '其他视频',
        '家庭录像',
        '家庭视频',
        '家庭影像',
        '自拍视频',
        '生活录像',
        'home video',
        'homevideo',
        'homevideos',
        'home movie',
        'home movies',
        'other video',
        'other videos',
      ],
    ),
    ('movie', ['电影', '影片', '影院', 'movie', 'movies', 'film', 'cinema']),
    (
      'tvShow',
      [
        '电视剧',
        '剧集',
        '连续剧',
        '美剧',
        '日剧',
        '韩剧',
        '英剧',
        '华语剧',
        'tv',
        'series',
        'drama',
        'shows',
      ],
    ),
  ];
  static const _genres = <(String, List<String>)>[
    ('anime', ['动画', '动漫', 'animation', 'anime']),
    ('documentary', ['纪录', 'documentary']),
    ('variety', ['综艺', '真人秀', '脱口秀', 'reality', 'talk', 'variety']),
    (
      'homeVideo',
      [
        '其他视频',
        '家庭录像',
        '家庭视频',
        'home video',
        'homevideo',
        'home movie',
        'other video',
      ],
    ),
  ];
}
