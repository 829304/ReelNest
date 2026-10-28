import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../sources/filesystem/filename_parser.dart';

/// Original VideoMetadataSidecarPolicy. Paths alone never grant write access.
class VideoNfoPolicy {
  static Future<String?> resolve(
    MediaSource source,
    IndexedMedia item,
    List<IndexedMedia> children,
  ) async {
    if (!source.options.preferMetadataWriteToSource ||
        !source.options.includeInMetadataFetch ||
        !source.kind.isFileSource ||
        source.mediaType == SourceMediaType.privateCollection ||
        source.mediaType == SourceMediaType.photo ||
        item.remote != null) {
      return null;
    }
    final root = source.location;
    if (!p.isAbsolute(root) ||
        !p.equals(
          await Directory(root).resolveSymbolicLinks(),
          p.normalize(root),
        )) {
      throw const SourceFailure('媒体源路径身份不可确认，已拒绝写回。');
    }
    Future<String> filePath(IndexedMedia value) async {
      final key = value.identity.localId;
      if (value.identity.sourceId != source.id ||
          p.posix.isAbsolute(key) ||
          p.windows.isAbsolute(key) ||
          key.contains('\\') ||
          p.posix.split(key).contains('..')) {
        throw const SourceFailure('媒体路径超出来源目录，已拒绝写回。');
      }
      final path = p.join(root, p.joinAll(p.posix.split(key)));
      if (!p.isWithin(root, path) ||
          !p.equals(
            await File(path).resolveSymbolicLinks(),
            p.normalize(path),
          ) ||
          await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const SourceFailure('媒体文件身份或路径已改变，已拒绝写回。');
      }
      return path;
    }

    if (!item.isSeries) {
      if (item.type == 'episode' ||
          item.type == 'music' ||
          item.type == 'photo') {
        return null;
      }
      return p.setExtension(await filePath(item), '.nfo');
    }
    String? showRoot;
    final episodes = children
        .where((child) => child.type == 'episode')
        .toList();
    if (episodes.isEmpty) return null;
    for (final child in episodes) {
      if (child.parentId != item.identity.localId) return null;
      final path = await filePath(child);
      final candidate = FilenameParser()
          .parse(path, preferredType: source.mediaType, sourcePath: root)
          .seriesDirectoryPath;
      if (candidate == null ||
          p.equals(candidate, root) ||
          !p.isWithin(root, candidate)) {
        return null;
      }
      if (showRoot != null && !p.equals(showRoot, candidate)) return null;
      showRoot = candidate;
    }
    return p.join(showRoot!, 'tvshow.nfo');
  }
}
