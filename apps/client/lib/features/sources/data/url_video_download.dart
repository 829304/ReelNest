import 'dart:io';

import '../../../api/emby/emby_download.dart';
import '../../../domain/media_source.dart';
import '../domain/url_video.dart';

/// Public/signed video URLs never share server credentials or rewrite queries.
Future<EmbyDownloadProgress> downloadUrlVideo(
  String location,
  File destination,
  ScanCancellation cancellation, {
  String? etag,
  void Function(EmbyDownloadProgress)? onProgress,
}) async {
  if (!UrlVideoPolicy.isCacheable(location)) {
    throw const SourceFailure('仅 HTTP/HTTPS 视频直链支持离线缓存。');
  }
  cancellation.check();
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final unlisten = cancellation.listen(() => http.close(force: true));
  try {
    return await streamEmbyDownload(
      http,
      Uri.parse(location),
      destination,
      cancellation,
      etag: etag,
      onProgress: onProgress,
      authenticatedOrigin: false,
      directVideoOnly: true,
    );
  } finally {
    unlisten();
    http.close(force: true);
  }
}
