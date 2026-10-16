import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// DPAPI uses the current Windows user. No registry or Credential Manager
/// entries are created by this adapter; ciphertext stays in the app folder.
class WindowsDataProtection {
  Uint8List protect(List<int> bytes) => _transform(bytes, encrypt: true);
  Uint8List unprotect(List<int> bytes) => _transform(bytes, encrypt: false);

  Uint8List _transform(List<int> bytes, {required bool encrypt}) =>
      using((arena) {
        if (bytes.isEmpty || bytes.length > 1024 * 1024) {
          throw const FormatException('Invalid credential size');
        }
        final input = arena<Uint8>(bytes.length);
        input.asTypedList(bytes.length).setAll(0, bytes);
        final source = arena<CRYPT_INTEGER_BLOB>();
        source.ref
          ..cbData = bytes.length
          ..pbData = input;
        final output = arena<CRYPT_INTEGER_BLOB>();
        try {
          final result = encrypt
              ? CryptProtectData(source, null, null, null, 1, output)
              : CryptUnprotectData(source, null, null, null, 1, output);
          if (!result.value || output.ref.pbData == nullptr) {
            throw const FormatException('Credential protection failed');
          }
          return Uint8List.fromList(
            output.ref.pbData.asTypedList(output.ref.cbData),
          );
        } finally {
          input.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
          if (output.ref.pbData != nullptr) {
            output.ref.pbData
                .asTypedList(output.ref.cbData)
                .fillRange(0, output.ref.cbData, 0);
            LocalFree(HLOCAL(output.ref.pbData.cast()));
          }
        }
      });
}
