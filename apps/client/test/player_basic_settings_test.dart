import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/data/player_preferences_repository.dart';
import 'package:reelnest/features/playback/domain/playback_options.dart';
import 'package:reelnest/features/playback/domain/playback_record.dart';
import 'package:reelnest/features/playback/presentation/player_behavior_settings.dart';
import 'package:reelnest/features/playback/presentation/player_visuals.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/platform/playback_sleep_guard.dart';
import 'package:reelnest/sources/filesystem/file_source_adapter.dart';
import 'package:reelnest/storage/library_database.dart';

import 'support/fake_video_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late SourceRepository sources;
  late PlayerPreferencesRepository preferences;
  late PlaybackRepository records;
  late PlaybackSession session;
  late MediaIdentity film;
  final engines = <FakeVideoEngine>[];
  var resourcesClosed = false;
  setUp(() async {
    engines.clear();
    resourcesClosed = false;
    sandbox = await Directory.systemTemp.createTemp('reelnest-basic-settings-');
    for (final name in ['Film.mkv', 'Show.S01E01.mkv', 'Show.S01E02.mkv']) {
      await File(p.join(sandbox.path, name))
          .writeAsString('fake decoder fixture');
    }
    sources = SourceRepository(
      database: LibraryDatabase(
        NativeDatabase(File(p.join(sandbox.path, 'library.sqlite'))),
      ),
      adapters: {MediaSourceKind.localFolder: FileSourceAdapter()},
      identityLookup: (_) async => 'fixture-volume',
    );
    final source = await sources.add(
      kind: MediaSourceKind.localFolder,
      name: 'Test',
      location: sandbox.path,
      minimumFileSize: 0,
    );
    await sources.scan(source.id);
    film = (sourceId: source.id, localId: 'Film.mkv');
    preferences = PlayerPreferencesRepository(sources.database);
    records = PlaybackRepository(sources.database);
    session = PlaybackSession(
      sources: sources,
      records: records,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final engine = FakeVideoEngine();
        engines.add(engine);
        return engine;
      },
    );
  });
  tearDown(() async {
    if (!resourcesClosed) {
      await session.close(discardProgress: true);
      session.dispose();
      await sources.close();
    }
    expect(p.isWithin(Directory.systemTemp.path, sandbox.path), isTrue);
    expect(p.basename(sandbox.path), startsWith('reelnest-basic-settings-'));
    await sandbox.delete(recursive: true);
  });

  Future<void> restart(MediaIdentity identity) async {
    await session.close();
    session.dispose();
    session = PlaybackSession(
      sources: sources,
      records: records,
      checkpointInterval: const Duration(hours: 1),
      createEngine: () {
        final engine = FakeVideoEngine();
        engines.add(engine);
        return engine;
      },
    );
    await session.open(identity);
  }

  test(
    'empty preferences use original defaults and bounded finite values',
    () async {
      final defaults = await preferences.options;
      expect(defaults.defaultRate, 1);
      expect(defaults.skipSeconds, 5);
      expect(defaults.rewindSeconds, 5);
      expect(defaults.launchVolume, 80);
      expect(defaults.watchedThreshold, .9);
      expect(
        defaults.rememberPosition &&
            defaults.rememberRate &&
            defaults.autoMarkWatched &&
            defaults.pitchCorrection,
        isTrue,
      );
      expect(defaults.useLaunchVolume, isFalse);
      final parsed = PlaybackOptions.fromJson({
        'defaultRate': double.nan,
        'skipSeconds': 1000,
        'rewindSeconds': 12,
        'launchVolume': -1,
        'rememberRate': 'false',
      });
      expect(parsed.defaultRate, 1);
      expect(parsed.skipSeconds, 30);
      expect(parsed.rewindSeconds, 10);
      expect(parsed.launchVolume, 0);
      expect(parsed.rememberRate, isTrue);
    },
  );
  test('resume policy changes start without deleting saved records', () async {
    await records.save(
      film,
      position: const Duration(seconds: 35),
      duration: const Duration(seconds: 100),
    );
    await preferences.rememberOptions(
      const PlaybackOptions(rememberPosition: false),
    );
    await session.open(film);
    expect(engines.last.openedAt, Duration.zero);
    expect((await records.read(film)).position.inSeconds, 35);
    await session.changeOptions(
      (o) => o.copyWith(rememberPosition: true, rewindSeconds: 15),
    );
    engines.last.emit(position: const Duration(seconds: 35));
    await restart(film);
    expect(engines.last.openedAt!.inSeconds, 20);
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(seconds: 11),
      ).resume(rewindSeconds: 30),
      Duration.zero,
    );
    expect(
      PlaybackRecord(
        identity: film,
        position: const Duration(seconds: 10),
      ).resume(rewindSeconds: 30).inSeconds,
      10,
    );
  });
  test('current rate remembers by series, reset and disabled policy preserve defaults', () async {
    final inventory = (await sources.inventory()).items;
    final one = inventory.singleWhere(
      (i) => i.identity.localId == 'Show.S01E01.mkv',
    );
    final two = inventory.singleWhere(
      (i) => i.identity.localId == 'Show.S01E02.mkv',
    );
    expect(one.parentId, isNotNull);
    await preferences.rememberOptions(const PlaybackOptions(defaultRate: 1.25));
    await session.open(one.identity);
    expect(session.clock.rate, 1.25);
    await session.rate(1.75, remember: false);
    expect(await preferences.rate(one), isNull);
    await session.rate(1.5);
    expect(await preferences.rate(two), 1.5);
    final otherSource = IndexedMedia(
      identity: (sourceId: 'other', localId: two.identity.localId),
      title: two.title,
      type: two.type,
      bytes: two.bytes,
      modified: two.modified,
      parentId: two.parentId,
    );
    expect(await preferences.rate(otherSource), isNull);
    await session.open(two.identity);
    expect(session.clock.rate, 1.5);
    await session.changeOptions((o) => o.copyWith(rememberRate: false));
    await session.rate(2);
    expect(await preferences.rate(two), 1.5);
    await session.open(one.identity);
    expect(session.clock.rate, 1.25);
    await session.changeOptions((o) => o.copyWith(rememberRate: true));
    await session.rate(1);
    expect(await preferences.rate(two), isNull);
    await session.open(two.identity);
    expect(session.clock.rate, 1.25);
  });
  test('option updates serialize without overwriting another setting or current speed', () async {
    await session.open(film);
    await Future.wait([
      session.changeOptions((o) => o.copyWith(skipSeconds: 15)),
      session.changeOptions((o) => o.copyWith(defaultRate: 1.5)),
    ]);
    expect(session.options.skipSeconds, 15);
    expect((await preferences.options).defaultRate, 1.5);
    expect((await preferences.options).skipSeconds, 15);
    expect(session.clock.rate, 1);
    engines.last.emit(position: const Duration(seconds: 95));
    await session.skip(1);
    expect(session.clock.position.inSeconds, 100);
    await session.skip(-1);
    expect(session.clock.position.inSeconds, 85);
    await restart(film);
    expect(session.clock.rate, 1.5);
  });
  test(
    'launch volume switch chooses configured level or previous logical volume',
    () async {
      await preferences.rememberNumber('videoVolume', 43);
      await session.open(film);
      expect(session.clock.volume, 43);
      await session.changeOptions(
        (o) => o.copyWith(useLaunchVolume: true, launchVolume: 25),
      );
      expect(session.clock.volume, 43);
      await restart(film);
      expect(session.clock.volume, 25);
      await session.volume(67);
      await session.changeOptions((o) => o.copyWith(useLaunchVolume: false));
      await restart(film);
      expect(session.clock.volume, 67);
    },
  );
  test('watched threshold is refreshed across connections and watched stays sticky', () async {
    await session.open(film);
    await session.changeOptions((o) => o.copyWith(autoMarkWatched: false));
    engines.last.emit(position: const Duration(seconds: 95));
    await session.save();
    expect((await records.read(film)).watched, isFalse);
    await session.changeOptions((o) => o.copyWith(autoMarkWatched: true));
    final peer = LibraryDatabase(
      NativeDatabase(File(p.join(sandbox.path, 'library.sqlite'))),
    );
    addTearDown(peer.close);
    final mainWindowPreferences = PlayerPreferencesRepository(peer);
    await mainWindowPreferences.rememberWatchedThreshold(.8);
    engines.last.emit(position: const Duration(seconds: 80));
    await session.save();
    expect((await records.read(film)).watched, isTrue);
    await mainWindowPreferences.rememberWatchedThreshold(.95);
    await session.changeOptions((o) => o.copyWith(autoMarkWatched: false));
    engines.last.emit(position: const Duration(seconds: 2));
    await session.save();
    expect((await records.read(film)).watched, isTrue);
    expect(await preferences.watchedThreshold, .95);
  });
  test('pitch change applies live and storage failure rolls back without closing playback', () async {
    await session.open(film);
    await session.changeOptions((o) => o.copyWith(pitchCorrection: false));
    expect(engines.last.pitchCorrection, isFalse);
    await sources.database.customStatement(
      "CREATE TRIGGER reject_options BEFORE INSERT ON player_preferences BEGIN SELECT RAISE(ABORT, 'fixture'); END",
    );
    await session.changeOptions((o) => o.copyWith(pitchCorrection: true));
    expect(session.options.pitchCorrection, isFalse);
    expect(engines.last.pitchCorrection, isFalse);
    expect(session.controlError, isNotNull);
    expect(session.error, isNull);
    expect(engines.last.disposals, 0);
    await sources.database.customStatement('DROP TRIGGER reject_options');
    await session.changeOptions((o) => o.copyWith(pitchCorrection: true));
    expect(session.controlError, isNull);
    expect(engines.last.pitchCorrection, isTrue);
  });
  testWidgets(
    'behavior dialog fits long labels and persists a user selection',
    (tester) async {
      Future<void> finish(Future<void> operation) async {
        var done = false;
        operation.then((_) => done = true);
        for (var n = 0; n < 150 && !done; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue, reason: 'Settings operation did not finish');
      }

      await finish(session.open(film));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlayerBehaviorSettings(
                context,
                session,
                const PlayerPalette(),
              ),
              child: const Text('settings'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();
      expect(find.text('记忆本片倍速'), findsOneWidget);
      expect(find.text('自动标记已看'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('15秒').first);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(session.options.skipSeconds, 15);
      late PlaybackOptions saved;
      await finish(preferences.options.then((value) => saved = value));
      expect(saved.skipSeconds, 15);
      await finish(session.close(discardProgress: true));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      await finish(sources.close());
      resourcesClosed = true;
    },
  );

  group('sleep requests', () {
    const channel = MethodChannel('reelnest/playback_sleep');
    final calls = <bool>[];
    final guards = <PlaybackSleepGuard>[];
    var reject = false;
    setUp(() {
      calls.clear();
      guards.clear();
      reject = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.arguments as bool);
            if (reject) throw PlatformException(code: 'fixture');
            return null;
          });
    });
    tearDown(() async {
      reject = false;
      for (final guard in guards) {
        await guard.dispose();
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    Future<void> drain() =>
        Future<void>.delayed(const Duration(milliseconds: 15));
    test('play pause resume and disposal balance requests', () async {
      final guard = PlaybackSleepGuard((_) {});
      guards.add(guard);
      guard.update(true);
      await drain();
      guard.update(true);
      await drain();
      guard.update(false);
      await drain();
      guard.update(true);
      await drain();
      await guard.dispose();
      expect(calls, [true, false, true, false]);
    });
    test(
      'disposing old decoder does not release a playing replacement',
      () async {
        final first = PlaybackSleepGuard((_) {}),
            second = PlaybackSleepGuard((_) {});
        guards.addAll([first, second]);
        first.update(true);
        await drain();
        second.update(true);
        await drain();
        await first.dispose();
        expect(calls, [true]);
        await second.dispose();
        expect(calls, [true, false]);
      },
    );
    test('request error warns and a later play can recover', () async {
      final warnings = <String?>[];
      final guard = PlaybackSleepGuard(warnings.add);
      guards.add(guard);
      reject = true;
      guard.update(true);
      await drain();
      expect(warnings.last, isNotNull);
      guard.update(false);
      await drain();
      reject = false;
      guard.update(true);
      await drain();
      expect(warnings.last, isNull);
      await guard.dispose();
      expect(calls, [true, true, false]);
    });
  });
}
