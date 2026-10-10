import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win32/win32.dart';

typedef ExternalLinkOpener = Future<void> Function(Uri uri);
final externalLinkOpenerProvider = Provider<ExternalLinkOpener>(
  (_) => openExternalLink,
);

Future<void> openExternalLink(Uri uri) async {
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw const FormatException('Invalid external link');
  }
  if (Platform.isWindows) {
    final value = await Isolate.run(
      () => using(
        (arena) => ShellExecute(
          null,
          'open'.toPcwstr(allocator: arena),
          uri.toString().toPcwstr(allocator: arena),
          null,
          null,
          SW_SHOWNORMAL,
        ).address,
      ),
    );
    if (value <= 32) throw const FileSystemException('无法打开浏览器');
  } else {
    final process = await Process.start(
      Platform.isMacOS ? '/usr/bin/open' : 'xdg-open',
      [uri.toString()],
      mode: ProcessStartMode.detached,
    );
    if (process.pid <= 0) throw const FileSystemException('无法打开浏览器');
  }
}
