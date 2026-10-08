import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../domain/media_source.dart';
import '../../domain/source_media_type.dart';
import '../../domain/source_scan.dart';
import '../source_adapter.dart';
import 'filename_parser.dart';
import 'local_metadata_service.dart';
import 'media_file_policy.dart';

/// Read-only enumeration. Never follows directory links or writes media files.
class FileSourceAdapter implements SourceAdapter {
  final _parser = FilenameParser();
  final _metadata = LocalMetadataService();
  static final _trackPrefix = RegExp(r'^\d{1,3}\s*[-_.]\s*');

  // MediaScanner.musicTitle: used only until audio tags are available.
  String _musicTitle(String path) {
    final filename = p.basenameWithoutExtension(path);
    final cleaned = filename
        .replaceFirst(_trackPrefix, '')
        .replaceAll('_', ' ')
        .trim();
    return cleaned.isEmpty ? filename : cleaned;
  }

  // MediaScanner.resolvedMovieType. Episodes always use the episode kind;
  // their parent show record carries the source's series category.
  String _movieType(SourceMediaType type) => switch (type) {
    SourceMediaType.auto ||
    SourceMediaType.tvShow ||
    SourceMediaType.episode ||
    SourceMediaType.photo => 'movie',
    _ => type.storageValue,
  };

  String _seriesType(SourceMediaType type) => switch (type) {
    SourceMediaType.auto ||
    SourceMediaType.movie ||
    SourceMediaType.tvShow ||
    SourceMediaType.episode ||
    SourceMediaType.photo => 'tvShow',
    _ => type.storageValue,
  };

  String _relative(String path, String root) =>
      p.posix.joinAll(p.split(p.relative(path, from: root)));

  String? _artwork(String? path, String root) =>
      path == null ? null : _relative(path, root);

  String _seriesId(String directoryOrTitle) {
    final key = Platform.isWindows
        ? directoryOrTitle.toLowerCase()
        : directoryOrTitle;
    // No dot/extension: cannot collide with a supported file's relative key.
    return 'series:${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}';
  }

  /// FileAccessService.isReachableDirectory: existence as a directory, not
  /// a successful prior scan. Dart filesystem I/O stays off the UI isolate.
  @override
  Future<bool> isReachable(String location) async =>
      Directory(location).exists();

