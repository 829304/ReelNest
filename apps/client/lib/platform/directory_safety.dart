import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

typedef DirectoryIdentityLookup = Future<String?> Function(String path);

/// A readable directory is insufficient proof that a mounted filesystem is
/// still present. No media files are created or modified by these probes.
Future<String?> directoryIdentity(String path) async {
  try {
    await Directory(path).list(followLinks: false).take(1).drain<void>();
    if (Platform.isWindows) {
      return await Isolate.run(() => _windowsIdentity(path));
    }
    if (Platform.isLinux) {
      return await linuxDirectoryIdentity(path);
    }
    if (Platform.isMacOS) {
      final process = await Process.start('/sbin/mount', const []);
      Future<String> read(Stream<List<int>> stream) async {
        final bytes = <int>[];
        await for (final chunk in stream) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            process.kill(ProcessSignal.sigkill);
            throw const FormatException('Mount table exceeds probe limit');
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      }

      try {
        final values = await Future.wait<Object>([
          read(process.stdout),
          read(process.stderr),
          process.exitCode,
        ], eagerError: true).timeout(const Duration(seconds: 5));
        if (values[2] != 0) return null;
        return macMountIdentity(path, values[0] as String);
      } finally {
        process.kill(ProcessSignal.sigkill);
      }
    }
  } on Exception {
    // Permissions, unavailable protocol/mount information and probe errors are
    // unknown, never proof that an indexed file has disappeared.
    return null;
  }
  return null;
}

String? _windowsIdentity(String path) => using((arena) {
  const capacity = 32768;
  final rootBuffer = arena<Uint16>(capacity).cast<Utf16>();
  if (!GetVolumePathName(
    path.toPcwstr(allocator: arena),
    PWSTR(rootBuffer),
    capacity,
  ).value) {
    return null;
  }
  final root = rootBuffer.toDartString();
  final serial = arena<Uint32>();
  final fs = arena<Uint16>(capacity).cast<Utf16>();
  if (!GetVolumeInformation(
    root.toPcwstr(allocator: arena),
    null,
    0,
    serial,
    null,
    null,
    PWSTR(fs),
    capacity,
  ).value) {
    return null;
  }
  String name;
  if (GetDriveType(root.toPcwstr(allocator: arena)) == DRIVE_REMOTE) {
    if (root.startsWith(r'\\')) {
      name = root;
    } else {
      final remote = arena<Uint16>(capacity).cast<Utf16>();
      final length = arena<Uint32>()..value = capacity;
      final connect = DynamicLibrary.open('mpr.dll')
          .lookupFunction<
            Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>),
            int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Uint32>)
          >('WNetGetConnectionW');
      if (connect(
            root.substring(0, 2).toNativeUtf16(allocator: arena),
            remote,
            length,
          ) !=
          0) {
        return null;
      }
      name = remote.toDartString();
    }
  } else {
    final volume = arena<Uint16>(capacity).cast<Utf16>();
    if (!GetVolumeNameForVolumeMountPoint(
      root.toPcwstr(allocator: arena),
      PWSTR(volume),
      capacity,
    ).value) {
      return null;
    }
    name = volume.toDartString();
  }
  return jsonEncode([
    'windows',
    name.toLowerCase(),
    serial.value,
    fs.toDartString(),
  ]);
});

String _decodeMount(String text) => text.replaceAllMapped(
  RegExp(r'\\([0-7]{3})'),
  (match) => String.fromCharCode(int.parse(match[1]!, radix: 8)),
);

// Strip user information from network mount sources before persisting them.
String _safeMountSource(String source) => source.replaceFirstMapped(
  RegExp(r'^(//|[a-zA-Z]+://)[^/]+@'),
  (match) => match[1]!,
);

typedef LinuxVolumeUuidLookup = Future<String?> Function(LinuxMount mount);

class LinuxMount {
  const LinuxMount({
    required this.id,
    required this.majorMinor,
    required this.root,
    required this.path,
    required this.fileSystem,
    required this.source,
  });
  final String id;
  final String majorMinor;
  final String root;
  final String path;
  final String fileSystem;
  final String source;
  bool get isNetwork =>
      const {'cifs', 'smb3', 'nfs', 'nfs4', 'fuse.sshfs'}.contains(fileSystem);

  bool sameMount(LinuxMount other) =>
      id == other.id &&
      majorMinor == other.majorMinor &&
      root == other.root &&
      path == other.path &&
      fileSystem == other.fileSystem &&
      source == other.source;

  String? identity(String? uuid) {
    final stableUuid = uuid?.trim().toLowerCase();
    if (!isNetwork && (stableUuid == null || stableUuid.isEmpty)) return null;
    return jsonEncode([
      'linux',
      path,
      root,
      fileSystem,
      isNetwork
          ? ['network', _safeMountSource(source)]
          : ['volume', stableUuid],
    ]);
  }
}

LinuxMount? _linuxMount(String path, String mountInfo) {
  final context = p.Context(style: p.Style.posix);
  final normalized = context.normalize(path);
  LinuxMount? selected;
  for (final line in const LineSplitter().convert(mountInfo)) {
    final fields = line.split(' ');
    final separator = fields.indexOf('-');
    if (separator < 6 ||
        fields.length < separator + 4 ||
        !RegExp(r'^\d+:\d+$').hasMatch(fields[2])) {
      continue;
    }
    final mount = _decodeMount(fields[4]);
    if (normalized != mount && !context.isWithin(mount, normalized)) continue;
    if (selected != null && mount.length < selected.path.length) continue;
    selected = LinuxMount(
      id: fields[0],
      majorMinor: fields[2],
      root: _decodeMount(fields[3]),
      path: mount,
      fileSystem: fields[separator + 1],
      source: _decodeMount(fields[separator + 2]),
    );
  }
  return selected;
}

