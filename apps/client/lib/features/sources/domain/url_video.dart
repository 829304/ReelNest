import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';

class UrlVideo {
  const UrlVideo({
    required this.identity,
    required this.title,
    required this.url,
    required this.createdAt,
    required this.updatedAt,
  });
  final MediaIdentity identity;
  final String title, url;
  final DateTime createdAt, updatedAt;
  @override
  String toString() => 'UrlVideo';
}

enum UrlVideoHealth {
  unknown('未检测'),
  checking('检测中'),
  ok('可访问'),
  unreachable('无法访问'),
  unparseable('无法解析');

  const UrlVideoHealth(this.label);
  final String label;
  bool get isUnhealthy => this == unreachable || this == unparseable;
}

class UrlAddResult {
  const UrlAddResult({required this.added, required this.skipped});
  final int added, skipped;
}

/// URLSourcePolicy.swift. Preserve the trimmed string: do not reorder signed
/// query parameters, normalize host case, decode escapes or strip fragments.
abstract final class UrlVideoPolicy {
  static bool isCacheable(String value) {
    final uri = Uri.tryParse(value);
    return normalize(value) != null &&
        uri != null &&
        ['http', 'https'].contains(uri.scheme.toLowerCase()) &&
        !['.m3u', '.m3u8', '.mpd'].any(uri.path.toLowerCase().endsWith);
  }

  static const schemes = {
    'http',
    'https',
    'rtsp',
    'rtmp',
    'rtp',
    'mms',
    'srt',
    'udp',
    'ftp',
  };
  static String? normalize(String raw) {
    final value = raw.trim(), uri = Uri.tryParse(raw.trim());
    if (value.isEmpty ||
        value.contains(RegExp(r'[\x00-\x20\x7f]')) ||
        uri == null ||
        !schemes.contains(uri.scheme.toLowerCase()) ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      return null;
    }
    try {
      uri.port;
    } on FormatException {
      return null;
    }
    return value;
  }

  static List<String> lines(String raw) => raw
      .split(RegExp(r'\r\n|[\r\n\u0085\u2028\u2029]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  static int addableCount(String raw) =>
      lines(raw).map(normalize).nonNulls.toSet().length;
  static String id(String normalized) =>
      'url-${sha256.convert(utf8.encode(normalized))}';
  static String title(String normalized) {
    final uri = Uri.parse(normalized);
    final last = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    if (last != null) {
      final stem = p.posix.basenameWithoutExtension(last);
      return stem.isEmpty ? last : stem;
    }
    return uri.host.isEmpty ? 'URL 视频' : uri.host;
  }
}
