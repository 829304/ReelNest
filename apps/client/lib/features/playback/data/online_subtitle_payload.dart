import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../domain/media_source.dart';
import '../domain/online_subtitle.dart';

class OnlineSubtitlePayload {
  const OnlineSubtitlePayload(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
  static const maxArchiveBytes = 8 * 1024 * 1024,
      maxTextBytes = 4 * 1024 * 1024;
  static const extensions = {
    'srt',
    'ass',
    'ssa',
    'vtt',
    'sub',
    'smi',
    'sami',
    'ttml',
    'dfxp',
  };
  static String extensionFor(String? name) {
    final ext = (name ?? '').split('.').last.trim().toLowerCase();
    return extensions.contains(ext) ? ext : 'srt';
  }

  static Future<OnlineSubtitlePayload> decode(
    Uint8List bytes, {
    String? filename,
    required ScanCancellation cancellation,
  }) async {
    cancellation.check();
    if (bytes.isEmpty || bytes.length > maxArchiveBytes) {
      throw const OnlineSubtitleFailure('字幕文件为空或过大。');
    }
    var extension = extensionFor(filename);
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      final selected = _zipEntry(bytes);
      extension = selected.extension;
      bytes = selected.method == 0
          ? selected.compressed
          : await _inflate(
              selected.compressed,
              ZLibDecoder(raw: true),
              cancellation,
            );
      if (bytes.length != selected.size || _crc32(bytes) != selected.crc) {
        throw const OnlineSubtitleFailure('字幕压缩包校验失败，请重试。');
      }
    } else if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = await _inflate(bytes, GZipCodec().decoder, cancellation);
      if (filename?.toLowerCase().endsWith('.gz') == true) {
        extension = extensionFor(filename!.substring(0, filename.length - 3));
      }
    }
    cancellation.check();
    validateText(bytes, extension);
    return OnlineSubtitlePayload(bytes, extension);
  }

  static Future<Uint8List> _inflate(
    Uint8List compressed,
    Converter<List<int>, List<int>> decoder,
    ScanCancellation token,
  ) async {
    final result = BytesBuilder(copy: false);
    // Decode in bounded input slices; never materialize an unbounded inflated
    // archive. No archive member path is ever passed to the filesystem.
    Stream<List<int>> chunks() async* {
      for (var i = 0; i < compressed.length; i += 4096) {
        token.check();
        yield Uint8List.sublistView(
          compressed,
          i,
          (i + 4096).clamp(0, compressed.length),
        );
      }
    }

    try {
      await for (final chunk in decoder.bind(chunks())) {
        token.check();
        if (result.length + chunk.length > maxTextBytes) {
          throw const OnlineSubtitleFailure('解压后的字幕过大，已停止处理。');
        }
        result.add(chunk);
      }
      return result.takeBytes();
    } on ScanCancelled {
      rethrow;
    } on OnlineSubtitleFailure {
      rethrow;
    } catch (_) {
      throw const OnlineSubtitleFailure('字幕压缩包损坏或格式不支持。');
    }
  }

  static ({
    Uint8List compressed,
    String extension,
    int method,
    int size,
    int crc,
  })
  _zipEntry(Uint8List bytes) {
    Never invalid() => throw const OnlineSubtitleFailure('字幕压缩包损坏、加密或格式不支持。');
    final data = ByteData.sublistView(bytes);
    int u16(int n) => data.getUint16(n, Endian.little);
    int u32(int n) => data.getUint32(n, Endian.little);
    var eocd = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (u32(i) == 0x06054b50 && i + 22 + u16(i + 20) == bytes.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0 || u16(eocd + 4) != 0 || u16(eocd + 6) != 0) invalid();
    final count = u16(eocd + 10), centralSize = u32(eocd + 12);
    var at = u32(eocd + 16), total = 0;
    if (count < 1 ||
        count > 64 ||
        u16(eocd + 8) != count ||
        at + centralSize != eocd) {
      invalid();
    }
    ({Uint8List compressed, String extension, int method, int size, int crc})?
    selected;
    final names = <String>{};
    for (var n = 0; n < count; n++) {
      if (at + 46 > eocd || u32(at) != 0x02014b50) invalid();
      final flags = u16(at + 8),
          method = u16(at + 10),
          crc = u32(at + 16),
          compressedSize = u32(at + 20),
          size = u32(at + 24);
      final nameLength = u16(at + 28),
          extra = u16(at + 30),
          comment = u16(at + 32),
          local = u32(at + 42);
      if (at + 46 + nameLength + extra + comment > eocd ||
          flags & 1 != 0 ||
          (method != 0 && method != 8) ||
          size > maxTextBytes ||
          compressedSize > maxArchiveBytes ||
          u16(at + 34) != 0) {
        invalid();
      }
      final name = utf8.decode(
        Uint8List.sublistView(bytes, at + 46, at + 46 + nameLength),
        allowMalformed: true,
      );
      final parts = name.replaceAll('\\', '/').split('/');
      if (name.startsWith('/') ||
          name.contains(':') ||
          parts.contains('..') ||
          !names.add(name)) {
        invalid();
      }
      total += size;
      if (total > 16 * 1024 * 1024) invalid();
      if (local + 30 > eocd ||
          u32(local) != 0x04034b50 ||
          u16(local + 8) != method ||
          u16(local + 6) != flags) {
        invalid();
      }
      final localName = u16(local + 26), localExtra = u16(local + 28);
      final start = local + 30 + localName + localExtra;
      if (start + compressedSize > u32(eocd + 16) ||
          localName != nameLength ||
          utf8.decode(
                Uint8List.sublistView(
                  bytes,
                  local + 30,
                  local + 30 + localName,
                ),
                allowMalformed: true,
              ) !=
              name) {
        invalid();
      }
      final ext = name.split('.').last.toLowerCase();
      if (selected == null && !name.endsWith('/') && extensions.contains(ext)) {
        selected = (
          compressed: Uint8List.sublistView(
            bytes,
            start,
            start + compressedSize,
          ),
          extension: ext,
          method: method,
          size: size,
          crc: crc,
        );
      }
      at += 46 + nameLength + extra + comment;
    }
    if (at != eocd || selected == null) invalid();
    return selected;
  }

  static void validateText(Uint8List bytes, String extension) {
    if (bytes.isEmpty || bytes.length > maxTextBytes) {
      throw const OnlineSubtitleFailure('字幕文件为空或过大。');
    }
    String text;
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) throw const OnlineSubtitleFailure('字幕编码无效。');
      final data = ByteData.sublistView(bytes);
      text = String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2)
          data.getUint16(i, bytes[0] == 0xff ? Endian.little : Endian.big),
      ]);
    } else {
      if (bytes.contains(0)) {
        throw const OnlineSubtitleFailure('下载内容不是可加载的文本字幕。');
      }
      // Keep the original bytes: mpv's subtitle charset handling also supports
      // legacy subtitle encodings. Decode only for structural/error-page checks.
      text = utf8.decode(bytes, allowMalformed: true);
    }
    final lower = text.trimLeft().toLowerCase();
    final valid =
        text.contains('-->') ||
        RegExp(
          r'\[(script info|events)\]',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(r'^\s*\{\d+\}\{\d+\}', multiLine: true).hasMatch(text) ||
        RegExp(r'^\s*\[\d+\]\[\d+\]', multiLine: true).hasMatch(text) ||
        lower.contains('[subtitle]') ||
        lower.contains('<sami') ||
        RegExp(r'<(?:[\w.-]+:)?tt(?:\s|>)').hasMatch(lower);
    if (!extensions.contains(extension) ||
        lower.contains('<!doctype html') ||
        lower.contains('<html') ||
        !valid) {
      throw const OnlineSubtitleFailure('下载内容不是可加载的文本字幕。');
    }
  }

  static final _crcTable = List<int>.generate(256, (i) {
    for (var j = 0; j < 8; j++) {
      i = i & 1 != 0 ? 0xedb88320 ^ (i >> 1) : i >> 1;
    }
    return i;
  });
  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = _crcTable[(crc ^ byte) & 255] ^ (crc >> 8);
    }
    return crc ^ 0xffffffff;
  }
}
