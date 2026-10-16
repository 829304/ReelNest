import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../domain/app_failure.dart';
import '../platform/windows_data_protection.dart';
import 'credential_store.dart';

/// One independently replaceable encrypted document per source/session key.
/// Different player engines never rewrite a shared credentials map.
class PortableCredentialStore implements CredentialStore {
  PortableCredentialStore({required this.directory, required this.key});
  final Future<Directory> Function() directory;
  final String key;
  final _protection = WindowsDataProtection();

  Future<File> _file() async {
    final root = await directory();
    await root.create(recursive: true);
    if (!p.isWithin(
      await root.parent.resolveSymbolicLinks(),
      await root.resolveSymbolicLinks(),
    )) {
      throw AppFailure.storage;
    }
    final name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    if (name.isEmpty || name.length > 200) throw AppFailure.storage;
    final target = File(p.join(root.path, '$name.bin'));
    if (await FileSystemEntity.type(target.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw AppFailure.storage;
    }
    return target;
  }

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      if (await file.length() > 1024 * 1024) throw AppFailure.storage;
      final value = jsonDecode(
        utf8.decode(_protection.unprotect(await file.readAsBytes())),
      );
      if (value is! Map || value['key'] != key || value['value'] is! String) {
        throw AppFailure.storage;
      }
      return value['value'] as String;
    } catch (_) {
      throw AppFailure.storage;
    }
  }

  @override
  Future<void> write(String value) async {
    File? temporary;
    try {
      final target = await _file();
      final nonce = Random.secure().nextInt(1 << 32);
      temporary = File('${target.path}.$pid.$nonce.part');
      final bytes = _protection.protect(
        utf8.encode(jsonEncode({'key': key, 'value': value})),
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (utf8.decode(_protection.unprotect(await temporary.readAsBytes())) !=
          jsonEncode({'key': key, 'value': value})) {
        throw AppFailure.storage;
      }
      // Replace atomically, preserving the previous document on any failure.
      final success = using(
        (arena) => MoveFileEx(
          _extended(temporary!.absolute.path).toPcwstr(allocator: arena),
          _extended(target.absolute.path).toPcwstr(allocator: arena),
          MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        ).value,
      );
      if (!success) throw AppFailure.storage;
    } catch (_) {
      throw AppFailure.storage;
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } on FileSystemException {
        // A leftover encrypted .part file must not replace the original result.
      }
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      throw AppFailure.storage;
    }
  }

  String _extended(String path) => path.startsWith(r'\\?\')
      ? path
      : path.startsWith(r'\\')
      ? r'\\?\UNC\' + path.substring(2)
      : r'\\?\' + path;
}
