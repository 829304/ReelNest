import 'package:flutter/foundation.dart';

import '../../../domain/media_source.dart';
import '../../../player/video_timeline.dart';
import '../data/playback_marker_repository.dart';
import '../data/player_preferences_repository.dart';
import '../domain/playback_marker.dart';

class PlaybackTimelineState {
  const PlaybackTimelineState({
    this.identity,
    this.supported = false,
    this.markers = const [],
    this.loop = const PlaybackLoopState(),
    this.skipBehavior = VideoMarkerSkipBehavior.prompt,
    this.activeSkipMarker,
  });
  final MediaIdentity? identity;
  final bool supported;
  final List<PlaybackMarker> markers;
  final PlaybackLoopState loop;
  final VideoMarkerSkipBehavior skipBehavior;
  final PlaybackMarker? activeSkipMarker;
  List<PlaybackMarker> get chapters => markers
      .where(
        (m) => m.kind == PlaybackMarkerKind.chapter && m.isAcceptedForPlayback,
      )
      .toList(growable: false);
  List<PlaybackMarker> get bookmarks => markers
      .where(
        (m) => m.kind == PlaybackMarkerKind.bookmark && m.isAcceptedForPlayback,
      )
      .toList(growable: false);
}

/// Internal session collaborator. All calls are serialized by PlaybackSession;
/// the front end observes state and calls the session's public commands.
class PlaybackTimelineController extends ValueNotifier<PlaybackTimelineState> {
  PlaybackTimelineController(this.repository, this.preferences)
    : super(const PlaybackTimelineState());
  final PlaybackMarkerRepository repository;
  final PlayerPreferencesRepository preferences;
  VideoTimelineEngine? _engine;
  Duration _offset = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  Future<void> attach(
    MediaIdentity identity,
    VideoTimelineEngine? engine, {
    required Duration offset,
    required Duration duration,
    required PlaybackLoopState loop,
    VideoMarkerSkipBehavior skipBehavior = VideoMarkerSkipBehavior.prompt,
    Duration position = Duration.zero,
  }) async {
    _engine = engine;
    _offset = offset;
    _duration = duration;
    _position = position;
    value = PlaybackTimelineState(
      identity: identity,
      supported: engine != null,
      loop: loop,
      skipBehavior: skipBehavior,
    );
    await refresh();
  }

  void detach() {
    _engine = null;
    value = const PlaybackTimelineState();
  }

  Future<void> refresh() async {
    final identity = value.identity;
    if (identity == null) return;
    var chapterReadFailed = false;
    try {
      await _engine?.refreshChapters();
    } catch (_) {
      chapterReadFailed = true;
    }
    final chapters = _engine?.chapters ?? const <VideoChapter>[];
    // A transcoded suffix may omit earlier chapters. It cannot replace a full
    // persisted chapter list. Keep the observed suffix only as a display fallback.
    final embedded = [
      for (var i = 0; i < chapters.length; i++)
        PlaybackMarker(
          id: 'embedded-${chapters[i].index}-${(chapters[i].time + _offset).inMicroseconds}',
          identity: identity,
          kind: PlaybackMarkerKind.chapter,
          title: chapters[i].title,
          start: chapters[i].time + _offset,
          end: i + 1 < chapters.length
              ? chapters[i + 1].time + _offset
              : _duration > chapters[i].time + _offset
              ? _duration
              : null,
          origin: PlaybackMarkerOrigin.embedded,
        ),
    ];
    // Like PlayerView.syncEmbeddedChapters, an empty decoder snapshot is not
    // evidence that cached chapters should be deleted.
    if (embedded.isNotEmpty && _offset == Duration.zero) {
      await repository.replaceEmbedded(identity, embedded);
    }
    final markers = await repository.read(identity);
    if (_offset > Duration.zero &&
        !markers.any((m) => m.origin == PlaybackMarkerOrigin.embedded)) {
      markers.addAll(embedded);
      markers.sort((a, b) => a.start.compareTo(b.start));
    }
    value = PlaybackTimelineState(
      identity: identity,
      supported: _engine != null,
      markers: List.unmodifiable(markers),
      loop: value.loop,
      skipBehavior: value.skipBehavior,
      activeSkipMarker: _activeMarker(markers, value.skipBehavior),
    );
    if (chapterReadFailed) throw StateError('Chapter refresh failed');
  }

  Future<void> addManual(PlaybackMarkerKind kind, Duration time) async {
    if (kind != PlaybackMarkerKind.chapter &&
        kind != PlaybackMarkerKind.bookmark) {
      throw ArgumentError('Not a point marker');
    }
    final identity = value.identity;
    if (identity == null) return;
    final number =
        value.markers
            .where(
              (m) => m.kind == kind && m.origin == PlaybackMarkerOrigin.manual,
            )
            .length +
        1;
    await repository.save(
      PlaybackMarker(
        identity: identity,
        kind: kind,
        title: '${kind == PlaybackMarkerKind.chapter ? '手动章节' : '书签'} $number',
        start: time,
      ),
    );
    await refresh();
  }

