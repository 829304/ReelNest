import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// LocalMetadataService.swift: local sidecars only, with the original candidate
/// order and tag semantics (not a general-purpose Kodi XML importer).
class LocalMetadata {
  const LocalMetadata({
    this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterPath,
    this.backdropPath,
  });

  final String? title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
}

class LocalMetadataService {
  static final _decimalInteger = RegExp(r'^[+-]?[0-9]+$');
  static final _tags = {
    for (final name in ['title', 'originaltitle', 'year', 'plot', 'overview'])
      name: RegExp('<$name>\\s*([^<]+)\\s*</$name>', caseSensitive: false),
  };
  static final _posterNames = _artworkNames(['poster', 'cover', 'folder']);
  static final _backdropNames = _artworkNames([
    'fanart',
    'backdrop',
    'background',
  ]);

  static List<String> _artworkNames(List<String> stems) => [
    for (final stem in stems)
      for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'heic']) '$stem.$ext',
  ];

  Future<LocalMetadata> forFile(
    String path, {
    required bool readNFO,
    required bool preferLocalArtwork,
  }) => _read(
    p.dirname(path),
    [
      p.setExtension(path, '.nfo'),
      p.join(p.dirname(path), 'movie.nfo'),
      p.join(p.dirname(path), 'tvshow.nfo'),
    ],
    readNFO: readNFO,
    preferLocalArtwork: preferLocalArtwork,
  );

  Future<LocalMetadata> forDirectory(
    String directory, {
    required bool readNFO,
    required bool preferLocalArtwork,
  }) => _read(
    directory,
    [p.join(directory, 'tvshow.nfo'), p.join(directory, 'movie.nfo')],
    readNFO: readNFO,
    preferLocalArtwork: preferLocalArtwork,
  );

  Future<LocalMetadata> _read(
    String directory,
    List<String> candidates, {
    required bool readNFO,
    required bool preferLocalArtwork,
  }) async {
    final text = readNFO ? await _readNfo(candidates) : const LocalMetadata();
    return LocalMetadata(
      title: text.title,
      originalTitle: text.originalTitle,
      year: text.year,
      overview: text.overview,
      posterPath: preferLocalArtwork
          ? await _firstExisting([
              for (final name in _posterNames) p.join(directory, name),
            ])
          : null,
      backdropPath: preferLocalArtwork
          ? await _firstExisting([
              for (final name in _backdropNames) p.join(directory, name),
            ])
          : null,
    );
  }

  Future<String?> _firstExisting(List<String> candidates) async {
    for (final path in candidates) {
      try {
        if (await FileSystemEntity.type(path) !=
            FileSystemEntityType.notFound) {
          return path;
        }
      } on FileSystemException {
        // Foundation.fileExists returns false if the candidate cannot be stat'ed.
      }
    }
    return null;
  }

  Future<LocalMetadata> _readNfo(List<String> candidates) async {
    final path = await _firstExisting(candidates);
    if (path == null) return const LocalMetadata();
    // Original stops at the first existing candidate, even if unreadable or
    // malformed. Do not merge fields from lower-priority sidecars.
    try {
      final raw = await File(path).readAsString();
      // Keep oversized/malformed tag parsing off the Flutter UI isolate.
      return raw.length > 64 * 1024
          ? await Isolate.run(() => _parse(raw))
          : _parse(raw);
    } on FileSystemException {
      return const LocalMetadata();
    } on FormatException {
      return const LocalMetadata();
    }
  }

  static LocalMetadata _parse(String raw) {
    String? tag(String name) {
      final value = _tags[name]!.firstMatch(raw)?.group(1)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final rawYear = tag('year') ?? '';
    // Swift Int.init uses decimal here; Dart int.tryParse also accepts 0x.
    final year = _decimalInteger.hasMatch(rawYear)
        ? int.tryParse(rawYear)
        : null;
    return LocalMetadata(
      title: tag('title'),
      originalTitle: tag('originaltitle'),
      year: year != null && year > 0 ? year : null,
      overview: tag('plot') ?? tag('overview'),
    );
  }
}
