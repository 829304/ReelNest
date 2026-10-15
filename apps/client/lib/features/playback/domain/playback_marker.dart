import 'dart:math';

import '../../../domain/media_source.dart';

enum VideoMarkerSkipBehavior {
  off('关闭', '不显示片头/片尾跳过入口，章节和手动标记仍会保留。'),
  prompt('显示按钮', '进入完整片头或片尾范围时显示跳过按钮，由你手动确认。'),
  automatic('自动跳过', '进入已确认的片头或片尾范围后直接跳到结束位置。');

  const VideoMarkerSkipBehavior(this.title, this.description);
  final String title;
  final String description;
}

enum PlaybackMarkerKind {
  chapter('章节'),
  intro('片头'),
  credits('片尾'),
  bookmark('书签');

  const PlaybackMarkerKind(this.title);
  final String title;
}

enum PlaybackMarkerOrigin { embedded, manual, automatic }

enum PlaybackMarkerReview { accepted, pending, rejected }

class PlaybackMarker {
  PlaybackMarker({
    String? id,
    required this.identity,
    required this.kind,
    required String title,
    required Duration start,
    Duration? end,
    this.origin = PlaybackMarkerOrigin.manual,
    PlaybackMarkerReview review = PlaybackMarkerReview.accepted,
    this.detectorIdentifier,
    double? confidence,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _newId(),
       title = title.trim().isEmpty ? kind.title : title.trim(),
       start = start < Duration.zero ? Duration.zero : start,
       end = end != null && end < Duration.zero ? Duration.zero : end,
       review = origin == PlaybackMarkerOrigin.automatic
           ? review
           : PlaybackMarkerReview.accepted,
       confidence = confidence?.isFinite == true
           ? confidence!.clamp(0, 1)
           : null,
       createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final String id;
  final MediaIdentity identity;
  final PlaybackMarkerKind kind;
  final String title;
  final Duration start;
  final Duration? end;
  final PlaybackMarkerOrigin origin;
  final PlaybackMarkerReview review;
  final String? detectorIdentifier;
  final double? confidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  bool get isPendingReview =>
      origin == PlaybackMarkerOrigin.automatic &&
      review == PlaybackMarkerReview.pending;
  bool get isCompleteRange => end != null && end! > start;
  bool contains(Duration time) =>
      isCompleteRange && time >= start && time < end!;
  bool get isAcceptedForPlayback =>
      origin != PlaybackMarkerOrigin.automatic ||
      review == PlaybackMarkerReview.accepted;

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

class PlaybackLoopState {
  const PlaybackLoopState({this.loopCurrentItem = false, this.start, this.end});
  final bool loopCurrentItem;
  final Duration? start;
  final Duration? end;
  bool get hasRange => start != null && end != null && end! > start!;

  /// Original PlaybackABLoopPolicy: a completed range starts a fresh A point;
  /// a B point at or before A + 0.20s also replaces A. Clearing is explicit.
  PlaybackLoopState cycle(Duration position) {
    final time = position < Duration.zero ? Duration.zero : position;
    if (start == null ||
        end != null ||
        time <= start! + const Duration(milliseconds: 200)) {
      return PlaybackLoopState(loopCurrentItem: loopCurrentItem, start: time);
    }
    return PlaybackLoopState(
      loopCurrentItem: loopCurrentItem,
      start: start,
      end: time,
    );
  }
}
