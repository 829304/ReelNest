import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/home/application/home_layout_provider.dart';
import 'package:reelnest/features/home/data/home_layout_repository.dart';
import 'package:reelnest/features/home/domain/home_layout.dart';
import 'package:reelnest/storage/library_database.dart';

class ControlledLayoutRepository extends HomeLayoutRepository {
  ControlledLayoutRepository(super.database);
  HomeLayout value = HomeLayout();
  bool failLoad = false, failSave = false;
  int reads = 0;
  final writes = <HomeLayout>[];
  Completer<void>? gate;
  Completer<HomeLayout>? loadGate;
  @override
  Future<HomeLayout> load() async {
    reads++;
    if (failLoad) throw StateError('read failure');
    return loadGate?.future ?? value;
  }

  @override
  Future<void> save(HomeLayout layout) async {
    writes.add(layout);
    await gate?.future;
    if (failSave) throw StateError('disk failure');
    value = layout;
  }
}

void main() {
  test(
    'Swift normalization retains first known IDs then appends missing defaults',
    () {
      final layout = HomeLayout.decode(
        'dashboard,hero,dashboard,unknown,stats',
        'favorites,favorites,unknown',
      );
      expect(layout.order.take(3), [
        HomeModule.dashboard,
        HomeModule.hero,
        HomeModule.stats,
      ]);
      expect(layout.order.toSet().length, HomeModule.values.length);
      expect(layout.order.length, HomeModule.values.length);
      expect(layout.hidden, {HomeModule.favorites});
      expect(layout.canReset, true);
      expect(
        layout.order.indexOf(HomeModule.musicRecommendations),
        lessThan(layout.order.indexOf(HomeModule.continueListening)),
      );
      expect(layout.added.every((m) => m.implemented), true);
    },
  );
  test('default module order mirrors HomeView except excluded photos', () {
    expect(HomeLayout().order.map((m) => m.name), [
      'hero',
      'stats',
      'seriesRecommendations',
      'continueWatching',
      'recentlyPlayed',
      'watchlist',
      'favorites',
      'musicRecommendations',
      'continueListening',
      'recentSeries',
      'highRated',
      'dashboard',
    ]);
    expect(
      HomeModule.values.map((m) => m.title),
      containsAll(['每日推荐', '媒体总览', '运行状态']),
    );
    expect(HomeLayout().canReset, false);
  });
  test('drag moves before destination in either direction, preserving hidden positions', () {
    final layout = HomeLayout().hide(HomeModule.watchlist);
    final moved = layout.move(HomeModule.dashboard, HomeModule.stats);
    expect(moved.order.take(3), [
      HomeModule.hero,
      HomeModule.dashboard,
      HomeModule.stats,
    ]);
    expect(moved.hidden, {HomeModule.watchlist});
    final down = moved.move(HomeModule.hero, HomeModule.highRated);
    expect(
      down.order.indexOf(HomeModule.hero) + 1,
      down.order.indexOf(HomeModule.highRated),
    );
    expect(down.move(HomeModule.hero, HomeModule.hero), same(down));
  });
  test('restore appends to current end; hidden choices use default order', () {
    final layout = HomeLayout()
        .hide(HomeModule.watchlist)
        .hide(HomeModule.hero)
        .move(HomeModule.dashboard, HomeModule.stats);
    expect(layout.addable, [HomeModule.hero, HomeModule.watchlist]);
    final restored = layout.restore(HomeModule.hero);
    expect(restored.order.last, HomeModule.hero);
    expect(restored.hidden, {HomeModule.watchlist});
    expect(restored.restore(HomeModule.stats), same(restored));
  });
  test('last implemented module cannot be hidden; malformed all-hidden layout keeps a recovery entry', () {
    var layout = HomeLayout();
    for (final module in HomeModule.values) {
      layout = layout.hide(module);
    }
    expect(layout.added, [HomeModule.dashboard]);
    expect(layout.hide(HomeModule.dashboard), same(layout));
    final broken = HomeLayout(hidden: HomeModule.values);
    expect(broken.added, [HomeModule.hero]);
    expect(broken.addable, contains(HomeModule.hero));
  });

  group('SQLite preferences', () {
    late LibraryDatabase database;
    late HomeLayoutRepository repository;
    setUp(() {
      database = LibraryDatabase(NativeDatabase.memory());
      repository = HomeLayoutRepository(database);
    });
    tearDown(() => database.close());

    test('fresh repository restores saved order/hidden state; reset removes only home keys', () async {
      await database.customStatement(
        "INSERT INTO player_preferences VALUES('global.volume','0.5')",
      );
      final layout = HomeLayout()
          .move(HomeModule.dashboard, HomeModule.hero)
          .hide(HomeModule.favorites);
      await repository.save(layout);
      final reopened = await HomeLayoutRepository(database).load();
      expect(reopened.sameAs(layout), true);
      await repository.save(HomeLayout());
      expect((await repository.load()).canReset, false);
      final row = await database
          .customSelect('SELECT * FROM player_preferences')
          .getSingle();
      expect(row.read<String>('key'), 'global.volume');
      expect(row.read<String>('value'), '0.5');
    });

    test(
      'failure on second preference rolls back order and visibility together',
      () async {
        final initial = HomeLayout()
            .move(HomeModule.dashboard, HomeModule.stats)
            .hide(HomeModule.watchlist);
        await repository.save(initial);
        await database.customStatement(
          '''CREATE TRIGGER reject_hidden BEFORE INSERT ON player_preferences
        WHEN NEW.key = 'home.hiddenModules' BEGIN SELECT RAISE(ABORT, 'test write failure'); END''',
        );
        final changed = initial
            .move(HomeModule.stats, HomeModule.hero)
            .hide(HomeModule.favorites);
        await expectLater(repository.save(changed), throwsA(anything));
        expect((await repository.load()).sameAs(initial), true);
      },
    );
  });

  group('editor controller', () {
    late LibraryDatabase database;
    late ControlledLayoutRepository repository;
    late ProviderContainer container;
    setUp(() {
      database = LibraryDatabase(NativeDatabase.memory());
      repository = ControlledLayoutRepository(database);
      container = ProviderContainer(
        overrides: [homeLayoutRepositoryProvider.overrideWithValue(repository)],
      );
    });
    tearDown(() async {
      container.dispose();
      await database.close();
    });
    Future<HomeLayoutController> ready() async {
      final controller = container.read(homeLayoutProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(homeLayoutProvider).ready, true);
      return controller;
    }

    test(
      'serial autosave coalesces rapid moves and Done waits for latest draft',
      () async {
        final controller = await ready();
        repository.gate = Completer<void>();
        controller.begin();
        controller.move(HomeModule.dashboard, HomeModule.hero);
        controller.hide(HomeModule.favorites);
        controller.restore(HomeModule.favorites);
        final draft = container.read(homeLayoutProvider).layout;
        final done = controller.finish();
        expect(repository.writes.length, 1);
        expect(container.read(homeLayoutProvider).finishing, true);
        repository.gate!.complete();
        expect(await done, true);
        expect(repository.writes.length, 2);
        expect(repository.value.sameAs(draft), true);
        expect(container.read(homeLayoutProvider).editing, false);
        expect(repository.reads, 1);
      },
    );

    test('failed save retains draft/editor and supports retry without another read', () async {
      final controller = await ready();
      controller.begin();
      repository.failSave = true;
      controller.hide(HomeModule.hero);
      expect(await controller.finish(), false);
      final failed = container.read(homeLayoutProvider);
      expect(failed.editing, true);
      expect(failed.layout.hidden, {HomeModule.hero});
      expect(failed.error, contains('保存失败'));
      repository.failSave = false;
      await controller.retrySave();
      expect(container.read(homeLayoutProvider).editing, true);
      expect(await controller.finish(), true);
      expect(repository.value.hidden, {HomeModule.hero});
      expect(repository.reads, 1);
    });

    test(
      'failed obsolete write cannot overwrite a newer successful draft',
      () async {
        final controller = await ready();
        repository.gate = Completer<void>();
        repository.failSave = true;
        controller.begin();
        controller.hide(HomeModule.hero);
        await Future<void>.delayed(Duration.zero);
        controller.restore(HomeModule.hero);
        repository.failSave = false;
        repository.gate!.complete();
        await controller.finish();
        expect(repository.value.order.last, HomeModule.hero);
        expect(repository.value.hidden, isEmpty);
        expect(container.read(homeLayoutProvider).error, isNull);
      },
    );

    test('load failure blocks editing/default overwrite; retry restores saved layout', () async {
      repository.failLoad = true;
      final controller = container.read(homeLayoutProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(homeLayoutProvider).ready, false);
      controller.begin();
      controller.hide(HomeModule.hero);
      expect(await controller.finish(), false);
      expect(repository.writes, isEmpty);
      repository.failLoad = false;
      repository.value = HomeLayout().hide(HomeModule.stats);
      await controller.retryLoad();
      expect(container.read(homeLayoutProvider).layout.hidden, {
        HomeModule.stats,
      });
      expect(container.read(homeLayoutProvider).error, isNull);
    });

    test('disposal retires slow load and pending saves cleanly', () async {
      repository.loadGate = Completer<HomeLayout>();
      container.read(homeLayoutProvider);
      await Future<void>.delayed(Duration.zero);
      container.dispose();
      repository.loadGate!.complete(HomeLayout().hide(HomeModule.hero));
      await Future<void>.delayed(Duration.zero);
      // A separately created editor reads the saved preferences, with no stale
      // completion attempting to write state into its disposed predecessor.
      container = ProviderContainer(
        overrides: [homeLayoutRepositoryProvider.overrideWithValue(repository)],
      );
      expect((await ready()).state.layout.hidden, {HomeModule.hero});
    });
  });
}
