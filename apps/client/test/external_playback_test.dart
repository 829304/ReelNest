import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/domain/remote_media_metadata.dart';
import 'package:reelnest/features/playback/application/external_playback_providers.dart';
import 'package:reelnest/features/playback/application/external_playback_service.dart';
import 'package:reelnest/features/playback/application/playback_providers.dart';
import 'package:reelnest/features/playback/data/external_player_settings_repository.dart';
import 'package:reelnest/features/playback/domain/external_player_settings.dart';
import 'package:reelnest/features/playback/domain/transient_playback_target.dart';
import 'package:reelnest/features/sources/application/source_providers.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/external_player_gateway.dart';
import 'package:reelnest/player/playback_diagnostics.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

class _Gateway implements ExternalPlayerGateway {
  final launches = <(String, String?)>[];
  Future<void> Function()? onLaunch, onValidate;
  @override
  Future<void> validateApplication(String path) async {
    await onValidate?.call();
  }

  @override
  Future<List<ExternalPlayerApplication>> availablePlayers({
    String? customPath,
  }) async => const [];
  @override
  Future<void> launch(String location, {String? applicationPath}) async {
    launches.add((location, applicationPath));
    await onLaunch?.call();
  }
}

class _BuiltIn implements PlaybackTargetLauncher {
  int library = 0, temporary = 0;
  @override
  Future<void> open(MediaIdentity identity) async {
    library++;
  }

  @override
  Future<void> openTransient(TransientPlaybackTarget target) async {
    temporary++;
  }
}

