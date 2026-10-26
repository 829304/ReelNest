import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:math';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
// media_kit 1.2.6 has no public getter for the resolved bundled libmpv path.
// Keep this pinned-version dependency confined to the preview adapter.
// ignore: implementation_imports
import 'package:media_kit/src/player/native/core/native_library.dart';

import 'mpv_preview_decoder.dart';

import '../features/playback/domain/video_frame_preview.dart';

/// Isolated decoder using the libmpv already bundled by media_kit. No native
/// commands, playback reports or seeks touch the visible player.
Future<Uint8List?> generateMpvVideoPreview(
  VideoPreviewResource resource,
  Duration sampleTime,
  VideoPreviewCancellation cancellation, {
  void Function(String code)? onIssue,
}) async {
  if (cancellation.isCancelled || sampleTime < resource.offset) return null;
  BoundedVideoPreviewProxy? proxy;
  final ready = ReceivePort();
  SendPort? control;
  final subscription = ready.listen((message) {
    if (message is SendPort) {
      control = message;
      if (cancellation.isCancelled) control?.send(null);
    } else if (message is String && message != 'cancelled') {
      onIssue?.call(message);
    }
  });
  unawaited(cancellation.whenCancelled.then((_) => control?.send(null)));
  final deadline = Timer(const Duration(seconds: 8), () {
    if (!cancellation.isCancelled) {
      onIssue?.call('preview_timeout');
      cancellation.cancel();
    }
  });
  try {
    var location = resource.location;
    final format = resource.remote
        ? previewDemuxer(Uri.parse(location).path)
        : null;
    if (resource.remote) {
      if (format == null) {
        onIssue?.call('container_unknown');
        return null;
      }
      proxy = await BoundedVideoPreviewProxy.open(
        Uri.parse(location),
        cancellation,
        onIssue: onIssue,
      );
      location = proxy.uri.toString();
    }
    if (cancellation.isCancelled) return null;
    MediaKit.ensureInitialized();
    final rgba = await decodeMpvPreview(
      MpvPreviewArguments(
        library: NativeLibrary.path,
        location: location,
        position: sampleTime - resource.offset,
        format: format,
        ready: ready.sendPort,
      ),
    );
    if (rgba == null || cancellation.isCancelled) return null;
    final image = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      312,
      176,
      ui.PixelFormat.rgba8888,
      image.complete,
    );
    final decoded = await image.future;
    try {
      final encoded = await decoded.toByteData(format: ui.ImageByteFormat.png);
      return cancellation.isCancelled ? null : encoded?.buffer.asUint8List();
    } finally {
      decoded.dispose();
    }
  } catch (_) {
    if (!cancellation.isCancelled) onIssue?.call('preview_exception');
    // No decoder exception or authenticated URI escapes through this API.
  } finally {
    deadline.cancel();
    await subscription.cancel();
    ready.close();
    await proxy?.close();
  }
  return null;
}

String? previewDemuxer(String path) {
  final extension = path.toLowerCase().split('.').last;
  return const {
    'mp4': 'mov',
    'm4v': 'mov',
    'mov': 'mov',
    'mkv': 'matroska',
    'webm': 'matroska',
    'avi': 'avi',
    'ts': 'mpegts',
    'mpeg': 'mpeg',
    'mpg': 'mpeg',
    'wmv': 'asf',
  }[extension];
}

