import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Windows portable data belongs to the executable, never the launcher's cwd.
/// Other platforms retain their existing platform-specific locations.
class RuntimeStoragePaths {
  RuntimeStoragePaths({Directory? root, bool? portable})
    : root = root ?? File(Platform.resolvedExecutable).parent,
      portable = portable ?? Platform.isWindows;

  static final zoneKey = Object();
  static RuntimeStoragePaths get current =>
      Zone.current[zoneKey] as RuntimeStoragePaths? ?? RuntimeStoragePaths();
  final Directory root;
  final bool portable;

  Future<Directory> support() async => portable
      ? Directory(p.join(root.path, 'userdata'))
      : getApplicationSupportDirectory();
  Future<Directory> cache() async => portable
      ? Directory(p.join(root.path, 'cache'))
      : getApplicationCacheDirectory();
  Future<Directory> logs() async => portable
      ? Directory(p.join(root.path, 'log'))
      : Directory(p.join((await support()).path, 'logs'));
  Future<Directory> temporary() async =>
      portable ? Directory(p.join(root.path, 'temp')) : Directory.systemTemp;
  Future<Directory> credentials() async =>
      Directory(p.join((await support()).path, 'credentials'));

  Future<Directory> library() async {
    if (portable) return _portableDirectory(['userdata', 'library']);
    final directory = Directory(p.join((await support()).path, 'library'));
    return directory.create(recursive: true);
  }

  /// Resolve the real SQLite location and its sidecars before handing it to
  /// the background connection. Startup preflight alone is not sufficient.
  Future<File> databaseFile() async {
    final directory = await library();
    final file = File(p.join(directory.path, 'reelnest.sqlite'));
    if (!portable) return file;
    final base = await root.resolveSymbolicLinks();
    final target = await _checkedFile(base, file);
    for (final suffix in ['-wal', '-shm', '-journal']) {
      await _checkedFile(base, File('${target.path}$suffix'));
    }
    return target;
  }

  Future<Directory> _portableDirectory(List<String> components) async {
    final base = await root.resolveSymbolicLinks();
    var directory = Directory(base);
    for (final component in components) {
      final child = Directory(p.join(directory.path, component));
      // Validate each existing parent before creating a child. In particular,
      // do not create library/ or a write probe through an external junction.
      if (await FileSystemEntity.type(child.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        await child.create();
      }
      final resolved = await child.resolveSymbolicLinks();
      _checkWithin(base, resolved);
      if (!await Directory(resolved).exists()) {
        throw const FileSystemException(
          'Portable database directory is invalid',
        );
      }
      directory = Directory(resolved);
    }
    return directory;
  }

  Future<File> _checkedFile(String base, File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return file;
    }
    final resolved = await file.resolveSymbolicLinks();
    _checkWithin(base, resolved);
    if (!await File(resolved).exists()) {
      throw const FileSystemException('Portable database file is invalid');
    }
    return File(resolved);
  }

  void _checkWithin(String base, String path) {
    if (!p.isWithin(base, path)) {
      throw const FileSystemException(
        'Portable directory escapes application root',
      );
    }
  }

  Future<void> prepare() async {
    if (!portable) return;
    final base = await root.resolveSymbolicLinks();
    for (final directory in [
      await support(),
      await cache(),
      await logs(),
      await temporary(),
      await library(),
    ]) {
      await directory.create(recursive: true);
      if (!p.isWithin(base, await directory.resolveSymbolicLinks())) {
        throw const FileSystemException(
          'Portable directory escapes application root',
        );
      }
      // Existing folders may be readable but unwritable. Never fall back to
      // AppData when an update was unpacked into a protected directory.
      final probe = await directory.createTemp('.write-probe-');
      await probe.delete();
    }
    await databaseFile();
  }
}
