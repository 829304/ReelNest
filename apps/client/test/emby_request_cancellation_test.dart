import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/api/emby/emby_client.dart';
import 'package:reelnest/domain/media_source.dart';

class _ConnectingHttp implements HttpClient {
  final opened = Completer<HttpClientRequest>();
  bool started = false;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    started = true;
    return opened.future;
  }

  @override
  set connectionTimeout(Duration? value) {}
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LateRequest implements HttpClientRequest {
  bool aborted = false;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealHttp extends HttpOverrides {}

void main() {
  const credential = 'fixture-only';
  EmbySession session(Uri server) => EmbySession(
    server: server,
    username: 'fixture',
    userId: 'user',
    token: credential,
  );
  test('cancel during connection setup returns promptly and aborts a late request before headers', () async {
    final http = _ConnectingHttp();
    final client = EmbyClient(deviceId: 'fixture', http: http);
    final token = ScanCancellation();
    final pending = client.artwork(
      session(Uri.parse('http://127.0.0.1:1')),
      'film',
      cancellation: token,
    );
    final failed = expectLater(
      pending.timeout(const Duration(seconds: 1)),
      throwsA(isA<ScanCancelled>()),
    );
    expect(http.started, isTrue);
    token.cancel();
    await failed;
    final request = _LateRequest();
    http.opened.complete(request);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(request.aborted, isTrue);
    client.close();
  });
  test('deadline also aborts connection setup that finishes after the caller returned', () async {
    final http = _ConnectingHttp();
    final client = EmbyClient(
      deviceId: 'fixture',
      http: http,
      timeout: const Duration(milliseconds: 25),
    );
    await expectLater(
      client.artwork(session(Uri.parse('http://127.0.0.1:1')), 'film'),
      throwsA(isA<EmbyFailure>()),
    );
    final request = _LateRequest();
    http.opened.complete(request);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(request.aborted, isTrue);
    client.close();
  });
  test('cancellation while reading an idle chunked body returns without the next chunk', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final started = Completer<void>(), release = Completer<void>();
    server.listen((request) async {
      try {
        request.response.add([1]);
        await request.response.flush();
        started.complete();
        await release.future;
        await request.response.close();
      } catch (_) {}
    });
    final client = EmbyClient(
      deviceId: 'fixture',
      http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp()),
    );
    final token = ScanCancellation();
    final pending = client.artwork(
      session(Uri.parse('http://127.0.0.1:${server.port}')),
      'film',
      cancellation: token,
    );
    final failed = expectLater(
      pending.timeout(const Duration(seconds: 1)),
      throwsA(isA<ScanCancelled>()),
    );
    try {
      await started.future;
      token.cancel();
      await failed;
    } finally {
      release.complete();
      client.close();
      await server.close(force: true);
    }
  });
}
