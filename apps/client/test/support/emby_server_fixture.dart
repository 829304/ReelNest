import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:reelnest/domain/media_source.dart';

/// Local protocol fixture; never contacts an external Emby account.
class EmbyServerFixture {
  EmbyServerFixture({this.kind = MediaSourceKind.emby});
  final MediaSourceKind kind;
  bool get jellyfin => kind == MediaSourceKind.jellyfin;
  String get basePath => jellyfin ? '/proxy/jellyfin/' : '/proxy/emby/';
  bool _closing = false;
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
  String get address => 'http://127.0.0.1:${server.port}$basePath';
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Future<void> respond(HttpRequest request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        method: request.method,
        uri: request.uri,
        authorization: request.headers.value(
          jellyfin ? HttpHeaders.authorizationHeader : 'X-Emby-Authorization',
        ),
        body: body,
      ));
      if (override != null) {
        await override!(request);
        return;
      }
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      final token = jellyfin
          ? RegExp(r'Token="([^"\r\n]+)"')
                    .firstMatch(authorization ?? '')
                    ?.group(1) ??
                request.uri.queryParameters['ApiKey']
          : request.uri.queryParameters['api_key'];
      var route = request.uri.path;
      if (jellyfin) {
        if (!route.startsWith(basePath) ||
            request.headers.value('X-Emby-Authorization') != null ||
            request.uri.queryParameters.containsKey('api_key')) {
          request.response.statusCode = 400;
          await request.response.close();
          return;
        }
        route = '/proxy/emby/${route.substring(basePath.length)}';
        final needsUser =
            route == '/proxy/emby/UserViews' ||
            route == '/proxy/emby/Items' ||
            route.startsWith('/proxy/emby/Items/') ||
            route.startsWith('/proxy/emby/UserFavoriteItems/') ||
            route.startsWith('/proxy/emby/UserPlayedItems/');
        if (needsUser && request.uri.queryParameters['UserId'] != userId) {
          request.response.statusCode = 400;
          await request.response.close();
          return;
        }
        route = route
            .replaceFirst(
              '/proxy/emby/UserViews',
              '/proxy/emby/Users/$userId/Views',
            )
            .replaceFirst(
              '/proxy/emby/Items',
              '/proxy/emby/Users/$userId/Items',
            )
            .replaceFirst(
              '/proxy/emby/UserFavoriteItems/',
              '/proxy/emby/Users/$userId/FavoriteItems/',
            )
            .replaceFirst(
              '/proxy/emby/UserPlayedItems/',
              '/proxy/emby/Users/$userId/PlayedItems/',
            );
      }
      request.response.headers.contentType = ContentType.json;
      if (route == '/proxy/emby/Users/AuthenticateByName') {
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
      } else if (route == '/proxy/emby/Users/$userId/Views') {
        viewsCount++;
        if (viewsHandler != null && token == validToken) {
          await viewsHandler!(request);
          return;
        }
        request.response.statusCode = token == validToken ? viewsStatus : 401;
        request.response.write(jsonEncode(views));
      } else if (route == '/proxy/emby/Users/$userId/Items') {
        if (token != validToken) {
          request.response.statusCode = 401;
          await request.response.close();
          return;
        }
        if (itemsHandler != null) {
          await itemsHandler!(request);
          return;
        }
        final query = request.uri.queryParameters;
        final included = query['IncludeItemTypes']?.split(',').toSet();
        final items =
            (catalog[query['ParentId'] ?? ''] ?? const <Map<String, dynamic>>[])
                .where(
                  (item) => included == null || included.contains(item['Type']),
                )
                .where((item) {
                  final id = query['PersonIds'], name = query['Person'];
                  if (id == null && name == null) return true;
                  return (item['People'] as List? ?? []).whereType<Map>().any(
                    (p) => id != null ? p['Id'] == id : p['Name'] == name,
                  );
                })
                .toList();
        final start = int.parse(query['StartIndex']!);
        final limit = int.parse(query['Limit']!);
        request.response.write(
          jsonEncode({
            'Items': items
                .skip(start)
                .take(itemPageSize < limit ? itemPageSize : limit)
                .toList(),
            if (includeTotal) 'TotalRecordCount': items.length,
          }),
        );
      } else if (route.startsWith('/proxy/emby/Users/$userId/Items/')) {
        if (token != validToken) {
          request.response.statusCode = 401;
        } else if (detailHandler != null) {
          await detailHandler!(request);
          return;
        } else {
          request.response.write('{}');
        }
      } else if (route.startsWith('/proxy/emby/Users/$userId/FavoriteItems/') ||
          route.startsWith('/proxy/emby/Users/$userId/PlayedItems/')) {
        if (token != validToken) {
          request.response.statusCode = 401;
        } else if (userFlagHandler != null) {
          await userFlagHandler!(request);
          return;
        } else {
          request.response.statusCode = 204;
        }
      } else if (route.startsWith('/proxy/emby/Sessions/Playing') ||
          route.startsWith('/proxy/emby/Videos/') ||
          route.startsWith('/proxy/emby/Audio/')) {
        if (token != validToken) {
          request.response.statusCode = 401;
        } else {
          final handler = route.contains('/Sessions/')
              ? playbackHandler
              : streamHandler;
          if (handler != null) {
            await handler(request);
            return;
          }
          request.response.statusCode = 204;
        }
      } else if (route.contains('/Images/')) {
        if (token != validToken) {
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
      } else if (route == '/proxy/emby/Users/$userId') {
        userCount++;
        request.response.statusCode = token == validToken ? 200 : 401;
        request.response.write(jsonEncode({'Id': userId}));
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    }

    server.listen((request) {
      unawaited(
        respond(request).catchError((Object error, StackTrace stack) {
          // Force-closing the fixture may abort a request while its body is still
          // arriving. That teardown I/O failure is expected; other handler errors
          // must still fail the owning test rather than disappear in a Future.
          if (_closing && error is IOException) return;
          Zone.current.handleUncaughtError(error, stack);
        }),
      );
    });
  }

  Future<void> close() async {
    _closing = true;
    await server.close(force: true);
  }
}
