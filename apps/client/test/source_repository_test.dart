import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_scan.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_options.dart';
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
    'parsed metadata survives SQLite reopen, rescan and root relocation',
    () async {
      await repository.close();
      final dbFile = File(p.join(sandbox.path, 'parsed.sqlite'));
      repository = makeRepository(
        LibraryDatabase(NativeDatabase.createInBackground(dbFile)),
      );
      final root = await folder('parsed');
      await media(root, 'Inception.2010.1080p.BluRay.x265.mkv');
      await media(root, 'Show (2020)/Season 2/Release.S02E07.mkv');
      await media(root, 'Loose.S01E02.mkv');
      await media(root, '01 - Song_Title.flac');
      final source = await add(root);
      final summary = await repository.scan(source.id);
      expect(summary.importedItems, 4);
      expect(summary.errors, isEmpty);
      await repository.close();
      repository = makeRepository(
        LibraryDatabase(NativeDatabase.createInBackground(dbFile)),
      );
      var items = (await repository.browse(source.id)).items;
      final movie = items.singleWhere((i) => i.type == 'movie');
      expect(movie.title, 'Inception');
      expect(movie.year, 2010);
      final show = items.singleWhere((i) => i.title == 'Show');
      expect(show.type, 'episode');
      expect(show.seasonNumber, 2);
      expect(show.episodeNumber, 7);
      expect(show.seriesDirectory, 'Show (2020)');
      expect(
        items.singleWhere((i) => i.title == 'Loose').seriesDirectory,
        isNull,
      );
      final song = items.singleWhere((i) => i.type == 'music');
      expect(song.title, 'Song Title');
      expect(song.year, isNull);
      expect(song.seasonNumber, isNull);

      final moved = await root.rename(p.join(sandbox.path, 'moved-parsed'));
      await repository.relocate(source.id, moved.path);
      await repository.scan(source.id);
      items = (await repository.browse(source.id)).items;
      final relocated = items.singleWhere((i) => i.title == 'Show');
      expect(relocated.identity, show.identity);
      expect(relocated.seriesDirectory, show.seriesDirectory);
      expect(relocated.episodeNumber, 7);

      // Changing source classification must clear old parsed fields on upsert.
      await repository.updateSettings(
        source.id,
        mediaType: SourceMediaType.movie,
      );
      await repository.scan(source.id);
      items = (await repository.browse(source.id)).items;
      expect(
        items,
        hasLength(3),
      ); // Music is no longer accepted by a movie source.
      final forced = items.singleWhere((i) => i.identity == show.identity);
      expect(forced.title, 'Release S02E07');
      expect(forced.type, 'movie');
      expect(forced.seasonNumber, isNull);
      expect(forced.episodeNumber, isNull);
      expect(forced.seriesDirectory, isNull);

      await repository.updateSettings(
        source.id,
        mediaType: SourceMediaType.photo,
      );
      await repository.scan(source.id);
      items = (await repository.browse(source.id)).items;
      final albumMovie = items.singleWhere((i) => i.identity == movie.identity);
      expect(albumMovie.title, 'Inception.2010.1080p.BluRay.x265');
      expect(albumMovie.type, 'homeVideo');
      expect(albumMovie.year, isNull);
      expect(
        items.every((i) => i.seasonNumber == null && i.seriesDirectory == null),
        isTrue,
      );
    },
  );

  test(
    'scanner preserves original source categories and album title bypass',
    () async {
      final root = await folder('categories');
      await media(root, 'Some Film.2024.mkv');
      await media(root, 'Show.S01E02.mkv');
      await media(root, 'Trip.2024.jpg');
      final source = await add(root);
      for (final type in [
        SourceMediaType.auto,
        SourceMediaType.tvShow,
        SourceMediaType.anime,
        SourceMediaType.documentary,
        SourceMediaType.variety,
        SourceMediaType.homeVideo,
        SourceMediaType.other,
        SourceMediaType.privateCollection,
        SourceMediaType.episode,
      ]) {
        await repository.updateSettings(source.id, mediaType: type);
        await repository.scan(source.id);
        final items = (await repository.browse(source.id)).items;
        expect(items, hasLength(2));
        final movie = items.singleWhere((i) => i.title == 'Some Film');
        expect(
          movie.type,
          [
                SourceMediaType.auto,
                SourceMediaType.tvShow,
                SourceMediaType.episode,
              ].contains(type)
              ? 'movie'
              : type.storageValue,
          reason: type.name,
        );
        expect(movie.year, 2024);
        expect(items.singleWhere((i) => i.title == 'Show').type, 'episode');
      }
      await repository.updateSettings(
        source.id,
        mediaType: SourceMediaType.photo,
      );
      await repository.scan(source.id);
      final album = (await repository.browse(source.id)).items;
      expect(album, hasLength(3));
      expect(album.singleWhere((i) => i.type == 'photo').title, 'Trip.2024');
      expect(
        album.singleWhere((i) => i.title == 'Show.S01E02').type,
        'homeVideo',
      );
      expect(
        album.every((i) => i.year == null && i.episodeNumber == null),
        isTrue,
      );
    },
  );

  test(
    'music fallback title strips only original track prefix, not movie noise',
    () async {
      final root = await folder('music-titles');
      await media(root, '001- Song_Name.2024.flac');
      await media(root, '01 Plain_Title.mp3');
      await media(root, '002_.mp3');
      final source = await add(root);
      for (final type in [SourceMediaType.auto, SourceMediaType.music]) {
        await repository.updateSettings(source.id, mediaType: type);
        await repository.scan(source.id);
        final items = (await repository.browse(source.id)).items;
        expect(items.map((i) => i.title).toSet(), {
          'Song Name.2024',
          '01 Plain Title',
          '002_',
        });
        expect(
          items.every(
            (i) =>
                i.type == 'music' && i.year == null && i.episodeNumber == null,
          ),
          isTrue,
        );
      }
    },
  );

  test('batch adds only new directories in selection order with original music defaults', () async {
    final old = await folder('existing');
    final a = await folder('music-a');
    final b = await folder('music-b');
    final original = await add(old);
    final created = await repository.addFolders(
      locations: [old.path, b.path, a.path, b.path],
      mediaType: SourceMediaType.music,
    );
    expect(created.map((s) => s.name), ['music-b', 'music-a']);
    expect(
      created.every(
        (s) =>
            s.mediaType == SourceMediaType.music &&
            s.minimumFileSize == 512 * 1024 &&
            s.recursive &&
            s.ignoreHidden,
      ),
      isTrue,
    );
    expect(
      (await repository.source(original.id)).mediaType,
      SourceMediaType.auto,
    );
    expect(await repository.sources(), hasLength(3));
    await expectLater(
      repository.addFolders(locations: [a.path, b.path]),
      throwsA(
        isA<SourceFailure>().having(
          (e) => e.message,
          'message',
          '所选目录均已添加为媒体源。',
        ),
      ),
    );
    expect(await repository.addFolders(locations: []), isEmpty);
  });

  test(
    'batch skips offline existing roots and album sources exclude metadata',
    () async {
      final old = await folder('offline-existing');
      final original = await add(old);
      await old.rename(p.join(sandbox.path, 'unmounted'));
      final album = await folder('相册');
      final created = await repository.addFolders(
        locations: [old.path, album.path],
        mediaType: SourceMediaType.photo,
      );
      expect(created.single.name, '相册');
      expect(created.single.options.includeInMetadataFetch, isFalse);
      expect(created.single.options.preferMetadataWriteToSource, isFalse);
      expect(created.single.options.includeInHealthCheck, isTrue);
      expect((await repository.source(original.id)).lastScan, isNull);
      await expectLater(
        repository.addFolders(
          locations: [album.path],
          mediaType: SourceMediaType.privateCollection,
        ),
        throwsA(
          isA<SourceFailure>().having(
            (e) => e.message,
            'private message',
            '该保险库媒体源已添加。',
          ),
        ),
      );
    },
  );

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
    'cancelling retains committed new files and never prunes old entries',
    () async {
      final root = await folder('cancel');
      await media(root, 'original.mp4');
      final source = await add(root);
      await repository.scan(source.id);
      final timestamp = (await repository.source(source.id)).lastScan;
      await File(p.join(root.path, 'original.mp4')).delete();
      for (var i = 0; i < 105; i++) {
        await media(root, '$i.mp3');
      }
      await expectLater(
        repository.scan(
          source.id,
          onProgress: (value) {
            if (value.importedItems == 1) repository.cancel(source.id);
          },
        ),
        throwsA(isA<ScanCancelled>()),
      );
      final partial = await repository.browse(source.id);
      expect(partial.total, 2);
      expect(partial.items.map((item) => item.title), contains('original'));
      expect((await repository.source(source.id)).lastScan, timestamp);
      final staged = await repository.database
          .customSelect('SELECT COUNT(*) AS n FROM scan_stage')
          .getSingle();
      expect(staged.read<int>('n'), 0);
      await repository.scan(source.id);
      expect((await repository.browse(source.id)).total, 105);
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
      expect(
        (await repository.browse(source.id)).items
            .map((i) => i.identity.localId),
        unorderedEquals(['.hidden.mp4', 'a.mp4']),
      );
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
        createdAt: source.createdAt,
        updatedAt: source.updatedAt,
        mediaType: SourceMediaType.movie,
        minimumFileSize: threshold,
      );
      expect(
        await files
            .scan(videoSource, ScanCancellation())
            .where((e) => e is ScanFileProcessed && e.item != null)
            .length,
        1,
      );
      await clip.writeAsBytes(List.filled(threshold - 1, 0));
      expect(
        await files
            .scan(videoSource, ScanCancellation())
            .where((e) => e is ScanFileProcessed && e.item != null)
            .length,
        0,
      );
      expect(await photo.exists(), isTrue);
    },
  );

  test('file disappearing after catalog continues, counts skips, protects old index', () async {
    final root = await folder('partial');
    final old = await media(root, 'old.mp4');
    final source = await add(root);
    await repository.scan(source.id);
    final lastScan = (await repository.source(source.id)).lastScan;
    await old.delete();
    final vanished = await media(root, 'vanished.mp4');
    await media(root, 'survivor.mp4');
    await File(p.join(root.path, 'small.mp4')).writeAsBytes([]);
    await repository.updateSettings(source.id, minimumFileSize: 1);
    final progress = <SourceScanProgress>[];
    final result = await repository.scan(
      source.id,
      onProgress: (value) {
        progress.add(value);
        if (value.processedFiles == 0) vanished.deleteSync();
      },
    );
    expect(result.scannedFiles, 3);
    expect(result.importedItems, 1);
    expect(result.skippedFiles, 1);
    expect(result.errors, hasLength(1));
    expect(result.errors.single, contains('vanished.mp4'));
    expect(progress.last.processedFiles, 3);
    expect(progress.last.fraction, 1);
    expect(
      (await repository.browse(source.id)).items.map((item) => item.title),
      ['old', 'survivor'],
    );
    expect((await repository.source(source.id)).lastScan, lastScan);
    await repository.scan(source.id);
    expect((await repository.browse(source.id)).items.single.title, 'survivor');
  });

  test(
    'database failure is isolated per file and private progress redacts paths',
    () async {
      final root = await folder('private');
      await media(root, 'old.mp4');
      final source = await add(root);
      await repository.scan(source.id);
      await File(p.join(root.path, 'old.mp4')).delete();
      await media(root, 'bad.mp4');
      await media(root, 'good.mp4');
      await repository.updateSettings(
        source.id,
        mediaType: SourceMediaType.privateCollection,
      );
      await repository.database.customStatement(
        "CREATE TRIGGER reject_bad BEFORE INSERT ON media WHEN NEW.title = 'bad' BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      final progress = <SourceScanProgress>[];
      final result = await repository.scan(source.id, onProgress: progress.add);
      expect(result.importedItems, 1);
      expect(result.errors, ['隐私媒体源中有文件扫描失败。']);
      expect(progress.every((value) => value.currentPath == null), isTrue);
      expect(
        (await repository.browse(source.id)).items.map((item) => item.title),
        ['good', 'old'],
      );
    },
  );

  test('all source policies persist across reopen and music update matches original threshold', () async {
    await repository.close();
    final file = File(p.join(sandbox.path, 'options.sqlite'));
    repository = makeRepository(LibraryDatabase(NativeDatabase(file)));
    final options = SourceOptions(
      autoScan: false,
      readNFO: false,
      preferLocalArtwork: false,
      networkScrapingEnabled: false,
      screenshotFallbackEnabled: false,
      includeInMetadataFetch: false,
      preferMetadataWriteToSource: true,
      includeInHealthCheck: false,
      remoteTraceSyncMode: RemoteTraceSyncMode.importOnly,
      selectedEmbyLibraryIDs: [' lib2 ', '', 'lib1', 'lib2'],
    );
    final source = await repository.add(
      kind: MediaSourceKind.localFolder,
      name: 'Settings',
      location: (await folder('options')).path,
      options: options,
    );
    final created = source.createdAt;
    expect(created, isNotNull);
    await repository.updateSettings(
      source.id,
      mediaType: SourceMediaType.music,
    );
    expect((await repository.source(source.id)).minimumFileSize, 512 * 1024);
    await repository.updateSettings(
      source.id,
      minimumFileSize: 5 * 1024 * 1024,
    );
    await repository.close();
    repository = makeRepository(LibraryDatabase(NativeDatabase(file)));
    final restored = await repository.source(source.id);
    expect(restored.options.toJson(), options.toJson());
    expect(restored.options.selectedEmbyLibraryIDs, ['lib2', 'lib1']);
    expect(restored.minimumFileSize, 5 * 1024 * 1024);
    expect(restored.createdAt, created);
    expect(restored.updatedAt.isBefore(created), isFalse);
    final fallback = SourceOptions.fromJson({'remoteTraceSyncMode': 'future'});
    expect(fallback.toJson(), const SourceOptions.defaults().toJson());
  });
}

class _InterruptibleFiles extends FileSourceAdapter {
  bool failAfterFirst = false;
  @override
  Stream<SourceScanEvent> scan(
    MediaSource source,
    ScanCancellation cancellation,
  ) async* {
    await for (final item in super.scan(source, cancellation)) {
      yield item;
      if (failAfterFirst && item is ScanFileProcessed) {
        throw const SourceFailure('模拟子目录读取失败');
      }
    }
  }
}
