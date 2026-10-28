import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/sources/filesystem/local_file_monitor.dart';

void main() {
  for (final perDirectory in [false, true]) {
    test(
      'real filesystem emits nested changes and stops after close (perDirectory=$perDirectory)',
      () async {
        if (Platform.isLinux && !perDirectory) return;
        final root = await Directory.systemTemp.createTemp('reelnest-watch-');
        final nested = await Directory(p.join(root.path, 'nested')).create();
        final changes = <LocalFileChange>[];
        final source = MediaSource(
          id: 'watch',
          kind: MediaSourceKind.localFolder,
          name: 'fixture',
          location: root.path,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final monitor = await LocalFileMonitor.start(
          source,
          changes.add,
          perDirectory: perDirectory,
        );
        try {
          final video = await File(p.join(nested.path, 'one.mkv'))
              .writeAsString('fixture');
          await _until(() => changes.any((e) => p.equals(e.path, video.path)));
          final newDirectory = await Directory(p.join(root.path, 'new'))
              .create();
          await _until(
            () => changes.any(
              (e) => e.fullScan && p.equals(e.path, newDirectory.path),
            ),
          );
          // Allow the per-directory tree to register the newly created directory.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          final newVideo = await File(p.join(newDirectory.path, 'two.mkv'))
              .writeAsString('fixture');
          await _until(
            () => changes.any((e) => p.equals(e.path, newVideo.path)),
          );
          await monitor.close();
          final count = changes.length;
          await video.writeAsString('after close');
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(changes.length, count);
        } finally {
          await monitor.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for filesystem notification');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
