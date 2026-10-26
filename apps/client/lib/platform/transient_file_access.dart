import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/media_source.dart';

/// Memory-only macOS security scope, retained for the decoder's full lifetime.
class TransientFileAccess {
  TransientFileAccess._(this.bookmark, this._token);
  final Uint8List? bookmark;
  final String? _token;
  bool _released = false;
  static const _channel = MethodChannel('reelnest/transient_file_access');

  static Future<TransientFileAccess> acquire(
    String path, {
    Uint8List? bookmark,
  }) async {
    if (!Platform.isMacOS) return TransientFileAccess._(null, null);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'acquire',
        {'path': path, 'bookmark': ?bookmark},
      );
      if (result?['token'] is! String || result?['bookmark'] is! Uint8List) {
        throw const SourceFailure('无法获取视频文件的临时读取权限，请重新选择文件。');
      }
      return TransientFileAccess._(
        result!['bookmark'] as Uint8List,
        result['token'] as String,
      );
    } catch (_) {
      throw const SourceFailure('无法获取视频文件的临时读取权限，请重新选择文件。');
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (_token != null) {
      await _channel.invokeMethod<void>('release', {'token': _token});
    }
  }
}
