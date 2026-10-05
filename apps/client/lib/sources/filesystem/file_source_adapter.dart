import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/media_source.dart';
import '../source_adapter.dart';
import 'media_file_policy.dart';

/// Read-only enumeration. Never follows directory links or writes media files.
class FileSourceAdapter implements SourceAdapter {
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
  Stream<IndexedMedia> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    cancellation.check();
    final root = await validateLocation(source.location);
    final pending = <Directory>[Directory(root)];
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
          final stat = await entity.stat();
          if (stat.type != FileSystemEntityType.file) {
            throw const SourceFailure('扫描时文件发生变化，请重新扫描。');
          }
          if (stat.size < MediaFilePolicy.minimumBytes(entity.path, source)) {
            continue;
          }
          // Metadata parsing/series grouping are migrated separately. Do not
          // confuse this provisional file kind with source classification.
          final type = MediaFilePolicy.isAudio(entity.path)
              ? 'music'
              : MediaFilePolicy.isImage(entity.path)
              ? 'photo'
              : 'homeVideo';
          final relative = p.relative(entity.path, from: root);
          // Use a portable relative key; remounting the root preserves identity.
          final id = p.posix.joinAll(p.split(relative));
          yield IndexedMedia(
            identity: (sourceId: source.id, localId: id),
            title: p.basenameWithoutExtension(entity.path),
            type: type,
            bytes: stat.size,
            modified: stat.modified.toUtc(),
          );
        }
      }
      // Recheck the root before allowing the repository to publish this scan.
      cancellation.check();
      await validateLocation(root);
    } on FileSystemException {
      throw const SourceFailure('扫描未完成：目录或文件不可读，已保留上次索引。');
    }
  }
}
