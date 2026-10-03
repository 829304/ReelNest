import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/service_providers.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/library_catalog.dart';
import '../../../domain/server_connection.dart';
import '../data/server_repository.dart';

class ServerConnectionState {
  const ServerConnectionState({
    this.busy = false,
    this.activity,
    this.connection,
    this.catalog,
    this.failure,
    this.requiresLogin = false,
    this.needsRestore = false,
    this.pendingClear = false,
    this.pendingSave = false,
  });

  final bool busy;
  final String? activity;
  final ServerConnection? connection;
  final LibraryCatalog? catalog;
  final AppFailure? failure;
  final bool requiresLogin;
  final bool needsRestore;
  final bool pendingClear;
  final bool pendingSave;
}

final connectionControllerProvider =
    NotifierProvider<ConnectionController, ServerConnectionState>(
      ConnectionController.new,
    );

class ConnectionController extends Notifier<ServerConnectionState> {
  late ServerRepository _repository;
  bool _disposed = false;

  @override
  ServerConnectionState build() {
    _repository = ref.read(serverRepositoryProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(_restore));
    return const ServerConnectionState(busy: true, activity: '正在读取本机连接…');
  }

  Future<void> _restore() async {
    if (_disposed) return;
    await _perform('正在恢复连接…', () async {
      await _repository.restore();
      return _repository.connection == null
          ? null
          : await _repository.loadCatalog();
    });
  }

  Future<void> connect({
    required String address,
    required String username,
    required String password,
  }) async {
    if (state.busy) return;
    await _perform('正在验证服务器并登录…', () async {
      await _repository.connect(
        address: address,
        username: username,
        password: password,
      );
      if (!_disposed) {
        state = ServerConnectionState(
          busy: true,
          activity: '正在读取媒体库…',
          connection: _repository.connection,
        );
      }
      return _repository.loadCatalog();
    }, preserveCatalog: false);
  }

  Future<void> retry() async {
    if (state.busy) return;
    if (state.pendingClear) return signOut();
    if (state.needsRestore) return _restore();
    if (_repository.connection == null || _repository.requiresLogin) return;
    await _perform('正在更新媒体库…', _repository.loadCatalog);
  }

  Future<void> signOut() async {
    if (state.busy) return;
    await _perform('正在清除本机连接…', () async {
      await _repository.signOut();
      return null;
    }, preserveCatalog: false);
  }

  Future<void> _perform(
    String activity,
    Future<LibraryCatalog?> Function() operation, {
    bool preserveCatalog = true,
  }) async {
    final previousCatalog = preserveCatalog ? state.catalog : null;
    state = ServerConnectionState(
      busy: true,
      activity: activity,
      connection: _repository.connection,
      catalog: previousCatalog,
      requiresLogin: _repository.requiresLogin,
      pendingClear: _repository.pendingClear,
      pendingSave: _repository.pendingSave,
    );
    LibraryCatalog? catalog = previousCatalog;
    AppFailure? failure;
    try {
      catalog = await operation();
    } catch (error) {
      failure = AppFailure.from(error);
    }
    if (_disposed) return;
    state = ServerConnectionState(
      connection: _repository.connection,
      catalog: _repository.connection == null || _repository.requiresLogin
          ? null
          : catalog,
      failure: failure,
      requiresLogin: _repository.requiresLogin,
      needsRestore: !_repository.restored,
      pendingClear: _repository.pendingClear,
      pendingSave: _repository.pendingSave,
    );
  }
}
