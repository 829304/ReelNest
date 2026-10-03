import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/app_failure.dart';
import '../../domain/library_catalog.dart';
import '../../domain/server_address.dart';
import '../../domain/server_connection.dart';
import 'mlink_codec.dart';

class MlinkClient {
  MlinkClient({HttpClient Function()? createClient, DateTime Function()? now})
    : _createClient = createClient ?? HttpClient.new,
      _now = now ?? DateTime.now;

  final HttpClient Function() _createClient;
  final DateTime Function() _now;
  static const _timeout = Duration(seconds: 10);
  static const _maxResponseBytes = 1024 * 1024;

  Future<ServerDescriptor> discover(ServerAddress address) async {
    try {
      return decodeDescriptor(await _request(address, '/.well-known/mlink'));
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.invalidResponse) {
        throw const AppFailure(
          FailureKind.incompatibleServer,
          '该地址没有返回有效的 Mlink 服务信息。暂不支持直连 Emby 或 Jellyfin。',
        );
      }
      rethrow;
    }
  }

  Future<MlinkTokens> login({
    required ServerAddress address,
    required String username,
    required String password,
    required String deviceName,
    required String platform,
  }) async {
    try {
      return MlinkTokens.fromJson(
        await _request(address, '/api/v1/auth/login', body: {
          'username': username,
          'password': password,
          'deviceName': deviceName,
          'platform': platform,
          'delivery': 'token',
        }),
      );
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.unauthorized) {
        throw const AppFailure(
          FailureKind.invalidCredentials,
          '用户名或密码不正确，请重新输入。',
        );
      }
      rethrow;
    }
  }

  Future<MlinkTokens> refresh(ServerAddress address, String refreshToken) async {
    try {
      return MlinkTokens.fromJson(
        await _request(address, '/api/v1/auth/refresh', body: {
          'refreshToken': refreshToken,
          'delivery': 'token',
        }),
      );
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.unauthorized) {
        throw AppFailure.sessionExpired;
      }
      rethrow;
    }
  }

  Future<LibraryCatalog> categories(
    ServerAddress address,
    String accessToken,
  ) async => decodeCatalog(
    await _request(
      address,
      '/api/v1/library/categories',
      accessToken: accessToken,
    ),
    _now(),
  );

  Future<Map<String, dynamic>> _request(
    ServerAddress address,
    String path, {
    Map<String, Object>? body,
    String? accessToken,
  }) async {
    final client = _createClient();
    client.connectionTimeout = _timeout;
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          address.endpoint(path),
        );
        // Never forward credentials across redirects, even on the same host.
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        if (accessToken != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $accessToken',
          );
        }
        if (body != null) {
          request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          request.headers.set('X-MediaLIB-Client', 'mlink-native/1');
          request.add(utf8.encode(jsonEncode(body)));
        }
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw _statusFailure(response.statusCode);
        }
        if (response.contentLength > _maxResponseBytes) {
          throw AppFailure.invalidResponse;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > _maxResponseBytes) {
            throw AppFailure.invalidResponse;
          }
          bytes.addAll(chunk);
        }
        return jsonObject(jsonDecode(utf8.decode(bytes)));
      })().timeout(_timeout);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, '连接超时，请检查地址或稍后重试。');
    } on HandshakeException {
      throw const AppFailure(
        FailureKind.certificate,
        '无法建立受信任的 TLS 连接，请检查服务器证书和本机时间。',
      );
    } on SocketException {
      throw const AppFailure(
        FailureKind.network,
        '无法连接服务器，请检查网络、地址和端口。',
      );
    } on HttpException {
      throw const AppFailure(FailureKind.network, '连接中断，请稍后重试。');
    } on FormatException {
      throw AppFailure.invalidResponse;
    } finally {
      // Also cancels the underlying socket when the whole-request timer expires.
      client.close(force: true);
    }
  }

  AppFailure _statusFailure(int status) => switch (status) {
    401 => const AppFailure(FailureKind.unauthorized, '请求需要有效的登录凭据。'),
    403 => const AppFailure(FailureKind.forbidden, '当前账号没有访问权限。'),
    404 => const AppFailure(
      FailureKind.incompatibleServer,
      '服务器没有提供所需的 Mlink 接口，请检查地址和服务端版本。',
    ),
    428 => const AppFailure(
      FailureKind.setupRequired,
      '服务器尚未完成初始化，请先在服务端完成设置。',
    ),
    429 => const AppFailure(FailureKind.rateLimited, '请求过于频繁，请稍后再试。'),
    >= 300 && < 400 => const AppFailure(
      FailureKind.invalidInput,
      '服务器要求跳转，请直接填写最终的 HTTPS 服务地址。',
    ),
    _ => AppFailure(FailureKind.server, '服务器请求未完成（HTTP $status）。'),
  };
}