  Future<int> analyzeIntroOutroMarkers({
    required Duration duration,
    ScanCancellation? cancellation,
  }) async {
    final identity = value.identity;
    if (identity == null) return 0;
    // Refresh absolute, persisted chapters first. An observed transcoded suffix
    // alone must not be mistaken for a full chapter snapshot by the detector.
    cancellation?.check();
    await refresh();
    cancellation?.check();
    final count = await repository.generateIntroOutroCandidates(
      identity,
      duration: duration,
      cancellation: cancellation,
    );
    await refresh();
    return count;
  }

  Future<void> reviewAutomatic(
    PlaybackMarker marker, {
    required bool accepted,
  }) async {
    if (value.identity != marker.identity || !marker.isPendingReview) return;
    await repository.reviewAutomatic(
      marker.identity,
      marker.id,
      accepted: accepted,
    );
    await refresh();
  }

  Future<void> deleteManual(String id) async {
    final identity = value.identity;
    if (identity == null) return;
    await repository.deleteManual(identity, id);
    await refresh();
  }

  Future<void> setBoundary(
    PlaybackMarkerKind kind, {
    required bool isStart,
    required Duration at,
  }) async {
    final identity = value.identity;
    if (identity == null) return;
    await repository.setManualBoundary(
      identity,
      kind,
      isStart: isStart,
      at: at,
    );
    await refresh();
  }

  Future<void> setSkipBehavior(VideoMarkerSkipBehavior behavior) async {
    await preferences.rememberMarkerSkipBehavior(behavior);
    value = PlaybackTimelineState(
      identity: value.identity,
      supported: value.supported,
      markers: value.markers,
      loop: value.loop,
      skipBehavior: behavior,
      activeSkipMarker: _activeMarker(value.markers, behavior),
    );
  }

  PlaybackMarker? _activeMarker(
    List<PlaybackMarker> markers,
    VideoMarkerSkipBehavior behavior,
  ) => behavior == VideoMarkerSkipBehavior.off
      ? null
      : markers
            .where(
              (m) =>
                  (m.kind == PlaybackMarkerKind.intro ||
                      m.kind == PlaybackMarkerKind.credits) &&
                  m.isAcceptedForPlayback &&
                  m.contains(_position),
            )
            .firstOrNull;

  /// A clock tick does no I/O and only notifies on range entry/exit, so marker
  /// panels and the skip overlay do not rebuild at playback-clock frequency.
  void updatePosition(Duration position, {bool enabled = true}) {
    _position = position;
    final active = enabled
        ? _activeMarker(value.markers, value.skipBehavior)
        : null;
    if (active == value.activeSkipMarker) return;
    value = PlaybackTimelineState(
      identity: value.identity,
      supported: value.supported,
      markers: value.markers,
      loop: value.loop,
      skipBehavior: value.skipBehavior,
      activeSkipMarker: active,
    );
  }

  Future<void> setLoopCurrentItem(bool enabled) async {
    final engine = _engine;
    if (engine == null) throw StateError('Timeline controls unavailable');
    final previous = value.loop;
    try {
      await engine.setLoopCurrentItem(enabled);
      await preferences.rememberLoopCurrentItem(enabled);
    } catch (_) {
      await engine.setLoopCurrentItem(previous.loopCurrentItem);
      rethrow;
    }
    _publishLoop(
      PlaybackLoopState(
        loopCurrentItem: enabled,
        start: previous.start,
        end: previous.end,
      ),
    );
  }

  Future<void> cycleABLoop(Duration position) =>
      _setABLoop(value.loop.cycle(position));
  Future<void> clearABLoop() => _setABLoop(
    PlaybackLoopState(loopCurrentItem: value.loop.loopCurrentItem),
  );
  Future<void> _setABLoop(PlaybackLoopState next) async {
    final engine = _engine;
    if (engine == null) throw StateError('Timeline controls unavailable');
    Duration? relative(Duration? time) => time == null ? null : time - _offset;
    final previous = value.loop;
    try {
      await engine.setABLoop(relative(next.start), relative(next.end));
    } catch (_) {
      await engine.setABLoop(relative(previous.start), relative(previous.end));
      rethrow;
    }
    _publishLoop(next);
  }

  void _publishLoop(PlaybackLoopState loop) {
    value = PlaybackTimelineState(
      identity: value.identity,
      supported: value.supported,
      markers: value.markers,
      loop: loop,
      skipBehavior: value.skipBehavior,
      activeSkipMarker: value.activeSkipMarker,
    );
  }
}
