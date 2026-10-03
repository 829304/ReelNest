import 'dart:convert';

import '../../domain/app_failure.dart';
import '../../domain/library_catalog.dart';
import '../../domain/server_connection.dart';

Map<String, dynamic> jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) throw AppFailure.invalidResponse;
  return value;
}

String jsonText(Object? value, int maxBytes, {int minBytes = 1}) {
  if (value is! String) throw AppFailure.invalidResponse;
  final length = utf8.encode(value).length;
  if (length < minBytes || length > maxBytes) {
    throw AppFailure.invalidResponse;
  }
  return value;
}

int _count(Object? value) {
  if (value is! int || value < 0) throw AppFailure.invalidResponse;
  return value;
}

ServerDescriptor decodeDescriptor(Map<String, dynamic> json) {
  if (json['apiVersion'] != 'v1') {
    throw const AppFailure(
      FailureKind.incompatibleServer,
      '服务器不支持 Mlink v1，请确认地址和服务端版本。',
    );
  }
  final capabilities = json['capabilities'];
  if (capabilities is! List || capabilities.length > 128) {
    throw AppFailure.invalidResponse;
  }
  return ServerDescriptor(
    id: jsonText(json['serverID'], 128),
    name: jsonText(json['serverName'], 256),
    apiVersion: 'v1',
    capabilities: capabilities.map((value) => jsonText(value, 128)).toList(),
  );
}

Map<String, Object> encodeDescriptor(ServerDescriptor server) => {
  'serverID': server.id,
  'serverName': server.name,
  'apiVersion': server.apiVersion,
  'capabilities': server.capabilities,
};

LibraryCatalog decodeCatalog(Map<String, dynamic> json, DateTime fetchedAt) {
  final entries = json['categories'];
  if (entries is! List || entries.length > 256) {
    throw AppFailure.invalidResponse;
  }
  final ids = <String>{};
  final categories = entries.map((entry) {
    final category = jsonObject(entry);
    final id = jsonText(category['id'], 128);
    if (!ids.add(id)) throw AppFailure.invalidResponse;
    return LibraryCategory(
      id: id,
      title: jsonText(category['title'], 256),
      itemCount: _count(category['itemCount']),
    );
  }).toList();
  return LibraryCatalog(
    categories: categories,
    videoGroupItemCount: _count(json['videoGroupItemCount']),
    fetchedAt: fetchedAt,
  );
}

/// Data-layer value; never expose through presentation providers or logs.
class MlinkTokens {
  const MlinkTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.sessionId,
    required this.deviceId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final String sessionId;
  final String deviceId;

  factory MlinkTokens.fromJson(Map<String, dynamic> json) {
    final type = jsonText(json['tokenType'], 32);
    final access = _date(json['accessExpiresAt']);
    final refresh = _date(json['refreshExpiresAt']);
    if (type.toLowerCase() != 'bearer' || !access.isBefore(refresh)) {
      throw AppFailure.invalidResponse;
    }
    final accessToken = jsonText(json['accessToken'], 1024, minBytes: 32);
    final refreshToken = jsonText(json['refreshToken'], 1024, minBytes: 32);
    // Bearer is an HTTP header value; reject control characters and whitespace.
    if (!RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(accessToken)) {
      throw AppFailure.invalidResponse;
    }
    return MlinkTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresAt: access,
      refreshExpiresAt: refresh,
      sessionId: jsonText(json['sessionID'], 128),
      deviceId: jsonText(json['deviceID'], 128),
    );
  }

  static DateTime _date(Object? value) {
    final text = jsonText(value, 64);
    final date = DateTime.tryParse(text);
    if (date == null || !date.isUtc) throw AppFailure.invalidResponse;
    return date;
  }

  Map<String, Object> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': 'Bearer',
    'accessExpiresAt': accessExpiresAt.toUtc().toIso8601String(),
    'refreshExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
    'sessionID': sessionId,
    'deviceID': deviceId,
  };

  @override
  String toString() => 'MlinkTokens(<redacted>)';
}
