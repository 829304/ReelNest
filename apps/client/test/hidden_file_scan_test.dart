import 'dart:io';

import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/hidden_file_access.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:win32/win32.dart';

void main() {
  late Directory root;
  late SourceRepository repository;

  Future<File> media(String name) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsString('index fixture, not playable');
  }

  SourceRepository store(FileSourceAdapter adapter) => SourceRepository(
    database: LibraryDatabase(NativeDatabase.memory()),
    adapters: {MediaSourceKind.localFolder: adapter},
  );

  Future<MediaSource> add() => repository.add(
    kind: MediaSourceKind.localFolder,
    name: 'Hidden attributes',
    location: root.path,
    minimumFileSize: 0,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reelnest-hidden-test-');
    repository = store(FileSourceAdapter());
  });
  tearDown(() async {
    await repository.close();
    final temp = p.normalize(Directory.systemTemp.absolute.path);
    final target = p.normalize(root.absolute.path);
    if (!p.isWithin(temp, target) ||
        !p.basename(target).startsWith('reelnest-hidden-test-')) {
      throw StateError('Refusing cleanup outside the test sandbox');
    }
    await root.delete(recursive: true);
  });

  test('Windows hidden files and directories are excluded before recursion; disabling restores both', () async {
    final hiddenFile = await media('隐藏影片.mp4');
    final hiddenChild = await media('隐藏目录/child.mp4');
    await media('visible.mp4');
    await media('.dot.mp4');
    final protectedPaths = [hiddenFile.path, hiddenChild.parent.path];
    final originalAttributes = <String, int>{};
    try {
      using((arena) {
        for (final path in protectedPaths) {
          final pointer = path.toPcwstr(allocator: arena);
          final attributes = GetFileAttributes(pointer).value;
          expect(attributes, isNot(0xffffffff));
          originalAttributes[path] = attributes;
          expect(
            SetFileAttributes(
              pointer,
              FILE_FLAGS_AND_ATTRIBUTES(attributes | FILE_ATTRIBUTE_HIDDEN),
            ).value,
            isTrue,
          );
        }
      });
      final probed = <String>[];
      await repository.close();
      repository = store(
        FileSourceAdapter(
          hiddenPaths: (paths) async {
            probed.addAll(paths);
            return hiddenFilePaths(paths);
          },
        ),
      );
      final source = await add();
      await repository.scan(source.id);
      expect(
        (await repository.browse(source.id)).items
            .map((i) => i.identity.localId),
        ['visible.mp4'],
      );
      expect(probed, isNot(contains(hiddenChild.path)));
      probed.clear();
      await repository.updateSettings(source.id, ignoreHidden: false);
      await repository.scan(source.id);
      expect((await repository.browse(source.id)).total, 4);
      expect(probed, isEmpty);
      await repository.updateSettings(source.id, ignoreHidden: true);
      await repository.scan(source.id);
      expect((await repository.browse(source.id)).total, 1);
      expect(await hiddenFile.exists(), isTrue);
      expect(await hiddenChild.exists(), isTrue);
    } finally {
      using((arena) {
        for (final entry in originalAttributes.entries) {
          expect(
            SetFileAttributes(
              entry.key.toPcwstr(allocator: arena),
              FILE_FLAGS_AND_ATTRIBUTES(entry.value),
            ).value,
            isTrue,
          );
        }
      });
    }
  }, skip: !Platform.isWindows);

  test('native hidden lookup reports missing paths instead of treating them as visible', () async {
    await expectLater(
      hiddenFilePaths([p.join(root.path, 'missing.mp4')]),
      throwsA(isA<FileSystemException>()),
    );
  }, skip: !Platform.isWindows);

  test(
    'attribute failure preserves prior index and successful scan timestamp',
    () async {
      var fail = false;
      await repository.close();
      repository = store(
        FileSourceAdapter(
          hiddenPaths: (paths) async {
            if (fail) {
              throw FileSystemException(
                'injected attribute failure',
                paths.first,
              );
            }
            return {};
          },
        ),
      );
      final old = await media('old.mp4');
      final source = await add();
      await repository.scan(source.id);
      final timestamp = (await repository.source(source.id)).lastScan;
      await old.delete();
      await media('new.mp4');
      fail = true;
      await expectLater(
        repository.scan(source.id),
        throwsA(isA<SourceFailure>()),
      );
      expect(
        (await repository.browse(source.id)).items.single.identity.localId,
        'old.mp4',
      );
      expect((await repository.source(source.id)).lastScan, timestamp);
      fail = false;
      await repository.scan(source.id);
      expect(
        (await repository.browse(source.id)).items.single.identity.localId,
        'new.mp4',
      );
    },
  );

  test(
    'hidden lookup batches bound work and skip hidden descendants',
    () async {
      final child = await media('excluded/child.mp4');
      for (var i = 0; i < 130; i++) {
        await media('visible-$i.mp4');
      }
      final batches = <List<String>>[];
      await repository.close();
      repository = store(
        FileSourceAdapter(
          hiddenPaths: (paths) async {
            batches.add(paths);
            return {child.parent.path};
          },
        ),
      );
      final source = await add();
      await repository.scan(source.id);
      expect(batches, hasLength(2));
      expect(batches.every((batch) => batch.length <= 128), isTrue);
      expect(batches.expand((batch) => batch), isNot(contains(child.path)));
      expect((await repository.browse(source.id)).total, 130);
    },
  );
}
