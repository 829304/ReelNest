import 'dart:convert';

import '../../../api/mlink/mlink_codec.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/server_address.dart';
import '../../../domain/server_connection.dart';

class StoredSession {
  const StoredSession({required this.connection, required this.tokens});

  final ServerConnection connection;
  final MlinkTokens tokens;

  factory StoredSession.decode(String value) {
    try {
      if (value.length > 65536) throw AppFailure.invalidResponse;
      final json = jsonObject(jsonDecode(value));
      if (json['version'] != 1) throw AppFailure.invalidResponse;
      return StoredSession(
        connection: ServerConnection(
          address: ServerAddress.parse(jsonText(json['address'], 2048)),
          server: decodeDescriptor(jsonObject(json['server'])),
          username: jsonText(json['username'], 128),
        ),
        tokens: MlinkTokens.fromJson(jsonObject(json['tokens'])),
      );
    } catch (_) {
      throw const AppFailure(
        FailureKind.storage,
        '已保存的会话无法读取，请清除本机连接后重新登录。',
      );
    }
  }

  String encode() => jsonEncode({
    'version': 1,
    'address': connection.address.toString(),
    'server': encodeDescriptor(connection.server),
    'username': connection.username,
    'tokens': tokens.toJson(),
  });

  StoredSession withTokens(MlinkTokens value) =>
      StoredSession(connection: connection, tokens: value);

  @override
  String toString() => 'StoredSession(<redacted>)';
}