  @override
  Future<String> validateLocation(String location) async {
    if (!p.isAbsolute(location)) {
      throw const SourceFailure('请选择绝对路径的目录。');
    }
    try {
      final directory = Directory(location);
      // Resolve the selected root, but do not follow links discovered inside it.
      final resolved = await directory.resolveSymbolicLinks();
      await Directory(resolved).list(followLinks: false).take(1).drain<void>();
      return p.normalize(resolved);
    } on FileSystemException {
      throw const SourceFailure('目录不可访问，请检查挂载状态与读取权限。');
    }
  }

  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    cancellation.check();
    final root = await validateLocation(source.location);
    final pending = <Directory>[Directory(root)];
    final files = <File>[];
    final seriesMetadata = <String, LocalMetadata>{};
    try {
      while (pending.isNotEmpty) {
        cancellation.check();
        final directory = pending.removeLast();
        await for (final entity in directory.list(followLinks: false)) {
          cancellation.check();
          if (source.ignoreHidden && p.basename(entity.path).startsWith('.')) {
            continue;
          }
          if (entity is Directory) {
            if (source.recursive) pending.add(entity);
            continue;
          }
          if (entity is! File) continue;
          if (!MediaFilePolicy.accepts(entity.path, source.mediaType)) continue;
          files.add(entity);
        }
      }
      yield ScanCatalogued(files.length);
      for (final entity in files) {
        cancellation.check();
        ScanFileProcessed result;
        try {
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file) {
            throw const SourceFailure('扫描时文件发生变化，请重新扫描。');
          }
          if (stat.size < MediaFilePolicy.minimumBytes(entity.path, source)) {
            yield ScanFileProcessed(path: entity.path);
            continue;
          }
          // Album files bypass movie parsing; music uses its own title rules.
          final album = source.mediaType == SourceMediaType.photo;
          final music =
              source.mediaType == SourceMediaType.music ||
              (source.mediaType == SourceMediaType.auto &&
                  MediaFilePolicy.isAudio(entity.path));
          final parsed = album || music
              ? null
              : _parser.parse(
                  entity.path,
                  preferredType: source.mediaType,
                  sourcePath: root,
                );
          final type = album
              ? (MediaFilePolicy.isImage(entity.path) ? 'photo' : 'homeVideo')
              : music
              ? 'music'
              : parsed!.kind == ParsedMediaKind.episode
              ? 'episode'
              : _movieType(source.mediaType);
          final id = _relative(entity.path, root);
          final local = album || music
              ? const LocalMetadata()
              : await _metadata.forFile(
                  entity.path,
                  readNFO: source.options.readNFO,
                  preferLocalArtwork: source.options.preferLocalArtwork,
                );
          final seriesDirectory = parsed?.seriesDirectoryPath == null
              ? null
              : _relative(parsed!.seriesDirectoryPath!, root);
          IndexedMedia? parent;
          if (parsed?.kind == ParsedMediaKind.episode) {
            final directory = parsed!.seriesDirectoryPath;
            var show = const LocalMetadata();
            if (directory != null) {
              show =
                  seriesMetadata[directory] ??
                  await _metadata.forDirectory(
                    directory,
                    readNFO: source.options.readNFO,
                    preferLocalArtwork: source.options.preferLocalArtwork,
                  );
              seriesMetadata[directory] = show;
            }
            final title = show.title ?? parsed.title;
            parent = IndexedMedia(
              identity: (
                sourceId: source.id,
                localId: _seriesId(seriesDirectory ?? title),
              ),
              title: title,
              type: _seriesType(source.mediaType),
              isSeries: true,
              bytes: 0,
              modified: stat.modified.toUtc(),
              seriesDirectory: seriesDirectory,
              originalTitle: show.originalTitle,
              year: show.year,
              overview: show.overview,
              posterPath: _artwork(show.posterPath ?? local.posterPath, root),
              backdropPath: _artwork(show.backdropPath, root),
            );
          }
          cancellation.check();
          result = ScanFileProcessed(
            path: entity.path,
            parent: parent,
            item: IndexedMedia(
              identity: (sourceId: source.id, localId: id),
              title: album
                  ? p.basenameWithoutExtension(entity.path)
                  : music
                  ? _musicTitle(entity.path)
                  : parent?.title ?? local.title ?? parsed!.title,
              type: type,
              bytes: stat.size,
              modified: stat.modified.toUtc(),
              year: parent == null ? local.year ?? parsed?.year : null,
              seasonNumber: parsed?.seasonNumber,
              episodeNumber: parsed?.episodeNumber,
              seriesDirectory: seriesDirectory,
              parentId: parent?.identity.localId,
              originalTitle: parent == null ? local.originalTitle : null,
              overview: parent == null ? local.overview : null,
              posterPath: album && MediaFilePolicy.isImage(entity.path)
                  ? id
                  : _artwork(local.posterPath, root),
              backdropPath: parent == null
                  ? _artwork(local.backdropPath, root)
                  : null,
            ),
          );
        } on FileSystemException {
          result = ScanFileProcessed(
            path: entity.path,
            error: '${p.basename(entity.path)}: 文件不可读或已移除。',
          );
        } on SourceFailure catch (error) {
          result = ScanFileProcessed(
            path: entity.path,
            error: '${p.basename(entity.path)}: ${error.message}',
          );
        }
        yield result;
      }
      // Recheck the root before allowing the repository to publish this scan.
      cancellation.check();
      await validateLocation(root);
    } on FileSystemException {
      throw const SourceFailure('扫描未完成：目录不可读，已导入的文件和原有索引均已保留。');
    }
  }
}