void main() {
  late Directory sandbox;
  late SourceRepository sources;
  late ExternalPlayerSettingsRepository settings;
  late _Gateway gateway;
  late ExternalPlaybackService service;
  late File video;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('reelnest-external-');
    video = await File(p.join(sandbox.path, 'Film.mkv'))
        .writeAsString('fixture');
    sources = SourceRepository(
      database: LibraryDatabase(NativeDatabase.memory()),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture',
    );
    settings = ExternalPlayerSettingsRepository(sources.database);
    gateway = _Gateway();
    service = ExternalPlaybackService(
      sources: sources,
      settings: settings,
      gateway: gateway,
    );
  });
  tearDown(() async {
    await service.dispose();
    await sources.close();
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-external-'));
    await sandbox.delete(recursive: true);
  });
  Future<MediaIdentity> local() async {
    final source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Library',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    return (sourceId: source.id, localId: 'Film.mkv');
  }

  Future<MediaIdentity> remote() async {
    final source = await sources.add(
      kind: MediaSourceKind.emby,
      name: 'Emby',
      location: 'emby://server/user',
    );
    await sources.database.customStatement(
      "INSERT INTO media(source_id,local_id,title,type,bytes,modified,identity_kind) VALUES(?,?,'Remote','movie',0,0,'remote')",
      [source.id, 'movie'],
    );
    await sources.database.customStatement(
      'INSERT INTO remote_media_metadata(source_id,local_id,value) VALUES(?,?,?)',
      [
        source.id,
        'movie',
        jsonEncode(const RemoteMediaMetadata(externalId: 'movie').toJson()),
      ],
    );
    return (sourceId: source.id, localId: 'movie');
  }

  test(
    'default is built-in, settings persist without changing schema',
    () async {
      expect((await settings.load()).mode, ExternalPlayerMode.builtIn);
      await settings.save(
        const ExternalPlayerSettings(
          mode: ExternalPlayerMode.external,
          applicationPath: 'C:/Player/player.exe',
        ),
      );
      final restored = await ExternalPlayerSettingsRepository(sources.database)
          .load();
      expect(restored.mode, ExternalPlayerMode.external);
      expect(restored.applicationPath, 'C:/Player/player.exe');
      expect(sources.database.schemaVersion, 1);
    },
  );
  test(
    'explicit external open ignores built-in preference and writes no progress',
    () async {
      final identity = await local();
      await service.openLibrary(identity);
      expect(gateway.launches, [(video.path, null)]);
      expect(
        (await sources.database
                .customSelect('SELECT COUNT(*) AS n FROM playback_states')
                .getSingle())
            .read<int>('n'),
        0,
      );
    },
  );
  test(
    'normal library and temporary playback route by fresh preference',
    () async {
      final builtin = _BuiltIn();
      final route = PreferredPlaybackLauncher(
        builtIn: builtin,
        settings: settings,
        external: service,
      );
      final identity = await local();
      final target = TransientPlaybackTarget.file(video.path);
      await route.open(identity);
      await route.openTransient(target);
      expect((builtin.library, builtin.temporary), (1, 1));
      await settings.save(
        const ExternalPlayerSettings(mode: ExternalPlayerMode.external),
      );
      await route.open(identity);
      await route.openTransient(target);
      expect(gateway.launches, hasLength(2));
      expect((builtin.library, builtin.temporary), (1, 1));
    },
  );
  test(
    'explicit configured app receives exactly the original media location',
    () async {
      await settings.save(
        const ExternalPlayerSettings(applicationPath: 'C:/A B/player.exe'),
      );
      final target = TransientPlaybackTarget.stream(
        'https://user:private@host/Film.mp4?token=secret&x=1',
      );
      await service.openTransient(target);
      expect(gateway.launches.single, (target.location, 'C:/A B/player.exe'));
    },
  );
  test('external protocol scope rejects RTSP before launch', () async {
    await expectLater(
      service.openTransient(TransientPlaybackTarget.stream('rtsp://host/live')),
      throwsA(isA<SourceFailure>()),
    );
    expect(gateway.launches, isEmpty);
  });
  test('missing file rejects before launch', () async {
    await expectLater(
      service.openTransient(
        TransientPlaybackTarget.file(p.join(sandbox.path, 'Missing.mkv')),
      ),
      throwsA(isA<SourceFailure>()),
    );
    expect(gateway.launches, isEmpty);
  });
  test(
    'cached resources are held, deduplicated, renewed and released at disposal',
    () async {
      final identity = await remote();
      final released = <String>[], renewed = <String>[];
      var serial = 0, online = 0;
      await service.dispose();
      service = ExternalPlaybackService(
        sources: sources,
        settings: settings,
        gateway: gateway,
        acquireCache: (_) async =>
            (path: video.path, lease: 'lease-${++serial}'),
        releaseCache: (id) async {
          released.add(id);
        },
        renewCache: (id) async {
          renewed.add(id);
        },
        remoteResource: (_) async {
          online++;
          return 'https://host/movie.mp4';
        },
        renewInterval: const Duration(milliseconds: 10),
      );
      await service.openLibrary(identity);
      await service.openLibrary(identity);
      expect(service.retainedResources, 1);
      expect(released, ['lease-2']);
      expect(online, 0);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(renewed, contains('lease-1'));
      await service.dispose();
      await service.dispose();
      expect(released, ['lease-2', 'lease-1']);
      expect(service.retainedResources, 0);
    },
  );
  test('definite launch failure releases a candidate lease', () async {
    final identity = await remote();
    final released = <String>[];
    await service.dispose();
    service = ExternalPlaybackService(
      sources: sources,
      settings: settings,
      gateway: gateway,
      acquireCache: (_) async => (path: video.path, lease: 'failed'),
      releaseCache: (id) async {
        released.add(id);
      },
    );
    gateway.onLaunch = () async => throw StateError('sensitive decoder output');
    await expectLater(
      service.openLibrary(identity),
      throwsA(isA<SourceFailure>()),
    );
    expect(released, ['failed']);
    expect(service.retainedResources, 0);
  });
  test('uncertain timed-out launch retains cache until app disposal', () async {
    final identity = await remote();
    final released = <String>[];
    final launched = Completer<void>();
    await service.dispose();
    service = ExternalPlaybackService(
      sources: sources,
      settings: settings,
      gateway: gateway,
      acquireCache: (_) async => (path: video.path, lease: 'pending'),
      releaseCache: (id) async {
        released.add(id);
      },
      launchTimeout: const Duration(milliseconds: 10),
    );
    gateway.onLaunch = () => launched.future;
    await expectLater(
      service.openLibrary(identity),
      throwsA(isA<SourceFailure>()),
    );
    expect(released, isEmpty);
    expect(service.retainedResources, 1);
    launched.complete();
    await service.dispose();
    expect(released, ['pending']);
  });
  test(
    'unavailable cache falls back to a fresh remote address without writes',
    () async {
      final identity = await remote();
      await service.dispose();
      service = ExternalPlaybackService(
        sources: sources,
        settings: settings,
        gateway: gateway,
        acquireCache: (_) async =>
            throw const FileSystemException('private path'),
        remoteResource: (_) async => 'https://host/movie.mp4?token=private',
      );
      await service.openLibrary(identity);
      expect(
        gateway.launches.single.$1,
        'https://host/movie.mp4?token=private',
      );
    },
  );
  test('launch errors are sanitized in the UI and diagnostics', () async {
    final logs = Directory(p.join(sandbox.path, 'logs'));
    final diagnostics = PlaybackDiagnostics(
      directory: () async => logs,
      writerId: '11-22',
    );
    await service.dispose();
    service = ExternalPlaybackService(
      sources: sources,
      settings: settings,
      gateway: gateway,
      diagnostics: diagnostics,
    );
    gateway.onLaunch = () async =>
        throw StateError('https://user:password@host/a?token=private');
    await expectLater(
      service.openTransient(
        TransientPlaybackTarget.stream('https://host/a?token=private'),
      ),
      throwsA(
        isA<SourceFailure>().having(
          (e) => e.message,
          'message',
          isNot(contains('private')),
        ),
      ),
    );
    await diagnostics.flush();
    final text = await File(p.join(logs.path, 'playback-11-22.jsonl'))
        .readAsString();
    expect(text, contains('external_launch_failed'));
    expect(text, isNot(contains('password')));
    expect(text, isNot(contains('token=')));
  });
  test(
    'settings controller serial mode and app changes merge latest state',
    () async {
      final container = ProviderContainer(
        overrides: [
          sourceRepositoryProvider.overrideWithValue(sources),
          externalPlayerGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      await container.read(externalPlayerSettingsProvider.future);
      final controller = container.read(
        externalPlayerSettingsProvider.notifier,
      );
      final gate = Completer<void>();
      gateway.onValidate = () => gate.future;
      final selected = controller.selectApplication('C:/Player/player.exe');
      final changed = controller.setMode(ExternalPlayerMode.external);
      gate.complete();
      await selected;
      await changed;
      final value = await settings.load();
      expect(value.mode, ExternalPlayerMode.external);
      expect(value.applicationPath, 'C:/Player/player.exe');
    },
  );
  test(
    'closing waits for an active launch and rejects queued launches',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      gateway.onLaunch = () async {
        started.complete();
        await finish.future;
      };
      final target = TransientPlaybackTarget.file(video.path);
      final first = service.openTransient(target);
      await started.future;
      final queued = expectLater(
        service.openTransient(target),
        throwsA(isA<SourceFailure>()),
      );
      final closing = service.dispose();
      expect(identical(closing, service.dispose()), isTrue);
      finish.complete();
      await first;
      await queued;
      await closing;
      expect(gateway.launches, hasLength(1));
      expect(service.retainedResources, 0);
    },
  );
  test(
    'failed settings save retains committed mode and can be retried',
    () async {
      final container = ProviderContainer(
        overrides: [sourceRepositoryProvider.overrideWithValue(sources)],
      );
      addTearDown(container.dispose);
      await container.read(externalPlayerSettingsProvider.future);
      await sources.database.customStatement('''
      CREATE TRIGGER reject_external_settings BEFORE INSERT ON player_preferences
      BEGIN SELECT RAISE(FAIL, 'fixture write failure'); END
    ''');
      final controller = container.read(
        externalPlayerSettingsProvider.notifier,
      );
      await expectLater(
        controller.setMode(ExternalPlayerMode.external),
        throwsA(anything),
      );
      expect(
        container.read(externalPlayerSettingsProvider).requireValue.mode,
        ExternalPlayerMode.builtIn,
      );
      expect((await settings.load()).mode, ExternalPlayerMode.builtIn);
      await sources.database.customStatement(
        'DROP TRIGGER reject_external_settings',
      );
      await controller.setMode(ExternalPlayerMode.external);
      expect((await settings.load()).mode, ExternalPlayerMode.external);
    },
  );
  test('explicit user edit repairs damaged settings while passive read preserves them', () async {
    await sources.database.customStatement(
      'INSERT INTO player_preferences(key,value) VALUES(?,?)',
      [ExternalPlayerSettingsRepository.key, 'invalid'],
    );
    await expectLater(settings.load(), throwsA(isA<SourceFailure>()));
    final container = ProviderContainer(
      overrides: [
        sourceRepositoryProvider.overrideWithValue(sources),
        externalPlayerGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(externalPlayerSettingsProvider.future),
      throwsA(isA<SourceFailure>()),
    );
    await container
        .read(externalPlayerSettingsProvider.notifier)
        .setMode(ExternalPlayerMode.external);
    expect((await settings.load()).mode, ExternalPlayerMode.external);
  });
}
