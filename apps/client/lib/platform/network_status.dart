import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Unknown interface state is never permission for Wi-Fi-only downloads.
Future<bool> desktopWifiAvailable() async {
  try {
    if (Platform.isWindows) return await Isolate.run(_windowsWifi);
    if (Platform.isLinux) {
      final table = await File('/proc/net/route').readAsString();
      final routes = linuxDefaultRoutes(table);
      if (routes.isEmpty) {
        final ipv6 = await File('/proc/net/ipv6_route').readAsString();
        for (final line in ipv6.split('\n')) {
          final p = line.trim().split(RegExp(r'\s+'));
          if (p.length >= 10 &&
              p[0] == '0' * 32 &&
              p[1] == '00' &&
              ((int.tryParse(p[8], radix: 16) ?? 0) & 1) == 1) {
            routes.add(p[9]);
          }
        }
      }
      return routes.isNotEmpty &&
          await Directory('/sys/class/net/${routes.first}/wireless').exists();
    }
    if (Platform.isMacOS) {
      var route = await _probe('/sbin/route', ['-n', 'get', 'default']);
      route ??= await _probe('/sbin/route', ['-n', 'get', '-inet6', 'default']);
      final name = RegExp(r'interface:\s*([a-zA-Z0-9]+)')
          .firstMatch(route ?? '')
          ?.group(1);
      if (name == null) return false;
      final power = await _probe('/usr/sbin/networksetup', [
        '-getairportpower',
        name,
      ]);
      return RegExp(r':\s*On\s*$', multiLine: true).hasMatch(power ?? '');
    }
  } on Exception {
    return false;
  }
  return false;
}

List<String> linuxDefaultRoutes(String table) {
  final routes = <({String name, int metric})>[];
  for (final line in table.split('\n').skip(1)) {
    final p = line.trim().split(RegExp(r'\s+'));
    if (p.length < 8 ||
        p[1] != '00000000' ||
        p[7] != '00000000' ||
        ((int.tryParse(p[3], radix: 16) ?? 0) & 1) == 0) {
      continue;
    }
    if (!RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(p[0])) continue;
    routes.add((name: p[0], metric: int.tryParse(p[6]) ?? 0x7fffffff));
  }
  routes.sort((a, b) => a.metric.compareTo(b.metric));
  return routes.map((r) => r.name).toList();
}

bool _windowsWifi() => using((arena) {
  final size = arena<Uint32>()..value = 64 * 1024;
  var buffer = arena<Uint8>(size.value).cast<IP_ADAPTER_ADDRESSES_LH>();
  var result = GetAdaptersAddresses(
    AF_UNSPEC,
    GAA_FLAG_INCLUDE_GATEWAYS,
    buffer,
    size,
  );
  if (result == ERROR_BUFFER_OVERFLOW && size.value <= 4 * 1024 * 1024) {
    buffer = arena<Uint8>(size.value).cast<IP_ADAPTER_ADDRESSES_LH>();
    result = GetAdaptersAddresses(
      AF_UNSPEC,
      GAA_FLAG_INCLUDE_GATEWAYS,
      buffer,
      size,
    );
  }
  if (result != 0) return false;
  // Query route selection rather than guessing from adapter metrics. These
  // addresses are inputs to the OS route table only; no packets are sent.
  final best = DynamicLibrary.open('iphlpapi.dll')
      .lookupFunction<
        Uint32 Function(Pointer<SOCKADDR>, Pointer<Uint32>),
        int Function(Pointer<SOCKADDR>, Pointer<Uint32>)
      >('GetBestInterfaceEx');
  var found = false;
  for (final family in [AF_INET, AF_INET6]) {
    final address = arena<Uint8>(28);
    address.cast<Uint16>().value = family;
    if (family == AF_INET) {
      for (var i = 4; i < 8; i++) {
        address[i] = 8;
      }
    } else {
      const destination = [
        0x20,
        0x01,
        0x48,
        0x60,
        0x48,
        0x60,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0x88,
        0x88,
      ];
      for (var i = 0; i < 16; i++) {
        address[8 + i] = destination[i];
      }
    }
    final index = arena<Uint32>();
    if (best(address.cast<SOCKADDR>(), index) != 0) continue;
    var wifi = false;
    for (var next = buffer; next != nullptr; next = next.ref.Next) {
      final adapter = next.ref;
      final id = family == AF_INET ? adapter.IfIndex : adapter.Ipv6IfIndex;
      if (id == index.value && adapter.OperStatus == IfOperStatusUp) {
        wifi = adapter.IfType == 71; // IANA ieee80211.
        break;
      }
    }
    if (!wifi) return false; // Mixed or unknown routes fail closed.
    found = true;
  }
  return found;
});

Future<String?> _probe(String executable, List<String> arguments) async {
  final process = await Process.start(executable, arguments, runInShell: false);
  Future<String> read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 128 * 1024) {
        process.kill(ProcessSignal.sigkill);
        throw const FormatException('Network probe output limit');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  try {
    final values = await Future.wait<Object>([
      read(process.stdout),
      read(process.stderr),
      process.exitCode,
    ], eagerError: true).timeout(const Duration(seconds: 4));
    return values[2] == 0 ? values[0] as String : null;
  } finally {
    process.kill(ProcessSignal.sigkill);
  }
}
