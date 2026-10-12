import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/application/source_providers.dart';
import '../data/home_layout_repository.dart';
import '../domain/home_layout.dart';

final homeLayoutRepositoryProvider = Provider<HomeLayoutRepository>(
  (ref) => HomeLayoutRepository(ref.watch(sourceRepositoryProvider).database),
);

class HomeLayoutState {
  HomeLayoutState({
    HomeLayout? layout,
    this.ready = false,
    this.editing = false,
    this.saving = false,
    this.finishing = false,
    this.error,
  }) : layout = layout ?? HomeLayout();
  final HomeLayout layout;
  final bool ready, editing, saving, finishing;
  final String? error;
  HomeLayoutState copyWith({
    HomeLayout? layout,
    bool? editing,
    bool? saving,
    bool? finishing,
    String? error,
    bool clearError = false,
  }) => HomeLayoutState(
    layout: layout ?? this.layout,
    ready: ready,
    editing: editing ?? this.editing,
    saving: saving ?? this.saving,
    finishing: finishing ?? this.finishing,
    error: clearError ? null : error ?? this.error,
  );
}

final homeLayoutProvider =
    NotifierProvider<HomeLayoutController, HomeLayoutState>(
      HomeLayoutController.new,
    );

/// Serial, coalesced autosaves preserve drag-enter ordering. Completion waits
/// for the latest draft; failure keeps that draft and the editor available.
class HomeLayoutController extends Notifier<HomeLayoutState> {
  late HomeLayoutRepository _repository;
  int _generation = 0, _revision = 0, _savedRevision = 0;
  Future<void>? _saving;

  @override
  HomeLayoutState build() {
    _repository = ref.watch(homeLayoutRepositoryProvider);
    final generation = ++_generation;
    _revision = _savedRevision = 0;
    _saving = null;
    unawaited(Future<void>.microtask(() => _load(generation)));
    return HomeLayoutState();
  }

  bool _current(int generation) => ref.mounted && generation == _generation;
  Future<void> _load(int generation) async {
    try {
      final layout = await _repository.load();
      if (_current(generation)) {
        state = HomeLayoutState(layout: layout, ready: true);
      }
    } catch (_) {
      if (_current(generation)) state = HomeLayoutState(error: '首页布局读取失败，请重试。');
    }
  }

  Future<void> retryLoad() async {
    if (state.ready) return;
    state = HomeLayoutState();
    await _load(_generation);
  }

  void begin() {
    if (state.ready) state = state.copyWith(editing: true);
  }

  void move(HomeModule module, HomeModule destination) =>
      _apply(state.layout.move(module, destination));
  void hide(HomeModule module) => _apply(state.layout.hide(module));
  void restore(HomeModule module) => _apply(state.layout.restore(module));
  void reset() => _apply(HomeLayout());
  void _apply(HomeLayout layout) {
    if (!state.ready ||
        !state.editing ||
        state.finishing ||
        layout.sameAs(state.layout)) {
      return;
    }
    _revision++;
    state = state.copyWith(layout: layout, clearError: true);
    unawaited(_save());
  }

  Future<void> _save() {
    if (_saving != null) return _saving!;
    if (_savedRevision == _revision) return Future.value();
    final completion = Completer<void>();
    _saving = completion.future;
    state = state.copyWith(saving: true, clearError: true);
    unawaited(_drain(_generation, _repository, completion));
    return completion.future;
  }

  Future<void> _drain(
    int generation,
    HomeLayoutRepository repository,
    Completer<void> completion,
  ) async {
    try {
      while (_current(generation) && _savedRevision != _revision) {
        final revision = _revision, layout = state.layout;
        try {
          await repository.save(layout);
          if (!_current(generation)) break;
          _savedRevision = revision;
        } catch (_) {
          if (!_current(generation)) break;
          if (revision != _revision) continue;
          state = state.copyWith(saving: false, error: '首页布局保存失败，当前调整已保留，请重试。');
          break;
        }
      }
    } finally {
      if (_current(generation)) {
        _saving = null;
        state = state.copyWith(saving: false);
      }
      completion.complete();
    }
  }

  Future<void> retrySave() => _save();
  Future<bool> finish() async {
    if (!state.ready || state.finishing) return false;
    final generation = _generation;
    state = state.copyWith(finishing: true);
    await _save();
    if (!_current(generation)) return false;
    final saved = _savedRevision == _revision;
    state = state.copyWith(editing: !saved, finishing: false);
    return saved;
  }
}
