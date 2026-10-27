import 'dart:convert';

import 'package:xml/xml.dart';

import '../emby/emby_item.dart';
import '../../domain/media_source.dart';

String? plexText(XmlElement node, String key) {
  final value = node.getAttribute(key)?.trim();
  return value == null || value.isEmpty ? null : value;
}

int? plexInt(XmlElement node, String key) =>
    int.tryParse(plexText(node, key) ?? '');

/// Persist only an image identity, never a signed URL or an authentication token.
String? plexArtworkReference(String? value, Uri server) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.hasScheme && !{'http', 'https'}.contains(uri.scheme)) ||
      uri.hasAuthority && !uri.hasScheme ||
      uri.pathSegments.any((s) => s == '..' || s.contains('\\'))) {
    return null;
  }
  final safe = uri
      .replace(
        queryParameters: {
          for (final entry in uri.queryParameters.entries)
            if (!{
              'x-plex-token',
              'api_key',
              'apikey',
              'token',
            }.contains(entry.key.toLowerCase()))
              entry.key: entry.value,
        },
      )
      .toString();
  return 'plex-artwork:${base64Url.encode(utf8.encode(safe))}';
}

String? plexProviderId(XmlElement node, String scheme) {
  for (final value in [
    ...node.findElements('Guid').map((e) => e.getAttribute('id')),
    node.getAttribute('guid'),
  ].whereType<String>()) {
    final match = RegExp(
      '^${RegExp.escape(scheme)}://([^?]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (match != null) return match[1];
  }
  return null;
}

double? _rating(String? text) {
  final rating = double.tryParse(text ?? '');
  return rating != null && rating.isFinite && rating > 0 && rating <= 10
      ? rating
      : null;
}

/// Translate protocol fields at the boundary; the shared index remains token-free.
EmbyItem plexItem(XmlElement node, Uri server) {
  final id = plexText(node, 'ratingKey');
  final name = plexText(node, 'title');
  if (id == null || name == null) {
    throw const SourceFailure('Plex 媒体条目标识或标题无效。');
  }
  final type = switch (plexText(node, 'type')) {
    'movie' => 'Movie',
    'show' => 'Series',
    'episode' => 'Episode',
    'track' => 'Audio',
    _ => 'Unsupported',
  };
  final poster = plexArtworkReference(
    plexText(node, 'thumb') ?? plexText(node, 'grandparentThumb'),
    server,
  );
  final backdrop = plexArtworkReference(plexText(node, 'art'), server);
  final duration = plexInt(node, 'duration');
  final position = (plexInt(node, 'viewOffset') ?? 0).clamp(0, 1 << 53);
  final lastViewed = plexInt(node, 'lastViewedAt');
  final people = <Map<String, dynamic>>[];
  for (final tag in ['Role', 'Director', 'Writer', 'Producer']) {
    for (final person in node.findElements(tag)) {
      final personName = plexText(person, 'tag');
      if (personName == null) continue;
      final personId = plexText(person, 'id');
      final image = plexArtworkReference(plexText(person, 'thumb'), server);
      people.add({
        'Name': personName,
        'Type': tag == 'Role' ? 'Actor' : tag,
        'Role': plexText(person, 'role'),
        'Id': personId == null
            ? 'name:$personName'
            : '${tag == 'Role' ? 'actor' : tag.toLowerCase()}:$personId',
        'PrimaryImageTag': ?image,
        'ImageReference': ?image,
      });
    }
  }
  final mediaSources = <Map<String, dynamic>>[];
  for (final media in node.findElements('Media')) {
    for (final part in media.findElements('Part')) {
      mediaSources.add({
        'Id': plexText(part, 'id'),
        'Container':
            plexText(part, 'container') ?? plexText(media, 'container'),
        'Size': plexInt(part, 'size'),
        'Bitrate': plexInt(media, 'bitrate') == null
            ? null
            : plexInt(media, 'bitrate')! * 1000,
        'MediaStreams': [
          // Some list responses omit Stream children; retain the media summary.
          {
            'Type': 'Video',
            'Codec': plexText(media, 'videoCodec'),
            'Width': plexInt(media, 'width'),
            'Height': plexInt(media, 'height'),
          },
          {'Type': 'Audio', 'Codec': plexText(media, 'audioCodec')},
          for (final stream in part.findElements('Stream'))
            {
              'Index': plexInt(stream, 'id') ?? plexInt(stream, 'index'),
              'Type': switch (plexInt(stream, 'streamType')) {
                1 => 'Video',
                2 => 'Audio',
                3 => 'Subtitle',
                _ => 'Unknown',
              },
              'Codec': plexText(stream, 'codec'),
              'Width': plexInt(stream, 'width'),
              'Height': plexInt(stream, 'height'),
              'Language':
                  plexText(stream, 'languageCode') ??
                  plexText(stream, 'language'),
              'DisplayTitle':
                  plexText(stream, 'displayTitle') ?? plexText(stream, 'title'),
              if (plexText(stream, 'key') != null)
                'DeliveryUrl': plexText(stream, 'key'),
            },
        ],
      });
    }
  }
  return EmbyItem.fromJson({
    'Id': id,
    'Name': name,
    'Type': type,
    'OriginalTitle': plexText(node, 'originalTitle'),
    'Overview': plexText(node, 'summary'),
    'ProductionYear': plexInt(node, 'year'),
    'ParentIndexNumber': plexInt(node, 'parentIndex'),
    'IndexNumber': plexInt(node, 'index'),
    'SeriesId': type == 'Episode'
        ? plexText(node, 'grandparentRatingKey')
        : null,
    'SeriesName': type == 'Episode' ? plexText(node, 'grandparentTitle') : null,
    'RunTimeTicks': duration == null
        ? null
        : duration.clamp(0, 1 << 53) * 10000,
    'InitialUserRating': _rating(plexText(node, 'userRating')) == null
        ? null
        : _rating(plexText(node, 'userRating'))! / 2,
    'CommunityRating':
        _rating(plexText(node, 'audienceRating')) ??
        _rating(plexText(node, 'rating')),
    'UserData': {
      'PlaybackPositionTicks': position * 10000,
      'PlayedPercentage': duration != null && duration > 0
          ? (position * 100 / duration).clamp(0, 100)
          : null,
      'Played': (plexInt(node, 'viewCount') ?? 0) > 0,
      'IsFavorite': false,
      if (lastViewed != null && lastViewed > 0 && lastViewed < 8640000000000)
        'LastPlayedDate': DateTime.fromMillisecondsSinceEpoch(
          lastViewed * 1000,
          isUtc: true,
        ).toIso8601String(),
    },
    'Genres': node
        .findElements('Genre')
        .map((e) => plexText(e, 'tag'))
        .whereType<String>()
        .toList(),
    'Artists': [
      if (plexText(node, 'grandparentTitle') != null && type == 'Audio')
        plexText(node, 'grandparentTitle'),
    ],
    'Album': type == 'Audio' ? plexText(node, 'parentTitle') : null,
    'MediaSources': mediaSources,
    'ImageTags': {'Primary': ?poster},
    'BackdropImageTags': [?backdrop],
    'PosterReference': poster,
    'BackdropReference': backdrop,
    'SupportsQualitySelection': false,
    'People': people,
    'ProviderIds': {
      'Tmdb': plexProviderId(node, 'tmdb'),
      'Imdb': plexProviderId(node, 'imdb'),
    },
    'OfficialRating': plexText(node, 'contentRating'),
    'Studios': [
      if (plexText(node, 'studio') != null) {'Name': plexText(node, 'studio')},
    ],
    'ProductionLocations': node
        .findElements('Country')
        .map((e) => plexText(e, 'tag'))
        .whereType<String>()
        .toList(),
    'PremiereDate': plexText(node, 'originallyAvailableAt'),
  });
}
