import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../api/mlink/mlink_client.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/library_catalog.dart';
import '../../../domain/media.dart';
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
  ServerDescriptor? _verifiedServer;
  bool _restored = false;
  bool _requiresLogin = false;
  bool _pendingSave = false;
  bool _pendingClear = false;
  Future<void> _pending = Future<void>.value();
  final _changes = StreamController<void>.broadcast();
  int _generation = 0;

  int get generation => _generation;
  Stream<void> get changes => _changes.stream;
  void _notify() { if (!_changes.isClosed) _changes.add(null); }
  void dispose() { unawaited(_changes.close()); }

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
    final generation = _generation;
    final value = await _store.read();
    if (generation != _generation) throw AppFailure.sessionExpired;
    _session = value == null ? null : StoredSession.decode(value);
    _verifiedServer = null;
    _restored = true;
    if (_session != null) _generation++;
  }

  Future<void> connect({
    required String address,
    required String username,
    required String password,
  }) => _exclusive(() async {
    await _restore();
    if (_pendingClear) throw AppFailure.storage;
    final generation = _generation;
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
    if (generation != _generation) throw AppFailure.sessionExpired;
    _session = StoredSession(
      connection: ServerConnection(
        address: target,
        server: server,
        username: account,
      ),
      tokens: tokens,
    );
    _verifiedServer = server;
    _requiresLogin = false;
    _generation++;
    _pendingSave = true;
    try { await _save(); } finally { _notify(); }
  });

  Future<void> _save() async {
    if (!_pendingSave) return;
    await _store.write(_session!.encode());
    _pendingSave = false;
  }

  Future<LibraryCatalog> loadCatalog() async {
    await restore();
    return _read(_generation, _client.categories, verifyServer: true);
  }

  Future<MediaPage> browse(int scope, String type, MediaSort sort, int offset) =>
      _read(scope, (address, token) => _client.browse(
        address, token, type: type, sort: sort, offset: offset));

  Future<MediaDetail> detail(int scope, String id, bool isSeries) =>
      _read(scope, (address, token) {
        if (isSeries && _verifiedServer!.capabilities.contains('series-detail')) {
          return _client.seriesDetail(address, token, id);
        }
        return _client.detail(address, token, id, isSeries: isSeries);
      }, verifyServer: isSeries);

  Future<MediaPage> episodes(int scope, String id, String season, int offset) =>
      _read(scope, (address, token) => _client.episodes(
        address, token, seriesId: id, season: season, offset: offset));

  Future<Uint8List> artwork(int scope, String id) =>
      _read(scope, (address, token) => _client.artwork(address, token, id));

  void _ensureScope(int scope) {
    if (scope != _generation || _session == null || _requiresLogin || _pendingClear) {
      throw AppFailure.sessionExpired;
    }
  }

  void _expire() {
    _requiresLogin = true;
    _generation++;
    _notify();
  }

  Future<StoredSession> _prepare(int scope, bool verifyServer) => _exclusive(() async {
    await _restore();
    _ensureScope(scope);
    await _save();
    _ensureScope(scope);
    if (verifyServer) {
      final server = await _client.discover(_session!.connection.address);
      _ensureScope(scope);
      if (server.id != _session!.connection.server.id) {
        _expire();
        throw const AppFailure(FailureKind.incompatibleServer,
          '该地址的服务器身份已改变，请重新连接。');
      }
      // Re-discover before opening a series so upgrades are visible without
      // replacing credentials or trusting a descriptor restored from disk.
      _verifiedServer = server;
    }
    if (!_session!.tokens.accessExpiresAt.isAfter(
      _now().add(const Duration(seconds: 30)),
    )) {
      await _refresh();
    }
    _ensureScope(scope);
    return _session!;
  });

  Future<T> _read<T>(int scope,
    Future<T> Function(ServerAddress, String) request, {
    bool verifyServer = false,
  }) async {
    final session = await _prepare(scope, verifyServer);
    _ensureScope(scope);
    try {
      final value = await request(session.connection.address, session.tokens.accessToken);
      _ensureScope(scope);
      return value;
    } on AppFailure catch (error) {
      _ensureScope(scope);
      if (error.kind != FailureKind.unauthorized) rethrow;
      // Concurrent 401s reuse a rotation already performed for this token.
      final rotated = await _exclusive(() async {
        _ensureScope(scope);
        await _save();
        _ensureScope(scope);
        if (_session!.tokens.accessToken == session.tokens.accessToken) {
          await _refresh();
        }
        _ensureScope(scope);
        return _session!;
      });
      _ensureScope(scope);
      try {
        final value = await request(rotated.connection.address, rotated.tokens.accessToken);
        _ensureScope(scope);
        return value;
      } on AppFailure catch (retryError) {
        _ensureScope(scope);
        if (retryError.kind == FailureKind.unauthorized) {
          _expire();
          throw AppFailure.sessionExpired;
        }
        rethrow;
      }
    }
  }

  Future<void> _refresh() async {
    final session = _session!;
    final scope = _generation;
    if (!session.tokens.refreshExpiresAt.isAfter(_now())) {
      _expire();
      throw AppFailure.sessionExpired;
    }
    try {
      final tokens = await _client.refresh(
        session.connection.address,
        session.tokens.refreshToken,
      );
      _ensureScope(scope);
      // Keep rotated tokens in memory even if storage fails. Retry persistence
      // before another request; never reuse the invalidated refresh token.
      _session = session.withTokens(tokens);
      _pendingSave = true;
      await _save();
      if (!tokens.accessExpiresAt.isAfter(_now())) {
        throw AppFailure.sessionExpired;
      }
    } on AppFailure catch (error) {
      if (error.kind == FailureKind.sessionExpired && scope == _generation) _expire();
      if (error.kind == FailureKind.storage) _notify();
      rethrow;
    }
  }

  Future<void> signOut() {
    // Stop using in-memory credentials immediately, even if deletion fails.
    _session = null;
    _verifiedServer = null;
    _requiresLogin = false;
    _pendingSave = false;
    _pendingClear = true;
    _generation++;
    _notify();
    return _exclusive(() async {
      await _store.clear();
      _pendingClear = false;
      _restored = true;
      _notify();
    });
  }
}
