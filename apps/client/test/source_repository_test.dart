import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

void main() {
  late Directory sandbox;
  late SourceRepository repository;
  late _InterruptibleFiles files;

  SourceRepository makeRepository(LibraryDatabase database) => SourceRepository(
    database: database,
    adapters: {
      for (final kind in MediaSourceKind.values.where((k) => k.isFileSource))
        kind: files,
    },
  );

  Future<Directory> folder(String name) =>
      Directory(p.join(sandbox.path, name)).create(recursive: true);
  Future<File> media(Directory root, String name) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsString('synthetic media index fixture; not playable');
  }

  Future<MediaSource> add(
    Directory root, {
    MediaSourceKind kind = MediaSourceKind.localFolder,
  }) => repository.add(
    kind: kind,
    name: p.basename(root.path),
    location: root.path,
    // Small synthetic fixtures exercise index mechanics, not default sizing.
    minimumFileSize: 0,
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-source-test-');
    files = _InterruptibleFiles();
    repository = makeRepository(LibraryDatabase(NativeDatabase.memory()));
  });
  tearDown(() async {
    await repository.close();
    // Only the uniquely created test sandbox, never user-selected media.
    await sandbox.delete(recursive: true);
  });

  test(
    'sources isolate same paths, filter files and page a deterministic index',
    () async {
      final a = await folder('a');
      final b = await folder('b');
      await media(a, 'shared.MP4');
      await media(b, 'shared.MP4');
      await media(a, 'album/track.flac');
      await media(a, 'album/second.mka');
      await media(a, 'photo.jpg');
      await media(a, '.hidden/skip.mp4');
      await media(a, 'notes.txt');
      final sa = await add(a);
      final sb = await add(b, kind: MediaSourceKind.mountedNas);
      await repository.scan(sa.id);
      await repository.scan(sb.id);
      final first = await repository.browse(sa.id, limit: 2);
      final second = await repository.browse(sa.id, offset: 2, limit: 2);
      expect(first.total, 3);
      expect(second.items, hasLength(1));
      final ids = [
        ...first.items,
        ...second.items,
      ].map((i) => i.identity).toSet();
      expect(ids, hasLength(3));
      expect(
        ids.intersection(
          (await repository.browse(sb.id)).items.map((i) => i.identity).toSet(),
        ),
        isEmpty,
      );
      await expectLater(add(a), throwsA(isA<SourceFailure>()));
    },
  );

  test(
    'SQLite survives reopen; relocating root retains source and media identity',
    () async {
      await repository.close();
      final dbFile = File(p.join(sandbox.path, 'library.sqlite'));
      repository = makeRepository(
        LibraryDatabase(NativeDatabase.createInBackground(dbFile)),
      );
      final a = await folder('drive');
      await media(a, 'movie.mkv');
      final source = await add(a, kind: MediaSourceKind.removableDrive);
      await repository.scan(source.id);
      final identity = (await repository.browse(source.id))
          .items
          .single
          .identity;
      await repository.close();
      repository = makeRepository(
        LibraryDatabase(NativeDatabase.createInBackground(dbFile)),
      );
      expect((await repository.sources()).single.id, source.id);
      expect(
        (await repository.browse(source.id)).items.single.identity,
        identity,
      );
      final moved = await a.rename(p.join(sandbox.path, 'remounted'));
      await repository.relocate(source.id, moved.path);
      await repository.scan(source.id);
      expect(
        (await repository.browse(source.id)).items.single.identity,
        identity,
      );
      expect((await repository.source(source.id)).location, moved.path);
    },
  );

  test(
    'cancelling a scan after a staged batch preserves the published snapshot',
    () async {
      final root = await folder('cancel');
      await media(root, 'original.mp4');
      final source = await add(root);
      await repository.scan(source.id);
      final timestamp = (await repository.source(source.id)).lastScan;
      for (var i = 0; i < 105; i++) {
        await media(root, '$i.mp3');
      }
      await expectLater(
        repository.scan(
          source.id,
          onProgress: (_) => repository.cancel(source.id),
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(
        (await repository.browse(source.id)).items.single.title,
        'original',
      );
      expect((await repository.source(source.id)).lastScan, timestamp);
      final staged = await repository.database
          .customSelect('SELECT COUNT(*) AS n FROM scan_stage')
          .getSingle();
      expect(staged.read<int>('n'), 0);
      await repository.scan(source.id);
      expect((await repository.browse(source.id)).total, 106);
    },
  );

  test(
    'failed/offline scans retain index; successful scans prune absent files',
    () async {
      final root = await folder('offline');
      await media(root, 'a.mp4');
      await media(root, 'b.mp4');
      final source = await add(root);
      await repository.scan(source.id);
      files.failAfterFirst = true;
      await expectLater(
        repository.scan(source.id),
        throwsA(isA<SourceFailure>()),
      );
      expect((await repository.source(source.id)).missingCount, 0);
      expect((await repository.browse(source.id)).total, 2);
      files.failAfterFirst = false;
      final moved = await root.rename(p.join(sandbox.path, 'unmounted'));
      await expectLater(
        repository.scan(source.id),
        throwsA(isA<SourceFailure>()),
      );
      expect((await repository.source(source.id)).missingCount, 0);
      await moved.rename(root.path);
      await File(p.join(root.path, 'b.mp4')).delete();
      await repository.scan(source.id);
      expect((await repository.source(source.id)).missingCount, 0);
      expect((await repository.browse(source.id)).total, 1);
      await media(root, 'b.mp4');
      await repository.scan(source.id);
      expect((await repository.source(source.id)).missingCount, 0);
    },
  );

  test(
    'removing one source clears only its index and never original files',
    () async {
      final a = await folder('a');
      final b = await folder('b');
      final original = await media(a, 'a.mp4');
      await media(b, 'b.mp4');
      final sa = await add(a);
      final sb = await add(b);
      await repository.scan(sa.id);
      await repository.scan(sb.id);
      await repository.remove(sa.id);
      expect(await original.exists(), isTrue);
      expect((await repository.browse(sa.id)).total, 0);
      expect((await repository.browse(sb.id)).total, 1);
      expect((await repository.sources()).single.id, sb.id);
    },
  );

  test(
    'recursive and dotfile settings are applied before traversing folders',
    () async {
      final root = await folder('filters');
      await media(root, 'a.mp4');
      await media(root, '.hidden.mp4');
      await media(root, 'nested/b.mp4');
      final source = await repository.add(
        kind: MediaSourceKind.localFolder,
        name: 'Filters',
        location: root.path,
        recursive: false,
        ignoreHidden: false,
        minimumFileSize: 0,
      );
      await repository.scan(source.id);
      expect((await repository.browse(source.id)).items.map((i) => i.title), [
        '.hidden',
        'a',
      ]);
    },
  );

  test(
    'source classification and original size defaults survive storage',
    () async {
      final video = await repository.add(
        kind: MediaSourceKind.localFolder,
        name: 'Video',
        location: (await folder('video')).path,
      );
      final music = await repository.add(
        kind: MediaSourceKind.localFolder,
        name: 'Music',
        location: (await folder('music')).path,
        mediaType: SourceMediaType.music,
      );
      expect(video.mediaType, SourceMediaType.auto);
      expect(video.minimumFileSize, 50 * 1024 * 1024);
      expect(music.mediaType, SourceMediaType.music);
      expect(music.minimumFileSize, 512 * 1024);
      await expectLater(
        repository.add(
          kind: MediaSourceKind.localFolder,
          name: 'Invalid',
          location: (await folder('invalid')).path,
          minimumFileSize: -1,
        ),
        throwsA(isA<SourceFailure>()),
      );
    },
  );

  test(
    'real directory applies source filters and inclusive byte threshold',
    () async {
      final root = await folder('album');
      final photo = await media(root, 'small.dng');
      final clip = await media(root, 'clip.M2TS');
      await media(root, 'song.caf');
      await media(root, 'movie.nfo');
      final source = await repository.add(
        kind: MediaSourceKind.localFolder,
        name: 'Album',
        location: root.path,
        mediaType: SourceMediaType.photo,
      );
      await repository.scan(source.id);
      expect((await repository.browse(source.id)).items.map((i) => i.title), [
        'clip',
        'small',
      ]);
      // Change only the policy in a second adapter run to exercise the boundary
      // against the real FileStat size, without creating large test files.
      final threshold = await clip.length();
      final videoSource = MediaSource(
        id: source.id,
        kind: source.kind,
        name: source.name,
        location: source.location,
        mediaType: SourceMediaType.movie,
        minimumFileSize: threshold,
      );
      expect(await files.scan(videoSource, ScanCancellation()).length, 1);
      await clip.writeAsBytes(List.filled(threshold - 1, 0));
      expect(await files.scan(videoSource, ScanCancellation()).length, 0);
      expect(await photo.exists(), isTrue);
    },
  );
}

class _InterruptibleFiles extends FileSourceAdapter {
  bool failAfterFirst = false;
  @override
  Stream<IndexedMedia> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    await for (final item in super.scan(source, cancellation)) {
      yield item;
      if (failAfterFirst) throw const SourceFailure('模拟子目录读取失败');
    }
  }
}
