import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/app_failure.dart';
import '../../domain/library_catalog.dart';
import '../../domain/media.dart';
import '../../domain/server_address.dart';
import '../../domain/server_connection.dart';
import 'mlink_codec.dart';
import 'media_codec.dart';

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
        await _request(
          address,
          '/api/v1/auth/login',
          body: {
            'username': username,
            'password': password,
            'deviceName': deviceName,
            'platform': platform,
            'delivery': 'token',
          },
        ),
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

  Future<MlinkTokens> refresh(
    ServerAddress address,
    String refreshToken,
  ) async {
    try {
      return MlinkTokens.fromJson(
        await _request(
          address,
          '/api/v1/auth/refresh',
          body: {'refreshToken': refreshToken, 'delivery': 'token'},
        ),
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
    Map<String, String>? query,
  }) async {
    try {
      return jsonObject(
        jsonDecode(
          utf8.decode(
            await _bytes(
              address,
              path,
              body: body,
              accessToken: accessToken,
              query: query,
            ),
          ),
        ),
      );
    } on FormatException {
      throw AppFailure.invalidResponse;
    }
  }

  Future<MediaPage> browse(
    ServerAddress address,
    String token, {
    required String type,
    required int offset,
    required MediaSort sort,
    int limit = 48,
  }) async {
    _validatePage(offset, limit);
    if (!mediaTypes.containsKey(type)) throw AppFailure.invalidResponse;
    return decodeMediaPage(
      await _request(
        address,
        '/api/v1/library/browse',
        accessToken: token,
        query: {
          'type': type,
          'offset': '$offset',
          'limit': '$limit',
          'sort': sort.name,
        },
      ),
      offset: offset,
      limit: limit,
    );
  }

  Future<MediaDetail> detail(
    ServerAddress address,
    String token,
    String id, {
    required bool isSeries,
  }) async {
    try {
      return decodeMediaDetail(
        await _request(
          address,
          '/api/v1/items/${Uri.encodeComponent(mediaIdentifier(id))}',
          accessToken: token,
        ),
        id,
        isSeries: isSeries,
      );
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.incompatibleServer) {
        throw const AppFailure(FailureKind.notFound, '该媒体已移除或当前账号无权访问。');
      }
      rethrow;
    }
  }

  Future<MediaDetail> seriesDetail(
    ServerAddress address,
    String token,
    String id,
  ) async {
    try {
      return decodeSeriesDetail(
        await _request(
          address,
          '/api/v1/series/${Uri.encodeComponent(mediaIdentifier(id))}',
          accessToken: token,
        ),
        id,
      );
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.incompatibleServer) {
        throw const AppFailure(FailureKind.notFound, '该系列已移除或当前账号无权访问。');
      }
      rethrow;
    }
  }

  Future<MediaPage> episodes(
    ServerAddress address,
    String token, {
    required String seriesId,
    required String season,
    required int offset,
    int limit = 48,
  }) async {
    _validatePage(offset, limit);
    if (season != 'unspecified' &&
        (!RegExp(r'^\d{1,5}$').hasMatch(season) || int.parse(season) > 10000)) {
      throw AppFailure.invalidResponse;
    }
    return decodeMediaPage(
      await _request(
        address,
        '/api/v1/series/${Uri.encodeComponent(mediaIdentifier(seriesId))}/episodes',
        accessToken: token,
        query: {'season': season, 'offset': '$offset', 'limit': '$limit'},
      ),
      offset: offset,
      limit: limit,
      episodes: true,
    );
  }

  Future<Uint8List> artwork(ServerAddress address, String token, String id) =>
      _bytes(
        address,
        '/api/v1/images/${Uri.encodeComponent(mediaIdentifier(id))}/poster',
        accessToken: token,
        query: const {'size': '320'},
        image: true,
        maxBytes: 4 * 1024 * 1024,
      );

  void _validatePage(int offset, int limit) {
    if (offset < 0 || offset > 1000000 || limit < 1 || limit > 100) {
      throw const AppFailure(FailureKind.invalidInput, '分页范围超出服务器支持的限制。');
    }
  }

  Future<Uint8List> _bytes(
    ServerAddress address,
    String path, {
    Map<String, Object>? body,
    String? accessToken,
    Map<String, String>? query,
    int maxBytes = _maxResponseBytes,
    bool image = false,
  }) async {
    final client = _createClient();
    client.connectionTimeout = _timeout;
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          address.endpoint(path).replace(queryParameters: query),
        );
        // Never forward credentials across redirects, even on the same host.
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          image
              ? 'image/jpeg,image/png,image/webp,image/gif'
              : 'application/json',
        );
        if (accessToken != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $accessToken',
          );
        }
        if (body != null) {
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          request.headers.set('X-MediaLIB-Client', 'mlink-native/1');
          request.add(utf8.encode(jsonEncode(body)));
        }
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw _statusFailure(response.statusCode);
        }
        if (image &&
            !{
              'image/jpeg',
              'image/png',
              'image/webp',
              'image/gif',
            }.contains(response.headers.contentType?.mimeType)) {
          throw AppFailure.invalidResponse;
        }
        if (response.contentLength > maxBytes) {
          throw AppFailure.invalidResponse;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw AppFailure.invalidResponse;
          }
          bytes.addAll(chunk);
        }
        return Uint8List.fromList(bytes);
      })().timeout(_timeout);
    } on TimeoutException {
      throw const AppFailure(FailureKind.timeout, '连接超时，请检查地址或稍后重试。');
    } on HandshakeException {
      throw const AppFailure(
        FailureKind.certificate,
        '无法建立受信任的 TLS 连接，请检查服务器证书和本机时间。',
      );
    } on SocketException {
      throw const AppFailure(FailureKind.network, '无法连接服务器，请检查网络、地址和端口。');
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
