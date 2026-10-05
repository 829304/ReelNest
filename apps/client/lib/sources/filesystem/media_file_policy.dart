import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../domain/media_source.dart';
import '../../domain/source_media_type.dart';

/// Port of FilenameParser.isMediaFile and MediaScanner.minimumFileSize.
/// This decides scan eligibility only; it does not replace metadata parsing.
abstract final class MediaFilePolicy {
  static const videoExtensions = {
    'mp4',
    'mkv',
    'mov',
    'avi',
    'm4v',
    'wmv',
    'flv',
    'webm',
    'ts',
    'm2ts',
    'mts',
    'rmvb',
    'rm',
    'mpg',
    'mpeg',
    '3gp',
    '3g2',
    'vob',
    'ogv',
    'mxf',
    'divx',
    'f4v',
  };
  static const audioExtensions = {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'aiff',
    'aif',
    'alac',
    'ogg',
    'opus',
    'ape',
    'caf',
    'mka',
  };
  static const imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'gif',
    'bmp',
    'avif',
    'jfif',
    'raw',
    'dng',
    'cr2',
    'nef',
    'arw',
    'rw2',
    'orf',
  };

  static String _extension(String path) =>
      p.extension(path).toLowerCase().replaceFirst('.', '');
  static bool isAudio(String path) =>
      audioExtensions.contains(_extension(path));
  static bool isImage(String path) =>
      imageExtensions.contains(_extension(path));
  static bool isVideo(String path) =>
      videoExtensions.contains(_extension(path));

  static bool accepts(String path, SourceMediaType type) => switch (type) {
    SourceMediaType.photo => isImage(path) || isVideo(path),
    SourceMediaType.music => isAudio(path),
    SourceMediaType.auto => isAudio(path) || isVideo(path),
    _ => isVideo(path),
  };

  static int minimumBytes(String path, MediaSource source) {
    if (source.mediaType == SourceMediaType.photo) return 0;
    return isAudio(path)
        ? math.min(source.minimumFileSize, 512 * 1024)
        : source.minimumFileSize;
  }
}
