import 'app_failure.dart';

class ServerAddress {
  const ServerAddress._(this.uri);

  final Uri uri;

  factory ServerAddress.parse(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        text.length > 2048 ||
        text.contains(RegExp(r'[\s\\]')) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !{'https', 'http'}.contains(uri.scheme)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '请输入完整的 HTTP 或 HTTPS 地址，且不要在地址中填写账号密码。',
      );
    }
    // Reading a lazily parsed port can itself fail for malformed addresses.
    try {
      if (uri.port < 1 || uri.port > 65535) {
        throw const FormatException();
      }
    } on FormatException {
      throw const AppFailure(
        FailureKind.invalidInput,
        '服务器端口必须是 1 至 65535 之间的整数。',
      );
    }
    if ((uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '请只填写服务器地址和端口，不要包含页面路径、查询参数或片段。',
      );
    }
    if (uri.scheme == 'http' &&
        !{'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase())) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '非回环服务器必须使用 HTTPS；局域网 IP 地址也需要 HTTPS。',
      );
    }
    return ServerAddress._(Uri.parse(uri.origin));
  }

  Uri endpoint(String path) => uri.resolve(path);

  @override
  String toString() => uri.toString();
}
