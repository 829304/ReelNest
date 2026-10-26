import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

import '../../../domain/media_source.dart';

/// An opaque, session-only identity. Neither a URL nor a path is used as a key.
bool isTransientPlayback(MediaIdentity identity) =>
    identity.sourceId == TransientPlaybackTarget.sourceId;

class TransientPlaybackTarget {
  TransientPlaybackTarget._(
    this.location,
    this.local,
    this.id, [
    this.securityBookmark,
  ]);

  static const sourceId = 'temporary-video';
  static const videoExtensions = [
    'mp4',
    'mkv',
    'avi',
    'mov',
    'm4v',
    'wmv',
    'flv',
    'ts',
    'm2ts',
    'webm',
    'mpg',
    'mpeg',
    'rmvb',
    'rm',
    '3gp',
    'vob',
  ];
  static const streamSchemes = {
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
  final String location;
  final bool local;
  final String id;
  final Uint8List? securityBookmark;
  TransientPlaybackTarget withBookmark(Uint8List? value) =>
      TransientPlaybackTarget._(location, local, id, value);
  MediaIdentity get identity => (sourceId: sourceId, localId: id);

  factory TransientPlaybackTarget.file(String value) {
    if (value.trim().isEmpty || value.contains('\u0000')) {
      throw const SourceFailure('请选择一个视频文件。');
    }
    final path = p.normalize(p.absolute(value));
    if (!videoExtensions.contains(
      p.extension(path).toLowerCase().replaceFirst('.', ''),
    )) {
      throw const SourceFailure('请选择支持的视频文件；音乐将在独立模块中提供。');
    }
    return TransientPlaybackTarget._(
      path,
      true,
      _id('file:${Platform.isWindows ? path.toLowerCase() : path}'),
    );
  }

  factory TransientPlaybackTarget.stream(String value) {
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (text.isEmpty ||
        text.contains(RegExp(r'[\x00-\x20\x7f]')) ||
        uri == null ||
        !streamSchemes.contains(uri.scheme.toLowerCase()) ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      throw const SourceFailure('请输入合法的串流地址（http / https / rtsp / rtmp 等）。');
    }
    try {
      uri.port;
    } on FormatException {
      throw const SourceFailure('网络串流地址的端口无效。');
    }
    return TransientPlaybackTarget._(text, false, _id('stream:$text'));
  }

  Future<void> validate() async {
    if (!local) return;
    try {
      if (await FileSystemEntity.type(location) != FileSystemEntityType.file) {
        throw const SourceFailure('视频文件不存在，或所选项目不是文件。');
      }
      final handle = await File(location).open();
      await handle.close();
    } on FileSystemException {
      throw const SourceFailure('无法读取视频文件，请检查文件权限或磁盘连接。');
    }
  }

  IndexedMedia get item {
    final uri = local ? null : Uri.parse(location);
    final name = local
        ? p.basenameWithoutExtension(location)
        : uri!.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return IndexedMedia(
      identity: identity,
      title: name?.isNotEmpty == true ? name! : uri?.host ?? '视频',
      type: 'other',
      bytes: 0,
      modified: DateTime.now().toUtc(),
    );
  }

  Map<String, Object> toJson() => {
    'kind': local ? 'file' : 'stream',
    'location': location,
    'id': id,
    if (securityBookmark != null) 'bookmark': base64Encode(securityBookmark!),
  };
  factory TransientPlaybackTarget.fromJson(Map<String, dynamic> json) {
    final location = json['location'], id = json['id'];
    if (location is! String ||
        id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const SourceFailure('临时播放请求无效。');
    }
    final target = switch (json['kind']) {
      'file' => TransientPlaybackTarget.file(location),
      'stream' => TransientPlaybackTarget.stream(location),
      _ => throw const SourceFailure('临时播放请求无效。'),
    };
    if (id != target.id) throw const SourceFailure('临时播放请求无效。');
    final rawBookmark = json['bookmark'];
    Uint8List? bookmark;
    if (rawBookmark != null) {
      if (!target.local ||
          rawBookmark is! String ||
          rawBookmark.length > 128 * 1024) {
        throw const SourceFailure('临时播放请求无效。');
      }
      try {
        bookmark = base64Decode(rawBookmark);
      } on FormatException {
        throw const SourceFailure('临时播放请求无效。');
      }
    }
    return TransientPlaybackTarget._(
      target.location,
      target.local,
      id,
      bookmark,
    );
  }
  static String _id(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  @override
  String toString() => 'TransientPlaybackTarget';
}
