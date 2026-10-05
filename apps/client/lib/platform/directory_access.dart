import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../domain/media_source.dart';

abstract interface class DirectoryAccess {
  bool get supported;
  String get unavailableReason;
  Future<String?> choose();
}

class DesktopDirectoryAccess implements DirectoryAccess {
  @override
  bool get supported => Platform.isWindows || Platform.isLinux;

  @override
  String get unavailableReason =>
      Platform.isMacOS ? 'macOS 目录的持久访问授权尚待接入。' : '此平台的文件授权入口尚待接入，暂不能添加目录。';

  @override
  Future<String?> choose() async {
    if (!supported) throw SourceFailure(unavailableReason);
    return getDirectoryPath(confirmButtonText: '选择媒体目录');
  }
}
