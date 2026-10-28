import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/metadata/application/metadata_supplement_service.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/data/video_nfo_writer.dart';
import 'package:reelnest/features/metadata/domain/metadata_supplement_state.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/sources/filesystem/local_metadata_service.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/tmdb_fixture.dart';

class _Store implements CredentialStore {
  @override
  Future<String?> read() async => 'fixture';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  late Directory sandbox, media, art;
  late SourceRepository sources;
  late TmdbFixture fixture;
  late TmdbSettingsRepository settings;
  late TmdbVideoService movie, series;
  late MediaSource source;
  Future<void> file(String name) async {
    final f = File(p.join(media.path, name));
    await f.parent.create(recursive: true);
    await f.writeAsString('media fixture');
  }

  Future<void> rescan() async {
    await sources.scan(source.id);
  }

  Future<IndexedMedia> film() async =>
      (await sources.indexedSource(source.id))
          .firstWhere((i) => i.type == 'movie');
  Future<IndexedMedia> show() async =>
      (await sources.indexedSource(source.id)).firstWhere((i) => i.isSeries);
  Future<void> enable() async {
    await sources.updateSettings(
      source.id,
      options: SourceOptions(preferMetadataWriteToSource: true),
    );
  }

  TmdbVideoService service(bool tv, {VideoNfoWriter? writer}) =>
      TmdbVideoService(
        sources: sources,
        settings: settings,
        client: fixture.client(),
        artwork: TmdbArtworkStore(library: () async => art),
        kind: tv ? TmdbMediaKind.tv : TmdbMediaKind.movie,
        nfoWriter: writer,
      );
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-nfo-supplement-');
    media = await Directory(p.join(sandbox.path, 'media')).create();
    art = await Directory(p.join(sandbox.path, 'art')).create();
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'library',
      location: media.path,
      minimumFileSize: 0,
    );
    await file('Film.2015.mkv');
    await file('Show/Season 1/Show.S01E01.mkv');
    await rescan();
    fixture = await TmdbFixture.start();
    settings = TmdbSettingsRepository(sources.database, store: _Store());
    movie = service(false);
    series = service(true);
  });
  tearDown(() async {
    await movie.dispose();
    await series.dispose();
    await fixture.close();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    await sandbox.delete(recursive: true);
  });
  Future<TmdbCandidate> selected(TmdbVideoService service) async =>
      (await service.search('Film Show')).first;

  test(
    'ordinary TMDB matching does not write NFO even with source opt-in',
    () async {
      await enable();
      final item = await film();
      await movie.apply(item.identity, await selected(movie));
      expect(await File(p.join(media.path, 'Film.2015.nfo')).exists(), isFalse);
      expect(await movie.metadata(item.identity), isNotNull);
    },
  );
  test('supplement defaults to index only and preserves existing descriptive fields', () async {
    final item = await film();
    await sources.database.customStatement(
      'UPDATE media SET overview=? WHERE source_id=? AND local_id=?',
      ['Existing overview', source.id, item.identity.localId],
    );
    await movie.apply(
      item.identity,
      await selected(movie),
      supplementOnly: true,
    );
    final updated = await sources.media(item.identity);
    expect(updated.year, 2015);
    expect(updated.overview, 'Existing overview');
    expect(await File(p.join(media.path, 'Film.2015.nfo')).exists(), isFalse);
  });
  test(
    'localized matched identity keeps edited title and existing cover',
    () async {
      final item = await film();
      final candidate = await selected(movie);
      await movie.apply(item.identity, candidate);
      final poster = (await sources.media(item.identity)).posterPath;
      await sources.database.customStatement(
        'UPDATE media SET title=?,overview=? WHERE source_id=? AND local_id=?',
        ['Manual title', 'Keep overview', source.id, item.identity.localId],
      );
      fixture.requests.clear();
      await movie.apply(item.identity, candidate, supplementOnly: true);
      final updated = await sources.media(item.identity);
      expect(updated.title, 'Manual title');
      expect(updated.overview, 'Keep overview');
      expect(updated.posterPath, poster);
      expect(
        fixture.requests.where((u) => u.path.startsWith('/t/p/')),
        isEmpty,
      );
    },
  );
  test('opted-in supplementation writes a safe independent NFO without modifying media', () async {
    await enable();
    final item = await film();
    final original = await File(p.join(media.path, item.identity.localId))
        .readAsBytes();
    final sidecar = File(p.join(media.path, 'Film.2015.nfo'));
    await sidecar.writeAsString(
      '<movie custom="keep"><studio>Independent</studio><uniqueid type="imdb">tt1</uniqueid></movie>',
    );
    final result = await movie.apply(
      item.identity,
      await selected(movie),
      supplementOnly: true,
    );
    expect(result.warnings, isEmpty);
    final xml = XmlDocument.parse(await sidecar.readAsString());
    expect(xml.rootElement.getAttribute('custom'), 'keep');
    expect(
      xml.rootElement.findElements('studio').single.innerText,
      'Independent',
    );
    expect(xml.rootElement.findElements('uniqueid').first.innerText, 'tt1');
    expect(
      await File(p.join(media.path, item.identity.localId)).readAsBytes(),
      original,
    );
    expect(await File(p.join(media.path, 'movie.nfo')).exists(), isFalse);
    final readback = await LocalMetadataService().forFile(
      p.join(media.path, item.identity.localId),
      readNFO: true,
      preferLocalArtwork: false,
    );
    expect(
      readback.title,
      xml.rootElement.findElements('title').single.innerText,
    );
    expect(readback.overview, 'Detailed overview');
    await rescan();
    expect((await sources.media(item.identity)).title, readback.title);
  });
  test(
    'malformed NFO is retained while confirmed index metadata still commits',
    () async {
      await enable();
      final item = await film();
      final sidecar = File(p.join(media.path, 'Film.2015.nfo'));
      await sidecar.writeAsString('<movie><broken>');
      final result = await movie.apply(
        item.identity,
        await selected(movie),
        supplementOnly: true,
      );
      expect(result.warnings.any((w) => w.contains('NFO')), isTrue);
      expect(await sidecar.readAsString(), '<movie><broken>');
      expect(await movie.metadata(item.identity), isNotNull);
    },
  );
  test('series supplementation writes only common tvshow.nfo and leaves episode metadata alone', () async {
    await enable();
    final item = await show();
    final children = await sources.indexedChildren(item.identity);
    await series.apply(
      item.identity,
      await selected(series),
      supplementOnly: true,
    );
    expect(
      await File(p.join(media.path, 'Show', 'tvshow.nfo')).exists(),
      isTrue,
    );
    final after = await sources.indexedChildren(item.identity);
    expect(
      after.map((e) => (e.title, e.overview)),
      children.map((e) => (e.title, e.overview)),
    );
    expect(fixture.requests.where((u) => u.path.contains('/season/')), isEmpty);
    expect(await File(p.join(media.path, 'tvshow.nfo')).exists(), isFalse);
  });
  test('writeback observes late source opt-out without reverting committed index data', () async {
    await enable();
    final item = await film();
    final sidecar = File(p.join(media.path, 'Film.2015.nfo'));
    const original = '<movie><studio>Keep</studio></movie>';
    await sidecar.writeAsString(original);
    final guarded = service(
      false,
      writer: VideoNfoWriter(
        beforeCommit: () async {
          await sources.updateSettings(
            source.id,
            options: SourceOptions(preferMetadataWriteToSource: false),
          );
        },
      ),
    );
    try {
      final result = await guarded.apply(
        item.identity,
        await selected(guarded),
        supplementOnly: true,
      );
      expect(result.warnings, isNotEmpty);
      expect(await sidecar.readAsString(), original);
      expect(await guarded.metadata(item.identity), isNotNull);
    } finally {
      await guarded.dispose();
    }
  });
  test('health supplement workflow fills both movie and series via the shared matcher', () async {
    await enable();
    MetadataSupplementState state = const MetadataSupplementState();
    Future<void> respond(HttpRequest request) async {
      if (request.uri.path.startsWith('/3/search/')) {
        await fixture.json(request, {
          'results': [
            request.uri.path.endsWith('/tv')
                ? fixture.tvCandidate(1)
                : fixture.candidate(1),
          ],
        });
      } else {
        fixture.intercept = null;
        try {
          await fixture.handle(request);
        } finally {
          fixture.intercept = respond;
        }
      }
    }

    fixture.intercept = respond;
    final candidates = [await film(), await show()];
    final workflow = MetadataSupplementService(
      sources: sources,
      settings: settings,
      movie: movie,
      series: series,
      loadCandidates: () async => candidates,
      isScanning: () => false,
      onState: (s) => state = s,
    );
    try {
      await workflow.start();
      expect(state.updated, 2);
      expect(state.failed, 0);
      expect(state.warningCount, 0);
      expect(state.running, isFalse);
      expect(await File(p.join(media.path, 'Film.2015.nfo')).exists(), isTrue);
      expect(
        await File(p.join(media.path, 'Show', 'tvshow.nfo')).exists(),
        isTrue,
      );
    } finally {
      await workflow.dispose();
    }
  });
}
