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
            next.origin != resource.origin ||
            next.userInfo.isNotEmpty) {
          throw const SourceFailure('下载地址发生跨站跳转，缓存已停止。');
        }
        await response.take(0).drain<void>();
        // Preserve the current credential only for this authenticated origin.
        uri = next.replace(
          queryParameters: {
            ...next.queryParameters,
            'api_key': resource.queryParameters['api_key']!,
          },
        );
        continue;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        request.abort();
        throw EmbyFailure(
          response.statusCode == 401
              ? EmbyError.authentication
              : EmbyError.response,
          '视频缓存失败（HTTP ${response.statusCode}）。',
          status: response.statusCode,
        );
      }
      final mime = response.headers.contentType?.mimeType;
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
      while (await chunks.moveNext()) {
        final chunk = chunks.current;
        cancellation.check();
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