/// Ephemeral loopback-only byte-range bridge. Actual received bytes, not only
/// Content-Length, consume a per-preview budget. No redirects or full-body
/// fallback, and no file writes; unsupported progressive transcodes fail closed.
class BoundedVideoPreviewProxy {
  BoundedVideoPreviewProxy._(
    this._server,
    this._client,
    this._upstream,
    this._route,
    this.maxRangeBytes,
    this.maxTotalBytes,
    this.onIssue,
  ) {
    _uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server.port,
      path: _route,
    );
    _server.listen((request) {
      unawaited(_serve(request));
    });
  }
  final HttpServer _server;
  final HttpClient _client;
  final Uri _upstream;
  final String _route;
  final int maxRangeBytes;
  final int maxTotalBytes;
  final void Function(String code)? onIssue;
  int _received = 0;
  bool _closed = false;
  int get receivedBytes => _received;
  late final Uri _uri;
  Uri get uri => _uri;

  static Future<BoundedVideoPreviewProxy> open(
    Uri upstream,
    VideoPreviewCancellation cancellation, {
    int maxRangeBytes = 2 * 1024 * 1024,
    int maxTotalBytes = 16 * 1024 * 1024,
    void Function(String code)? onIssue,
  }) async {
    if (!['http', 'https'].contains(upstream.scheme) ||
        upstream.userInfo.isNotEmpty ||
        maxRangeBytes <= 0 ||
        maxTotalBytes <= 0) {
      throw ArgumentError('Invalid preview resource');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = false;
    final nonce = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final proxy = BoundedVideoPreviewProxy._(
      server,
      client,
      upstream,
      '/$nonce/preview.mp4',
      maxRangeBytes,
      maxTotalBytes,
      onIssue,
    );
    unawaited(cancellation.whenCancelled.then((_) => proxy.close()));
    return proxy;
  }

  Future<void> _serve(HttpRequest request) async {
    final output = request.response;
    try {
      if (_closed ||
          request.uri.path != _route ||
          request.uri.hasQuery ||
          !['GET', 'HEAD'].contains(request.method) ||
          _received >= maxTotalBytes) {
        output.statusCode = HttpStatus.notFound;
        return;
      }
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(
        request.headers.value(HttpHeaders.rangeHeader) ?? 'bytes=0-',
      );
      if (match == null) {
        output.statusCode = HttpStatus.badRequest;
        return;
      }
      final start = int.parse(match[1]!);
      final requestedEnd = int.tryParse(match[2]!);
      final limit = min(maxRangeBytes, maxTotalBytes - _received);
      final end = min(requestedEnd ?? start + limit - 1, start + limit - 1);
      if (end < start) {
        output.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      final incoming = await _client.openUrl(request.method, _upstream);
      incoming.followRedirects = false;
      incoming.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      incoming.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await incoming.close();
      final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
        response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
      );
      if (response.statusCode != HttpStatus.partialContent ||
          range == null ||
          int.parse(range[1]!) != start ||
          int.parse(range[2]!) > end ||
          int.parse(range[2]!) < start ||
          int.parse(range[3]!) <= int.parse(range[2]!) ||
          response.contentLength > limit ||
          (response.headers.value(HttpHeaders.contentEncodingHeader) ??
                  'identity') !=
              'identity') {
        onIssue?.call(
          response.statusCode != 206
              ? 'upstream_http_${response.statusCode}'
              : 'upstream_range',
        );
        incoming.abort();
        output.statusCode = HttpStatus.badGateway;
        return;
      }
      final expected = int.parse(range[2]!) - start + 1;
      if (response.contentLength >= 0 && response.contentLength != expected) {
        incoming.abort();
        output.statusCode = HttpStatus.badGateway;
        return;
      }
      output.statusCode = HttpStatus.partialContent;
      output.headers.set(
        HttpHeaders.contentRangeHeader,
        response.headers.value(HttpHeaders.contentRangeHeader)!,
      );
      output.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      output.headers.contentType = ContentType.binary;
      output.contentLength = expected;
      if (request.method == 'HEAD') {
        incoming.abort();
        return;
      }
      var count = 0;
      await for (final chunk in response) {
        if (_closed ||
            count + chunk.length > expected ||
            _received + chunk.length > maxTotalBytes) {
          if (!_closed) onIssue?.call('upstream_budget');
          incoming.abort();
          await close();
          return;
        }
        count += chunk.length;
        _received += chunk.length;
        output.add(chunk);
        await output.flush();
      }
      if (count != expected) {
        incoming.abort();
        await close();
      }
    } catch (_) {
      // A canceled native request or closed cache volume is an empty preview.
    } finally {
      try {
        await output.close();
      } catch (_) {
        /* Client already canceled. */
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
    await _server.close(force: true);
  }
}
