import 'dart:convert';
import 'dart:io';

/// Local protocol fixture; never contacts an external Emby account.
class EmbyServerFixture {
  late HttpServer server;
  int loginCount = 0, viewsCount = 0, userCount = 0;
  int loginStatus = 200, viewsStatus = 200;
  String userId = 'user-1';
  String validToken = '';
  final requests =
      <({String method, Uri uri, String? authorization, String body})>[];
  Object views = {
    'Items': [
      {'Id': 'movies', 'Name': '电影', 'CollectionType': 'movies'},
      {'Id': 'shows', 'Name': '电视剧', 'CollectionType': 'tvshows'},
    ],
  };
  final catalog = <String, List<Map<String, dynamic>>>{};
  int itemPageSize = 2;
  bool includeTotal = true;
  Future<void> Function(HttpRequest)? itemsHandler,
      viewsHandler,
      detailHandler,
      userFlagHandler,
      artworkHandler,
      playbackHandler,
      streamHandler;
  Future<void> Function(HttpRequest)? override;
  String get address => 'http://127.0.0.1:${server.port}/proxy/emby/';
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        authorization: request.headers.value('X-Emby-Authorization'),
        body: body,
      ));
      if (override != null) {
        await override!(request);
        return;
      }
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/proxy/emby/Users/AuthenticateByName') {
        loginCount++;
        request.response.statusCode = loginStatus;
        validToken = 'token-$loginCount';
        request.response.write(
          jsonEncode(
            loginStatus == 200
                ? {
                    'User': {'Id': userId, 'Name': 'tester'},
                    'AccessToken': validToken,
                  }
                : {'error': 'fixture'},
          ),
        );
      } else if (request.uri.path == '/proxy/emby/Users/$userId/Views') {
        viewsCount++;
        if (viewsHandler != null &&
            request.uri.queryParameters['api_key'] == validToken) {
          await viewsHandler!(request);
          return;
        }
        request.response.statusCode =
            request.uri.queryParameters['api_key'] == validToken
            ? viewsStatus
            : 401;
        request.response.write(jsonEncode(views));
      } else if (request.uri.path == '/proxy/emby/Users/$userId/Items') {
        if (request.uri.queryParameters['api_key'] != validToken) {
          request.response.statusCode = 401;
          await request.response.close();
          return;
        }
        if (itemsHandler != null) {
          await itemsHandler!(request);
          return;
        }
        final items =
            catalog[request.uri.queryParameters['ParentId'] ?? ''] ?? const [];
        final start = int.parse(request.uri.queryParameters['StartIndex']!);
        request.response.write(
          jsonEncode({
            'Items': items.skip(start).take(itemPageSize).toList(),
            if (includeTotal) 'TotalRecordCount': items.length,
          }),
        );
      } else if (request.uri.path.startsWith(
        '/proxy/emby/Users/$userId/Items/',
      )) {
        if (request.uri.queryParameters['api_key'] != validToken) {
          request.response.statusCode = 401;
        } else if (detailHandler != null) {
          await detailHandler!(request);
          return;
        } else {
          request.response.write('{}');
        }
      } else if (request.uri.path.startsWith(
            '/proxy/emby/Users/$userId/FavoriteItems/',
          ) ||
          request.uri.path.startsWith(
            '/proxy/emby/Users/$userId/PlayedItems/',
          )) {
        if (request.uri.queryParameters['api_key'] != validToken) {
          request.response.statusCode = 401;
        } else if (userFlagHandler != null) {
          await userFlagHandler!(request);
          return;
        } else {
          request.response.statusCode = 204;
        }
      } else if (request.uri.path.startsWith('/proxy/emby/Sessions/Playing') ||
          request.uri.path.startsWith('/proxy/emby/Videos/') ||
          request.uri.path.startsWith('/proxy/emby/Audio/')) {
        if (request.uri.queryParameters['api_key'] != validToken) {
          request.response.statusCode = 401;
        } else {
          final handler = request.uri.path.contains('/Sessions/')
              ? playbackHandler
              : streamHandler;
          if (handler != null) {
            await handler(request);
            return;
          }
          request.response.statusCode = 204;
        }
      } else if (request.uri.path.contains('/Images/')) {
        if (request.uri.queryParameters['api_key'] != validToken) {
          request.response.statusCode = 401;
        } else if (artworkHandler != null) {
          await artworkHandler!(request);
          return;
        } else {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          );
        }
      } else if (request.uri.path == '/proxy/emby/Users/$userId') {
        userCount++;
        request.response.statusCode =
            request.uri.queryParameters['api_key'] == validToken ? 200 : 401;
        request.response.write(jsonEncode({'Id': userId}));
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
  }

  Future<void> close() => server.close(force: true);
}
