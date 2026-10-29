import 'dart:async';
import 'dart:io';

import '../../../application/async_tasks.dart';
import '../../../domain/media_source.dart';
import '../domain/url_video.dart';

typedef UrlVideoProbe = Future<UrlVideoHealth> Function(
  String,
  ScanCancellation,
);

/// URLSourceHealthMonitor: generation guard, HTTP-only checks, no periodic
/// polling. Responses are classified from headers, never buffered in memory.
class UrlVideoHealthMonitor {
  UrlVideoHealthMonitor({
    required this.onState,
    UrlVideoProbe? probe,
    this.timeout = const Duration(seconds: 12),
    this.concurrency = 4,
    HttpClient Function()? createClient,
  }) : _providedProbe = probe,
       createClient = createClient ?? HttpClient.new;
  final void Function(Map<MediaIdentity, UrlVideoHealth>) onState;
  final UrlVideoProbe? _providedProbe;
  final HttpClient Function() createClient;
  final Duration timeout;
  final int concurrency;
  ScanCancellation? _token;
  bool _closed = false;
  Future<void>? _pending;
  Map<MediaIdentity, UrlVideoHealth> _state = {};
  Future<void> refresh(List<UrlVideo> items, {bool enabled = true}) {
    _token?.cancel();
    final token = ScanCancellation();
    _token = token;
    final work = _refresh(items, enabled, token);
    _pending = work;
    return work;
  }

  Future<void> _refresh(
    List<UrlVideo> items,
    bool enabled,
    ScanCancellation token,
  ) async {
    if (_closed) return;
    if (!enabled) {
      _state = {};
      onState(const {});
      return;
    }
    final eligible = items
        .where(
          (e) => {
            'http',
            'https',
          }.contains(Uri.tryParse(e.url)?.scheme.toLowerCase()),
        )
        .toList();
    final live = items.map((e) => e.identity).toSet();
    final next = <MediaIdentity, UrlVideoHealth>{
      for (final e in _state.entries)
        if (live.contains(e.key)) e.key: e.value,
      for (final e in eligible) e.identity: UrlVideoHealth.checking,
    };
    _state = next;
    onState(Map.unmodifiable(next));
    var index = 0;
    Future<void> worker() async {
      while (index < eligible.length && !token.isCancelled && !_closed) {
        final item = eligible[index++];
        try {
          final result = await awaitWithCancellation(
            token,
            () => (_providedProbe ?? _probe)(item.url, token),
          );
          token.check();
          next[item.identity] = result;
        } on ScanCancelled {
          return;
        } catch (_) {
          if (!token.isCancelled) {
            next[item.identity] = UrlVideoHealth.unreachable;
          }
        }
      }
    }

    await Future.wait(List.generate(concurrency.clamp(1, 8), (_) => worker()));
    if (!_closed && !token.isCancelled && identical(_token, token)) {
      _state = next;
      onState(Map.unmodifiable(next));
    }
  }

  static UrlVideoHealth classify(int status, String? contentType) {
    if (status >= 400) return UrlVideoHealth.unreachable;
    final type = (contentType ?? '').toLowerCase();
    return type.contains('text/html') || type.contains('application/xhtml')
        ? UrlVideoHealth.unparseable
        : UrlVideoHealth.ok;
  }

  Future<UrlVideoHealth> _probe(String location, ScanCancellation token) async {
    Future<UrlVideoHealth> request(String method) async {
      final client = createClient()..connectionTimeout = timeout;
      final unlisten = token.listen(() => client.close(force: true));
      final deadline = Timer(timeout, () => client.close(force: true));
      try {
        token.check();
        Future<UrlVideoHealth> work() async {
          final request = await client.openUrl(method, Uri.parse(location));
          request.maxRedirects = 5;
          if (method == 'GET') {
            request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
          }
          final response = await request.close();
          final result = classify(
            response.statusCode,
            response.headers.value(HttpHeaders.contentTypeHeader),
          );
          await response.listen((_) {}).cancel();
          return result;
        }

        return await work().timeout(timeout);
      } finally {
        deadline.cancel();
        unlisten();
        client.close(force: true);
      }
    }

    try {
      return await request('HEAD');
    } catch (_) {
      token.check();
    }
    try {
      return await request('GET');
    } catch (_) {
      token.check();
      return UrlVideoHealth.unreachable;
    }
  }

  Future<void> dispose() async {
    _closed = true;
    _token?.cancel();
    await _pending;
  }
}
