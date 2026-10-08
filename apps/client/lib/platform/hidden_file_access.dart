import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

typedef HiddenPathLookup = Future<Set<String>> Function(List<String> paths);

/// Batches native queries off the UI isolate, including potentially slow UNC
/// paths. Dot names remain hidden on every platform, as in the existing scan.
Future<Set<String>> hiddenFilePaths(List<String> paths) async {
  final hidden = paths
      .where((path) => p.basename(path).startsWith('.'))
      .toSet();
  if (!Platform.isWindows) return hidden;
  final candidates = paths.where((path) => !hidden.contains(path)).toList();
  if (candidates.isNotEmpty) {
    hidden.addAll(await Isolate.run(() => _windowsHiddenPaths(candidates)));
  }
  return hidden;
}

Set<String> _windowsHiddenPaths(List<String> paths) => using((arena) {
  final hidden = <String>{};
  for (final path in paths) {
    final result = GetFileAttributes(path.toPcwstr(allocator: arena));
    // DWORD failure sentinel; GetLastError is meaningful only on failure.
    if (result.value == 0xffffffff) {
      throw FileSystemException(
        '无法读取文件隐藏属性',
        path,
        OSError('GetFileAttributesW failed', result.error),
      );
    }
    if ((result.value & FILE_ATTRIBUTE_HIDDEN) != 0) hidden.add(path);
  }
  return hidden;
});
