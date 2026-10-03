import 'dart:convert';

import '../../../api/mlink/mlink_client.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/library_catalog.dart';
import '../../../domain/server_address.dart';
import '../../../domain/server_connection.dart';
import '../../../storage/credential_store.dart';
import 'stored_session.dart';

class ServerRepository {
  ServerRepository({
    required MlinkClient client,
    required CredentialStore store,
    required String platform,
    DateTime Function()? now,
  }) : _client = client,
       _store = store,
       _platform = platform,
       _now = now ?? DateTime.now;

  final MlinkClient _client;
  final CredentialStore _store;
  final String _platform;
  final DateTime Function() _now;
  StoredSession? _session;
  bool _restored = false;
  bool _requiresLogin = false;
  bool _pendingSave = false;
  bool _pendingClear = false;
  Future<void> _pending = Future<void>.value();

  ServerConnection? get connection => _session?.connection;
  bool get requiresLogin => _requiresLogin;
  bool get pendingClear => _pendingClear;
  bool get pendingSave => _pendingSave;
  bool get restored => _restored;

  // Serialize restore, token rotation and removal. A late refresh cannot write
  // credentials back after a queued sign-out or replace a newer connection.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> restore() => _exclusive(_restore);

  Future<void> _restore() async {
    if (_restored) return;
    final value = await _store.read();
    _session = value == null ? null : StoredSession.decode(value);
    _restored = true;
  }

  Future<void> connect({
    required String address,
    required String username,
    required String password,
  }) => _exclusive(() async {
    await _restore();
    if (_pendingClear) throw AppFailure.storage;
    final target = ServerAddress.parse(address);
    final account = username.trim();
    if (account.isEmpty || utf8.encode(account).length > 128) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '请填写用户名，长度不得超过 128 字节。',
      );
    }
    if (password.isEmpty || utf8.encode(password).length > 1024) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '请填写密码，长度不得超过 1024 字节。',
      );
    }
    final server = await _client.discover(target);
    final tokens = await _client.login(
      address: target,
      username: account,
      password: password,
      deviceName: 'ReelNest ($_platform)',
      platform: _platform,
    );
    if (!tokens.refreshExpiresAt.isAfter(_now())) {
      throw AppFailure.invalidResponse;
    }
    _session = StoredSession(
      connection: ServerConnection(
        address: target,
        server: server,
        username: account,
      ),
      tokens: tokens,
    );
    _requiresLogin = false;
    _pendingSave = true;
    await _save();
  });

  Future<void> _save() async {
    if (!_pendingSave) return;
    await _store.write(_session!.encode());
    _pendingSave = false;
  }

  Future<LibraryCatalog> loadCatalog() => _exclusive(() async {
    await _restore();
    if (_pendingClear) throw AppFailure.storage;
    if (_session == null || _requiresLogin) throw AppFailure.sessionExpired;
    await _save();
    // Do not send stored credentials when the address points to a new server.
    final server = await _client.discover(_session!.connection.address);
    if (server.id != _session!.connection.server.id) {
      throw const AppFailure(
        FailureKind.incompatibleServer,
        '该地址的服务器身份已改变。请退出此设备后重新连接。',
      );
    }
    var refreshed = false;
    if (!_session!.tokens.accessExpiresAt.isAfter(
      _now().add(const Duration(seconds: 30)),
    )) {
      await _refresh();
      refreshed = true;
    }
    try {
      return await _fetchCatalog();
    } on AppFailure catch (error) {
      if (error.kind != FailureKind.unauthorized) rethrow;
      // A newly issued access token being rejected requires a new login.
      if (refreshed) {
        _requiresLogin = true;
        throw AppFailure.sessionExpired;
      }
      // At most one token rotation per catalog operation.
      await _refresh();
      try {
        return await _fetchCatalog();
      } on AppFailure catch (retryError) {
        if (retryError.kind == FailureKind.unauthorized) {
          _requiresLogin = true;
          throw AppFailure.sessionExpired;
        }
        rethrow;
      }
    }
  });

  Future<LibraryCatalog> _fetchCatalog() => _client.categories(
    _session!.connection.address,
    _session!.tokens.accessToken,
  );

  Future<void> _refresh() async {
    final session = _session!;
    if (!session.tokens.refreshExpiresAt.isAfter(_now())) {
      _requiresLogin = true;
      throw AppFailure.sessionExpired;
    }
    try {
      final tokens = await _client.refresh(
        session.connection.address,
        session.tokens.refreshToken,
      );
      // Keep rotated tokens in memory even if storage fails. Retry persistence
      // before another request; never reuse the invalidated refresh token.
      _session = session.withTokens(tokens);
      _pendingSave = true;
      await _save();
      if (!tokens.accessExpiresAt.isAfter(_now())) {
        _requiresLogin = true;
        throw AppFailure.sessionExpired;
      }
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.sessionExpired) _requiresLogin = true;
      rethrow;
    }
  }

  Future<void> signOut() => _exclusive(() async {
    // Stop using in-memory credentials immediately, even if deletion fails.
    _session = null;
    _requiresLogin = false;
    _pendingSave = false;
    _pendingClear = true;
    await _store.clear();
    _pendingClear = false;
    _restored = true;
  });
}
