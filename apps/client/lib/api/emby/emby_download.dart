import 'dart:async';
import 'dart:io';

import '../../domain/media_source.dart';
import 'emby_client.dart';

class EmbyDownloadProgress {
  const EmbyDownloadProgress(this.received, this.expected, this.etag);
  final int received;
  final int? expected;
  final String? etag;
}

/// Stream directly to an owned staging file. No response-sized memory buffer.
Future<EmbyDownloadProgress> streamEmbyDownload(
  HttpClient http,
  Uri resource,
  File destination,
  ScanCancellation cancellation, {
  String? etag,
  void Function(EmbyDownloadProgress)? onProgress,
  Duration idleTimeout = const Duration(seconds: 30),
  bool authenticatedOrigin = true,
  bool directVideoOnly = false,
}) async {
  HttpClientRequest? active;
  RandomAccessFile? output;
  StreamIterator<List<int>>? chunks;
  final unlisten = cancellation.listen(() {
    active?.abort();
    if (chunks != null) unawaited(chunks.cancel());
  });
  try {
    var uri = resource;
    final offset =
        await destination.exists() && etag != null && !etag.startsWith('W/')
        ? await destination.length()
        : 0;
    for (var redirect = 0; redirect <= 4; redirect++) {
      cancellation.check();
      final request = active = await http.getUrl(uri).timeout(idleTimeout);
      cancellation.check();
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        request.headers.set(HttpHeaders.ifRangeHeader, etag!);
      }
      final response = await request.close().timeout(idleTimeout);
      if (response.statusCode == 416 &&
          offset > 0 &&
          response.headers.value(HttpHeaders.contentRangeHeader) ==
              'bytes */$offset' &&
          response.headers.value(HttpHeaders.etagHeader) == etag) {
        cancellation.check();
        return EmbyDownloadProgress(offset, offset, etag);
      }
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final next = location == null ? null : uri.resolve(location);
        if (next == null ||
            !['http', 'https'].contains(next.scheme) ||
            (authenticatedOrigin && next.origin != resource.origin) ||
            next.userInfo.isNotEmpty) {
          throw const SourceFailure('下载地址发生跨站跳转，缓存已停止。');
        }
        await response.take(0).drain<void>();
        // Preserve the current credential only for this authenticated origin.
        uri = !authenticatedOrigin
            ? next
            : next.replace(
                queryParameters: {
                  for (final entry in next.queryParameters.entries)
                    if (!{
                      'api_key',
                      'apikey',
                      'x-plex-token',
                    }.contains(entry.key.toLowerCase()))
                      entry.key: entry.value,
                  if (resource.queryParameters['X-Plex-Token']
                      case final String token)
                    'X-Plex-Token': token,
                  if (resource.queryParameters['ApiKey']
                      case final String token)
                    'ApiKey': token,
                  if (resource.queryParameters['api_key']
                      case final String token)
                    'api_key': token,
                },
              );
        continue;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        request.abort();
        if (!authenticatedOrigin) {
          throw SourceFailure(
            '视频缓存失败（HTTP ${response.statusCode}），请检查链接是否已失效。',
          );
        }
        throw EmbyFailure(
          response.statusCode == 401
              ? EmbyError.authentication
              : EmbyError.response,
          '视频缓存失败（HTTP ${response.statusCode}）。',
          status: response.statusCode,
        );
      }
      final mime = response.headers.contentType?.mimeType;
      if (directVideoOnly &&
          ([
                'application/vnd.apple.mpegurl',
                'application/x-mpegurl',
                'audio/mpegurl',
                'audio/x-mpegurl',
                'application/dash+xml',
                'application/xml',
                'text/xml',
              ].contains(mime) ||
              ['.m3u', '.m3u8', '.mpd'].any(uri.path.toLowerCase().endsWith))) {
        throw const SourceFailure('此地址返回在线播放列表，暂不支持离线缓存。');
      }
      if (mime == 'text/html' ||
          mime == 'application/json' ||
          mime == 'text/plain') {
        throw const SourceFailure('服务器没有返回视频数据。');
      }
      var received = 0;
      int? expected = response.contentLength >= 0
          ? response.contentLength
          : null;
      final receivedTag = response.headers.value(HttpHeaders.etagHeader);
      if (response.statusCode == 206) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
        );
        if (range == null ||
            int.parse(range[1]!) != offset ||
            int.parse(range[2]!) != int.parse(range[3]!) - 1 ||
            (offset > 0 && receivedTag != etag) ||
            (expected != null && expected != int.parse(range[3]!) - offset)) {
          throw const SourceFailure('续传响应不匹配，已保留原有缓存。');
        }
        received = offset;
        expected = int.parse(range[3]!);
      }
      output = await destination.open(
        mode: response.statusCode == 206 && offset > 0
            ? FileMode.append
            : FileMode.write,
      );
      onProgress?.call(EmbyDownloadProgress(received, expected, receivedTag));
      chunks = StreamIterator(response.timeout(idleTimeout));
      // Only a bounded prefix is inspected; video data continues straight to disk.
      final prefix = <int>[];
      // A resumed byte range starts in the middle of a container. Subtitle/text
      // bytes there are not a new document and must not be treated as a playlist.
      final inspectPrefix =
          directVideoOnly && (response.statusCode == 200 || offset == 0);
      while (await chunks.moveNext()) {
        final chunk = chunks.current;
        cancellation.check();
        if (inspectPrefix && prefix.length < 512) {
          prefix.addAll(chunk.take(512 - prefix.length));
          final text = String.fromCharCodes(prefix)
              .replaceFirst(RegExp(r'^\xEF\xBB\xBF'), '')
              .trimLeft()
              .toLowerCase();
          if (text.startsWith('#extm3u') ||
              text.startsWith('<!doctype html') ||
              text.startsWith('<html') ||
              text.startsWith('<?xml') ||
              text.startsWith('<mpd')) {
            throw const SourceFailure('此地址未返回可离线缓存的视频文件，请使用视频直链。');
          }
        }
        if (expected != null && received + chunk.length > expected) {
          throw const SourceFailure('视频长度校验失败。');
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        onProgress?.call(EmbyDownloadProgress(received, expected, receivedTag));
      }
      cancellation.check();
      if (received == 0 || (expected != null && received != expected)) {
        throw const SourceFailure('视频下载不完整，请重新缓存。');
      }
      await output.flush();
      return EmbyDownloadProgress(received, expected, receivedTag);
    }
    throw const SourceFailure('视频下载重定向次数过多。');
  } on SourceFailure {
    rethrow;
  } catch (_) {
    cancellation.check();
    throw const SourceFailure('视频缓存失败，请检查网络、目录权限和磁盘空间。');
  } finally {
    active?.abort();
    await chunks?.cancel();
    await output?.close();
    unlisten();
  }
}
