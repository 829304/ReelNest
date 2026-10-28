import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

typedef _ReplaceNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _Replace = int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _MoveNative = Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _Move = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _PathsNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _Paths = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _Chmod = int Function(Pointer<Utf8>, int);

/// Same-directory native publication. A null backup means create-without-
/// overwrite; an existing destination is never deleted before replacement.
Future<bool> publishNfo(String temporary, String target, String? backup) =>
    Isolate.run(() => _publish(temporary, target, backup));

bool _publish(String temporary, String target, String? backup) => using((
  arena,
) {
  if (Platform.isWindows) {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final input = temporary.toNativeUtf16(allocator: arena),
        output = target.toNativeUtf16(allocator: arena);
    if (backup == null) {
      return kernel.lookupFunction<_MoveNative, _Move>('MoveFileExW')(
            input,
            output,
            0,
          ) !=
          0;
    }
    return kernel.lookupFunction<_ReplaceNative, _Replace>('ReplaceFileW')(
          output,
          input,
          backup.toNativeUtf16(allocator: arena),
          0,
          nullptr,
          nullptr,
        ) !=
        0;
  }
  if (Platform.isMacOS || Platform.isLinux) {
    final libc = DynamicLibrary.process();
    final link = libc.lookupFunction<_PathsNative, _Paths>('link');
    final input = temporary.toNativeUtf8(allocator: arena),
        output = target.toNativeUtf8(allocator: arena);
    if (backup == null) return link(input, output) == 0;
    final mode = File(target).statSync().mode & 0x1ff;
    if (libc.lookupFunction<_ChmodNative, _Chmod>('chmod')(input, mode) != 0) {
      return false;
    }
    if (link(output, backup.toNativeUtf8(allocator: arena)) != 0) return false;
    return libc.lookupFunction<_PathsNative, _Paths>('rename')(input, output) ==
        0;
  }
  throw UnsupportedError('NFO publication requires a desktop platform');
});
