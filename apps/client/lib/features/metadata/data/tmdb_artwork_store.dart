import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../storage/runtime_storage_paths.dart';

/// Immutable, content-addressed artwork outside the user's media directories.
/// Database values are portable references, never executable-specific paths.
class TmdbArtworkStore {
  TmdbArtworkStore({Future<Directory> Function()? library})
    : library = library ?? (() => RuntimeStoragePaths.current.library());
  final Future<Directory> Function() library;
  static const prefix = 'metadata-artwork:';
  static bool isReference(String value) => value.startsWith(prefix);
  static final _name = RegExp(r'^[a-f0-9]{64}\.(?:jpg|png|webp)$');

  Future<Directory> _directory() async {
    final root = await library();
    final resolved = await root.resolveSymbolicLinks();
    final directory = Directory(p.join(resolved, 'metadata-artwork'));
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      await directory.create();
    }
    final real = await directory.resolveSymbolicLinks();
    if (!p.isWithin(resolved, real)) throw const SourceFailure('元数据图片目录不可用。');
    return Directory(real);
  }

  Future<File> file(String reference) async {
    if (!isReference(reference) ||
        !_name.hasMatch(reference.substring(prefix.length))) {
      throw const SourceFailure('元数据图片引用无效。');
    }
    final directory = await _directory();
    final file = File(
      p.join(directory.path, reference.substring(prefix.length)),
    );
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final real = await file.resolveSymbolicLinks();
      if (!p.isWithin(directory.path, real)) {
        throw const SourceFailure('元数据图片路径不可用。');
      }
    }
    return file;
  }

  Future<String> save(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const SourceFailure('元数据图片大小无效。');
    }
    final ext =
        bytes.length >= 8 &&
            bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71
        ? 'png'
        : bytes.length >= 3 &&
              bytes[0] == 255 &&
              bytes[1] == 216 &&
              bytes[2] == 255
        ? 'jpg'
        : bytes.length >= 12 &&
              String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
              String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
        ? 'webp'
        : null;
    if (ext == null) throw const SourceFailure('元数据图片格式无效。');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width > 8192 ||
          descriptor.height > 8192 ||
          descriptor.width * descriptor.height > 32 * 1024 * 1024) {
        throw const SourceFailure('元数据图片尺寸过大。');
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: descriptor.width.clamp(1, 256),
      );
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    final reference = '$prefix${sha256.convert(bytes)}.$ext';
    final target = await file(reference);
    if (await target.exists()) return reference;
    final temporary = File(
      '${target.path}.part-${Random.secure().nextInt(0x7fffffff)}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return reference;
  }
}
