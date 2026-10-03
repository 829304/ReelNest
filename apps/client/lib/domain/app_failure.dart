enum FailureKind {
  invalidInput,
  incompatibleServer,
  invalidResponse,
  invalidCredentials,
  unauthorized,
  sessionExpired,
  forbidden,
  rateLimited,
  setupRequired,
  network,
  timeout,
  certificate,
  storage,
  server,
  unexpected,
}

/// Only deliberate, credential-free messages cross into presentation state.
class AppFailure implements Exception {
  const AppFailure(this.kind, this.message);

  final FailureKind kind;
  final String message;

  static const invalidResponse = AppFailure(
    FailureKind.invalidResponse,
    '服务器返回的数据不符合 Mlink v1 协议。',
  );
  static const sessionExpired = AppFailure(
    FailureKind.sessionExpired,
    '登录已过期，请重新输入密码登录。',
  );
  static const storage = AppFailure(
    FailureKind.storage,
    '无法访问系统安全存储。请解锁系统钥匙串或凭据服务后重试。',
  );

  static AppFailure from(Object error) => error is AppFailure
      ? error
      : const AppFailure(FailureKind.unexpected, '操作未完成，请重试。');

  @override
  String toString() => 'AppFailure(${kind.name})';
}
