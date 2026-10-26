import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../domain/online_subtitle.dart';
import 'online_subtitle_payload.dart';

class OnlineSubtitleStore {
  /// Original sidecar name, never the provider's filename or archive member
  /// path. A fully downloaded/validated file replaces a prior sidecar atomically.
  Future<String> save(
    OnlineSubtitlePayload payload,
    String path,
    ScanCancellation token,
  ) async {
    token.check();
    OnlineSubtitlePayload.validateText(payload.bytes, payload.extension);
    File? staged;
    Directory? staging;
    try {
      final target = File(path);
      // Do not follow a preexisting sidecar link to another file/directory.
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const FileSystemException('Invalid subtitle target');
      }
      staging = await target.parent.createTemp('.reelnest-subtitle-');
      staged = File(p.join(staging.path, 'subtitle.part'));
      await staged.writeAsBytes(payload.bytes, flush: true);
      token.check();
      // Recheck before publishing; a failure never deletes the existing file.
      final latest = await FileSystemEntity.type(path, followLinks: false);
      if (latest != FileSystemEntityType.notFound &&
          latest != FileSystemEntityType.file) {
        throw const FileSystemException('Subtitle target changed');
      }
      await staged.rename(path);
      return path;
    } on ScanCancelled {
      rethrow;
    } catch (_) {
      throw const OnlineSubtitleFailure('字幕保存失败，请检查视频目录的权限或磁盘空间。');
    } finally {
      try {
        if (staged != null && await staged.exists()) await staged.delete();
      } catch (_) {}
      try {
        await staging?.delete();
      } catch (_) {}
    }
  }
}
