import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/automatic_scan_interval.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/domain/source_media_type.dart';
import 'package:reelnest/domain/source_options.dart';
import 'package:reelnest/features/metadata/application/tmdb_batch_service.dart';
import 'package:reelnest/features/metadata/application/tmdb_video_service.dart';
import 'package:reelnest/features/metadata/data/tmdb_artwork_store.dart';
import 'package:reelnest/features/metadata/data/tmdb_settings_repository.dart';
import 'package:reelnest/features/metadata/domain/tmdb_match_tolerance.dart';
import 'package:reelnest/features/metadata/domain/tmdb_models.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/credential_store.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/storage/preference_store.dart';

import 'support/tmdb_fixture.dart';

class _Store implements CredentialStore {
  String? value = 'fixture-key';
  @override
  Future<String?> read() async => value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<void> write(String next) async {
    value = next;
  }
}

void main() {
  late Directory sandbox, media, art;
  late SourceRepository sources;
  late TmdbSettingsRepository settings;
  late TmdbFixture fixture;
  late TmdbVideoService series;
  late TmdbBatchService batch;
  late MediaSource source;
  late _Store credentials;
  var scanning = false;
  Future<void> file(String relative) async {
    final f = File(p.join(media.path, relative));
    await f.parent.create(recursive: true);
    await f.writeAsString('not a playable video');
  }

  Future<IndexedMedia> show() async =>
      (await sources.indexedSource(source.id)).firstWhere((e) => e.isSeries);
  Future<void> defaults(HttpRequest request) async {
    fixture.intercept = null;
    try {
      await fixture.handle(request);
    } finally {
      fixture.intercept = defaults;
    }
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-tmdb-batch-');
    media = await Directory(p.join(sandbox.path, 'media')).create();
    art = await Directory(p.join(sandbox.path, 'art')).create();
    credentials = _Store();
    scanning = false;
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'TV',
      location: media.path,
      minimumFileSize: 0,
    );
    await file('Show/Show.S01E01.mkv');
    await sources.scan(source.id);
    fixture = await TmdbFixture.start();
    settings = TmdbSettingsRepository(sources.database, store: credentials);
    series = TmdbVideoService(
      sources: sources,
      settings: settings,
      client: fixture.client(),
      artwork: TmdbArtworkStore(library: () async => art),
      kind: TmdbMediaKind.tv,
    );
    batch = TmdbBatchService(
      sources: sources,
      settings: settings,
      series: series,
      isScanning: () => scanning,
    );
  });
  tearDown(() async {
    await batch.dispose();
    await series.dispose();
    await fixture.close();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    await sandbox.delete(recursive: true);
  });
  Future<void> uniqueSearch(HttpRequest request) async {
    if (request.uri.path == '/3/search/tv') {
      await fixture.json(request, {
        'results': [fixture.tvCandidate(1)],
      });
    } else {
      fixture.intercept = null;
      try {
        await fixture.handle(request);
      } finally {
        fixture.intercept = uniqueSearch;
      }
    }
  }

  test(
    'automatic preflight without credentials or candidates stays quiet',
    () async {
      final initial = batch.state.value;
      credentials.value = '';
      await batch.startAutomatic(ScanCancellation());
      expect(identical(batch.state.value, initial), isTrue);
      expect(fixture.requests, isEmpty);
      credentials.value = 'fixture-key';
      fixture.intercept = uniqueSearch;
      await batch.start();
      final completed = batch.state.value;
      fixture.requests.clear();
      await batch.startAutomatic(ScanCancellation());
      expect(identical(batch.state.value, completed), isTrue);
      expect(fixture.requests, isEmpty);
      scanning = true;
      await batch.startAutomatic(ScanCancellation());
      expect(identical(batch.state.value, completed), isTrue);
    },
  );

  test(
    'automatic entry cannot join or cancel a running manual batch',
    () async {
      final entered = Completer<void>(), gate = Completer<void>();
      fixture.intercept = (request) async {
        if (request.uri.path == '/3/search/tv') {
          if (!entered.isCompleted) entered.complete();
          await gate.future;
          await fixture.json(request, {
            'results': [fixture.tvCandidate(1)],
          });
        } else {
          fixture.intercept = null;
          try {
            await fixture.handle(request);
          } finally {
            fixture.intercept = uniqueSearch;
          }
        }
      };
      final manual = batch.start();
      await entered.future;
      final automaticToken = ScanCancellation();
      await batch.startAutomatic(automaticToken);
      automaticToken.cancel();
      gate.complete();
      await manual;
      expect(batch.state.value.matched, 1);
      expect(batch.state.value.cancelled, isFalse);
    },
  );

  test('automatic task cancellation preserves the first item and aborts the second', () async {
    await file('Second/Second.S01E01.mkv');
    await sources.scan(source.id);
    final entered = Completer<void>(), gate = Completer<void>();
    var block = false;
    void progressed() {
      if (batch.state.value.matched == 1) block = true;
    }

    batch.state.addListener(progressed);
    Future<void> respond(HttpRequest request) async {
      if (request.uri.path == '/3/search/tv') {
        if (block) {
          if (!entered.isCompleted) entered.complete();
          await gate.future;
        }
        await fixture.json(request, {
          'results': [fixture.tvCandidate(1)],
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
    final token = ScanCancellation(), automatic = batch.startAutomatic(token);
    try {
      await entered.future;
      token.cancel();
      await automatic.timeout(const Duration(seconds: 2));
      expect(batch.state.value.cancelled, isTrue);
      expect(batch.state.value.matched, 1);
      final rows = await sources.database
          .customSelect('SELECT * FROM local_series_metadata')
          .get();
      expect(rows, hasLength(1));
    } finally {
      if (!gate.isCompleted) gate.complete();
      batch.state.removeListener(progressed);
    }
  });

  test('automatic interval persists independently of file scanning and other TMDB settings', () async {
    expect(
      (await settings.read()).automaticMatchInterval,
      AutomaticScanInterval.disabled,
    );
    await sources.database.writePreference(
      'automaticScanInterval',
      AutomaticScanInterval.daily.name,
    );
    for (final value in AutomaticScanInterval.values) {
      await settings.setAutomaticMatchInterval(value);
      final reopened = TmdbSettingsRepository(
        sources.database,
        store: credentials,
      );
      expect((await reopened.read()).automaticMatchInterval, value);
    }
    await settings.setAutomaticMatchInterval(AutomaticScanInterval.hourly);
    await settings.setLanguage('en-US');
    await settings.setMatchTolerance(TmdbMatchTolerance.strict);
    final config = await settings.read();
    expect(config.automaticMatchInterval, AutomaticScanInterval.hourly);
    expect(config.language, 'en-US');
    expect(config.matchTolerance, TmdbMatchTolerance.strict);
    expect(
      await sources.database.preferenceValue('automaticScanInterval'),
      AutomaticScanInterval.daily.name,
    );
    await sources.database.writePreference(
      TmdbSettingsRepository.automaticIntervalKey,
      'unknown',
    );
    expect(
      (await settings.read()).automaticMatchInterval,
      AutomaticScanInterval.disabled,
    );
  });

  test(
    'failed automatic interval save retains the prior stored setting',
    () async {
      await settings.setAutomaticMatchInterval(AutomaticScanInterval.hourly);
      await sources.database.customStatement(
        "CREATE TRIGGER reject_automatic_interval BEFORE INSERT ON player_preferences WHEN NEW.key='global.automaticTMDBMatchInterval' BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      await expectLater(
        settings.setAutomaticMatchInterval(AutomaticScanInterval.daily),
        throwsA(isA<SourceFailure>()),
      );
      expect(
        (await settings.read()).automaticMatchInterval,
        AutomaticScanInterval.hourly,
      );
    },
  );

  test(
    'anime series uses TV matching while preserving source classification',
    () async {
      await sources.updateSettings(source.id, mediaType: SourceMediaType.anime);
      await sources.scan(source.id);
      fixture.intercept = uniqueSearch;
      final before = await show();
      expect(before.type, 'anime');
      await batch.start();
      expect(batch.state.value.matched, 1);
      expect((await sources.media(before.identity)).type, 'anime');
    },
  );

  test('batch uses the existing series apply path and excludes movies/remote/opt-out sources', () async {
    await file('Film.mkv');
    await sources.scan(source.id);
    final other = await Directory(p.join(sandbox.path, 'excluded')).create();
    await File(p.join(other.path, 'Other.S01E01.mkv')).writeAsString('fixture');
    final excluded = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'excluded',
      location: other.path,
      minimumFileSize: 0,
      options: SourceOptions(includeInMetadataFetch: false),
    );
    await sources.scan(excluded.id);
    final remote = await sources.add(
      kind: MediaSourceKind.emby,
      name: 'remote',
      location: 'emby://fixture/account',
    );
    await sources.syncRemote(
      remote.id,
      (_, _) async => [
        IndexedMedia(
          identity: (sourceId: remote.id, localId: 'remote-series'),
          title: 'Remote show',
          type: 'tvShow',
          isSeries: true,
          bytes: 0,
          modified: DateTime.utc(2026),
          remote: const RemoteMediaMetadata(externalId: 'remote-series'),
        ),
      ],
    );
    fixture.intercept = uniqueSearch;
    final before = await show();
    await batch.start();
    expect(batch.state.value.total, 1);
    expect(batch.state.value.matched, 1);
    expect(batch.state.value.failed, 0);
    expect(
      (await sources.indexedSource(remote.id)).single.title,
      'Remote show',
    );
    expect(batch.state.value.running, isFalse);
    expect(await series.metadata(before.identity), isNotNull);
    expect(
      (await sources.indexedSource(excluded.id))
          .firstWhere((e) => e.isSeries)
          .title,
      'Other',
    );
    expect((await sources.media(before.identity)).identity, before.identity);
    expect(fixture.requests.any((r) => r.path == '/3/search/movie'), isFalse);
    await expectLater(
      batch.start(),
      throwsA(
        isA<SourceFailure>().having(
          (e) => e.message,
          'message',
          contains('无需匹配'),
        ),
      ),
    );
  });

  test('same-language metadata is skipped while language changes allow one refresh', () async {
    fixture.intercept = uniqueSearch;
    await batch.start();
    await settings.setLanguage('en-US');
    await batch.start();
    final metadata = await series.metadata((await show()).identity);
    expect(metadata!.candidate.provider, 'TMDB[en-US]');
    expect(batch.state.value.matched, 1);
  });

  test(
    'missing credential and active scan fail before any HTTP requests',
    () async {
      credentials.value = '';
      await expectLater(batch.start(), throwsA(isA<SourceFailure>()));
      credentials.value = 'fixture-key';
      scanning = true;
      await expectLater(batch.start(), throwsA(isA<SourceFailure>()));
      expect(fixture.requests, isEmpty);
      expect(batch.state.value.running, isFalse);
    },
  );

  test(
    'strict mode leaves ambiguous low-confidence matches untouched',
    () async {
      await settings.setMatchTolerance(TmdbMatchTolerance.strict);
      fixture.intercept = (request) async {
        if (request.uri.path == '/3/search/tv') {
          await fixture.json(request, {
            'results': [
              {
                ...fixture.tvCandidate(1),
                'name': 'zzzz',
                'original_name': 'zzzz',
              },
              {
                ...fixture.tvCandidate(2),
                'name': 'yyyy',
                'original_name': 'yyyy',
              },
            ],
          });
        } else {
          await defaults(request);
        }
      };
      final before = await show();
      await batch.start();
      expect(batch.state.value.lowConfidence, 1);
      expect(batch.state.value.matched, 0);
      expect(await series.metadata(before.identity), isNull);
      expect((await sources.media(before.identity)).title, before.title);
    },
  );

  test('duplicate starts share the task and cancel aborts blocked HTTP without publishing metadata', () async {
    final entered = Completer<void>(), gate = Completer<void>();
    fixture.intercept = (request) async {
      if (request.uri.path == '/3/search/tv') {
        if (!entered.isCompleted) entered.complete();
        await gate.future;
        await fixture.json(request, {
          'results': [fixture.tvCandidate(1)],
        });
      } else {
        await defaults(request);
      }
    };
    final first = batch.start();
    await entered.future;
    final second = batch.start();
    expect(identical(first, second), isTrue);
    batch.cancel();
    await first.timeout(const Duration(seconds: 2));
    expect(batch.state.value.cancelled, isTrue);
    expect(batch.state.value.matched, 0);
    gate.complete();
    expect(await series.metadata((await show()).identity), isNull);
  });

  for (final change in [
    'opt-out',
    'manual-edit',
    'scan',
    'language',
    'remove',
  ]) {
    test('late search results cannot overwrite after $change', () async {
      final entered = Completer<void>(), gate = Completer<void>();
      fixture.intercept = (request) async {
        if (request.uri.path == '/3/search/tv') {
          if (!entered.isCompleted) entered.complete();
          await gate.future;
          await fixture.json(request, {
            'results': [fixture.tvCandidate(1)],
          });
        } else {
          fixture.intercept = null;
          try {
            await fixture.handle(request);
          } finally {
            fixture.intercept = uniqueSearch;
          }
        }
      };
      final before = await show(), work = batch.start();
      await entered.future;
      switch (change) {
        case 'opt-out':
          await sources.updateSettings(
            source.id,
            options: SourceOptions(includeInMetadataFetch: false),
          );
        case 'manual-edit':
          await sources.database.customStatement(
            'UPDATE media SET title=? WHERE source_id=? AND local_id=?',
            ['Manual title', source.id, before.identity.localId],
          );
        case 'scan':
          await sources.scan(source.id);
        case 'language':
          await settings.setLanguage('en-US');
        case 'remove':
          await sources.remove(source.id);
      }
      gate.complete();
      await work;
      expect(batch.state.value.matched, 0);
      expect(batch.state.value.failed, 1);
      if (change != 'remove') {
        expect(await series.metadata(before.identity), isNull);
      }
      if (change == 'manual-edit') {
        expect((await sources.media(before.identity)).title, 'Manual title');
      }
    });
  }

  test(
    'scan starting during detail preparation blocks the transaction',
    () async {
      fixture.intercept = uniqueSearch;
      final gate = Completer<void>();
      fixture.detailGate = gate.future;
      final work = batch.start();
      await fixture.detailStarted.future;
      scanning = true;
      gate.complete();
      await work;
      expect(batch.state.value.matched, 0);
      expect(batch.state.value.failed, 1);
      expect(await series.metadata((await show()).identity), isNull);
    },
  );

  test(
    'one failed item does not prevent the next item from matching',
    () async {
      await file('Second/Second.S01E01.mkv');
      await sources.scan(source.id);
      var failSearch = true;
      void progressed() {
        if (batch.state.value.processed >= 1) failSearch = false;
      }

      batch.state.addListener(progressed);
      fixture.intercept = (request) async {
        if (request.uri.path == '/3/search/tv') {
          if (failSearch) {
            request.response.statusCode = 503;
            await request.response.close();
          } else {
            await fixture.json(request, {
              'results': [fixture.tvCandidate(1)],
            });
          }
        } else {
          await defaults(request);
        }
      };
      try {
        await batch.start();
      } finally {
        batch.state.removeListener(progressed);
      }
      expect(batch.state.value.total, 2);
      expect(batch.state.value.processed, 2);
      expect(batch.state.value.failed, 1);
      expect(batch.state.value.matched, 1);
    },
  );

  test(
    'editing tolerance during search affects the next batch, not this snapshot',
    () async {
      fixture.intercept = (request) async {
        if (request.uri.path == '/3/search/tv') {
          await settings.setMatchTolerance(TmdbMatchTolerance.strict);
          await fixture.json(request, {
            'results': [fixture.tvCandidate(1)],
          });
        } else {
          await defaults(request);
        }
      };
      await batch.start();
      expect(batch.state.value.matched, 1);
      expect((await settings.read()).matchTolerance, TmdbMatchTolerance.strict);
    },
  );

  test('tolerance persistence keeps defaults, all values and invalid storage fallback', () async {
    expect((await settings.read()).matchTolerance, TmdbMatchTolerance.loose);
    for (final value in TmdbMatchTolerance.values) {
      await settings.setMatchTolerance(value);
      expect((await settings.read()).matchTolerance, value);
    }
    await sources.database.writePreference(
      TmdbSettingsRepository.toleranceKey,
      'invalid',
    );
    expect((await settings.read()).matchTolerance, TmdbMatchTolerance.loose);
  });
}
