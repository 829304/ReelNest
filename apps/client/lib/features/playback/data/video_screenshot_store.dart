import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:path/path.dart' as p;

import '../../../storage/runtime_storage_paths.dart';
import '../domain/video_screenshot.dart';

class VideoScreenshotStore {
  VideoScreenshotStore({
    Future<Directory> Function()? directory,
    DateTime Function()? now,
  }) : _directory =
           directory ?? (() => RuntimeStoragePaths.current.screenshots()),
       _now = now ?? DateTime.now;
  final Future<Directory> Function() _directory;
  final DateTime Function() _now;

  static String filename(String title, DateTime at) {
    var clean = title
        .replaceAll(RegExp(r'[/\\:?%*|"<>\x00-\x1f]'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    var chars = clean.characters.take(64);
    // A grapheme may contain arbitrarily many combining characters. Also
    // respect filesystem component limits without splitting Unicode scalars.
    while (chars.isNotEmpty &&
        (chars.string.length > 128 || utf8.encode(chars.string).length > 224)) {
      chars = chars.skipLast(1);
    }
    clean = chars.string.trim().replaceAll(RegExp(r'[. ]+$'), '');
    if (clean.isEmpty) clean = '视频截图';
    String two(int n) => n.toString().padLeft(2, '0');
    final local = at.toLocal();
    return '$clean ${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}.${two(local.minute)}.${two(local.second)}.png';
  }

  Future<String> save(String title, Uint8List png) async {
    VideoScreenshotLimits.png(png);
    Directory? staging;
    File? reserved;
    var committed = false;
    try {
      final directory = await _directory();
      await directory.create(recursive: true);
      final base = await directory.resolveSymbolicLinks();
      staging = await Directory(base).createTemp('.capture-');
      final staged = File(p.join(staging.path, 'frame.png'));
      await staged.writeAsBytes(png, flush: true);
      final name = filename(title, _now());
      for (var n = 0; n < 10000; n++) {
        final candidate = File(
          p.join(
            base,
            n == 0 ? name : '${p.basenameWithoutExtension(name)} ($n).png',
          ),
        );
        try {
          // Exclusive reservation works across separate player processes. An
          // existing PNG, symlink or another reservation is never overwritten.
          await candidate.create(exclusive: true);
          reserved = candidate;
          break;
        } on FileSystemException {
          if (await FileSystemEntity.type(candidate.path, followLinks: false) ==
              FileSystemEntityType.notFound) {
            rethrow;
          }
        }
      }
      if (reserved == null) {
        throw const FileSystemException('Screenshot name collision');
      }
      // Publish a fully flushed PNG in one same-filesystem rename. Only our
      // own exclusive empty reservation can be replaced by this operation.
      final result = await staged.rename(reserved.path);
      committed = true;
      return result.path;
    } catch (_) {
      throw const VideoScreenshotFailure('无法保存截图，请检查截图目录的权限或磁盘空间。');
    } finally {
      if (!committed && reserved != null) {
        try {
          await reserved.delete();
        } catch (_) {}
      }
      if (staging != null) {
        try {
          final staged = File(p.join(staging.path, 'frame.png'));
          if (await staged.exists()) await staged.delete();
          await staging.delete();
        } catch (_) {}
      }
    }
  }
}