/// Device names and major/minor numbers locate a volume, but cannot identify
/// it across unplug/replug. Only a UUID proves a local volume's identity.
String? linuxMountIdentity(
  String path,
  String mountInfo, {
  Map<String, String> volumeUuids = const {},
}) {
  final mount = _linuxMount(path, mountInfo);
  if (mount == null) return null;
  return mount.identity(volumeUuids[mount.majorMinor]);
}

Future<String?> linuxDirectoryIdentity(
  String path, {
  Future<String> Function()? readMountInfo,
  LinuxVolumeUuidLookup? volumeUuid,
}) async {
  final read =
      readMountInfo ?? () => File('/proc/self/mountinfo').readAsString();
  final lookup = volumeUuid ?? _linuxVolumeUuid;
  try {
    final first = _linuxMount(path, await read());
    if (first == null) return null;
    final firstUuid = first.isNetwork ? null : await lookup(first);
    final identity = first.identity(firstUuid);
    if (identity == null) return null;
    final current = _linuxMount(path, await read());
    if (current == null || !first.sameMount(current)) return null;
    final currentUuid = current.isNetwork ? null : await lookup(current);
    return current.identity(currentUuid) == identity ? identity : null;
  } on Exception {
    return null;
  }
}

/// Explicit output columns and flat JSON avoid lsblk's human-readable defaults.
/// For virtual device numbers (e.g. btrfs), use the mounted block source only.
String? linuxVolumeUuidFromLsblk(LinuxMount mount, String output) {
  final decoded = jsonDecode(output);
  if (decoded is! Map || decoded['blockdevices'] is! List) return null;
  final matches = <Map>[];
  for (final device in decoded['blockdevices'] as List) {
    if (device is! Map) continue;
    final byNumber =
        !mount.majorMinor.startsWith('0:') &&
        device['maj:min'] == mount.majorMinor;
    final byVirtualSource =
        mount.majorMinor.startsWith('0:') &&
        mount.source.startsWith('/dev/') &&
        device['name'] == mount.source;
    if (byNumber || byVirtualSource) matches.add(device);
  }
  if (matches.isEmpty) return null;
  final uuids = <String>{};
  for (final device in matches) {
    final uuid = device['uuid'];
    if (uuid is! String || uuid.trim().isEmpty) return null;
    uuids.add(uuid.trim().toLowerCase());
  }
  return uuids.length == 1 ? uuids.single : null;
}

Future<String?> _linuxVolumeUuid(LinuxMount mount) async {
  final process = await Process.start('lsblk', const [
    '--json',
    '--list',
    '--paths',
    '--output',
    'NAME,MAJ:MIN,UUID',
  ]);
  Future<String> read(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        process.kill(ProcessSignal.sigkill);
        throw const FormatException('Volume probe exceeds size limit');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  try {
    // Drain both pipes while waiting for exit; a full pipe cannot stall lsblk.
    final values = await Future.wait<Object>([
      read(process.stdout),
      read(process.stderr),
      process.exitCode,
    ], eagerError: true).timeout(const Duration(seconds: 5));
    if (values[2] != 0) return null;
    return linuxVolumeUuidFromLsblk(mount, values[0] as String);
  } finally {
    process.kill(ProcessSignal.sigkill);
  }
}

String? macMountIdentity(String path, String mountTable) {
  final context = p.Context(style: p.Style.posix);
  final normalized = context.normalize(path);
  String? identity;
  var longest = -1;
  for (final line in const LineSplitter().convert(mountTable)) {
    final on = line.indexOf(' on '), options = line.lastIndexOf(' (');
    if (on < 0 || options <= on) continue;
    final mount = line.substring(on + 4, options);
    if (normalized != mount && !context.isWithin(mount, normalized)) continue;
    if (mount.length < longest) continue;
    longest = mount.length;
    identity = jsonEncode([
      'macos',
      mount,
      _safeMountSource(line.substring(0, on)),
      line.substring(options + 2).split(',').first.replaceAll(')', ''),
    ]);
  }
  return identity;
}

/// Prove absence by listing ancestors. File.exists/type can hide I/O failures
/// behind a false/notFound result; a failed listing instead preserves indexes.
Future<bool> fileDefinitelyMissing(String root, String path) async {
  final context = p.context;
  if (!context.isWithin(root, path)) return false;
  var directory = root;
  final parts = context.split(context.relative(path, from: root));
  for (var i = 0; i < parts.length; i++) {
    FileSystemEntity? found;
    final expected = Platform.isWindows ? parts[i].toLowerCase() : parts[i];
    await for (final entity in Directory(directory).list(followLinks: false)) {
      final name = context.basename(entity.path);
      if ((Platform.isWindows ? name.toLowerCase() : name) == expected) {
        found = entity;
        break;
      }
    }
    if (found == null) return true;
    if (i == parts.length - 1 || found is! Directory) return false;
    directory = found.path;
  }
  return false;
}
