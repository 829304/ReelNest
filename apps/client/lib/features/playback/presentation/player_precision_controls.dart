import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/media_source.dart';
import '../../../player/video_engine.dart';
import '../application/playback_session.dart';
import '../application/playback_timeline_controller.dart';
import '../domain/playback_marker.dart';
import 'player_visuals.dart';

typedef PlayerNotice = void Function(String message);

class PlayerMarkerPanel extends StatefulWidget {
  const PlayerMarkerPanel({
    required this.session,
    required this.palette,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;

  @override
  State<PlayerMarkerPanel> createState() => _PlayerMarkerPanelState();
}

class _PlayerMarkerPanelState extends State<PlayerMarkerPanel> {
  ScanCancellation? _analysisCancellation;
  MediaIdentity? _identity;
  VideoEngine? _engine;
  bool _analyzing = false;
  String? _actionStatus;
  final _reviewingMarkerIds = <String>{};

  PlaybackSession get session => widget.session;
  PlayerPalette get palette => widget.palette;

  @override
  void initState() {
    super.initState();
    _identity = session.item?.identity;
    _engine = session.engine;
    session.addListener(_handleSessionChange);
  }

  @override
  void didUpdateWidget(covariant PlayerMarkerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == session) return;
    oldWidget.session.removeListener(_handleSessionChange);
    _cancelAnalysis();
    _actionStatus = null;
    _reviewingMarkerIds.clear();
    _identity = session.item?.identity;
    _engine = session.engine;
    session.addListener(_handleSessionChange);
  }

  @override
  void dispose() {
    session.removeListener(_handleSessionChange);
    _analysisCancellation?.cancel();
    super.dispose();
  }

  void _handleSessionChange() {
    final identity = session.item?.identity;
    final engine = session.engine;
    if (identity == _identity && identical(engine, _engine)) return;
    _identity = identity;
    _engine = engine;
    _cancelAnalysis();
    if (mounted) {
      setState(() {
        _actionStatus = null;
        _reviewingMarkerIds.clear();
      });
    }
  }

  void _cancelAnalysis() {
    _analysisCancellation?.cancel();
    _analysisCancellation = null;
    _analyzing = false;
  }

  bool get _canUse =>
      !session.loading &&
      session.engine != null &&
      session.error == null &&
      session.precision.value.identity != null;

  Future<void> _addChapter(Duration at) async {
    await session.addChapter(at: at);
  }

  Future<void> _addBookmark(Duration at) async {
    await session.addBookmark(at: at);
  }

  Future<void> _setBoundary(
    PlaybackMarkerKind kind, {
    required bool isStart,
    required Duration at,
  }) async {
    await session.setMarkerBoundary(kind, isStart: isStart, at: at);
  }

  Future<void> _delete(PlaybackMarker marker) async {
    await session.deletePlaybackMarker(marker.id);
  }

  Future<void> _analyze() async {
    final expectedSession = session;
    final identity = expectedSession.item?.identity;
    final expectedEngine = expectedSession.engine;
    if (!_canUse || _analyzing || identity == null) return;
    _analysisCancellation?.cancel();
    final cancellation = ScanCancellation();
    _analysisCancellation = cancellation;
    setState(() {
      _analyzing = true;
      _actionStatus = null;
    });
    final count = await expectedSession.analyzeIntroOutroMarkers(
      cancellation: cancellation,
    );
    if (!mounted ||
        !identical(_analysisCancellation, cancellation) ||
        session != expectedSession ||
        expectedSession.engine != expectedEngine ||
        expectedSession.item?.identity != identity) {
      return;
    }
    _analysisCancellation = null;
    setState(() {
      _analyzing = false;
      if (count != null && expectedSession.controlError == null) {
        _actionStatus = count == 0 ? '没有发现可审核候选' : '发现 $count 个待审核标记';
      }
    });
  }

  Future<void> _review(PlaybackMarker marker, {required bool accepted}) async {
    final expectedSession = session;
    final expectedEngine = expectedSession.engine;
    if (!_canUse ||
        !marker.isPendingReview ||
        marker.identity != expectedSession.item?.identity ||
        _reviewingMarkerIds.contains(marker.id)) {
      return;
    }
    setState(() {
      _reviewingMarkerIds.add(marker.id);
      _actionStatus = null;
    });
    await expectedSession.reviewAutomaticPlaybackMarker(
      marker,
      accepted: accepted,
    );
    if (!mounted ||
        session != expectedSession ||
        expectedSession.engine != expectedEngine ||
        marker.identity != expectedSession.item?.identity) {
      return;
    }
    final updated = expectedSession.precision.value.markers
        .where((value) => value.id == marker.id)
        .firstOrNull;
    final completed = accepted
        ? updated?.review == PlaybackMarkerReview.accepted
        : updated == null;
    setState(() {
      _reviewingMarkerIds.remove(marker.id);
      if (completed && expectedSession.controlError == null) {
        _actionStatus = accepted
            ? '已采用自动标记 · ${marker.kind.title}'
            : '已忽略自动标记 · ${marker.kind.title}';
      }
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoClock>(
    valueListenable: session.timeline,
    builder: (context, clock, _) =>
        ValueListenableBuilder<PlaybackTimelineState>(
          valueListenable: session.precision,
          builder: (context, state, _) {
            final current = clock.position;
            return Column(
              key: const ValueKey('player-marker-panel'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    Icon(
                      Icons.bookmark_outline,
                      size: 16,
                      color: palette.primary,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '章节与播放标记',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '仅管理 ReelNest 内部索引',
                            style: TextStyle(
                              color: palette.subdued,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatPrecisionTime(current),
                      style: TextStyle(
                        color: palette.secondary,
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: IconButton(
                        key: const ValueKey('refresh-playback-markers'),
                        tooltip: '刷新章节与标记',
                        padding: EdgeInsets.zero,
                        onPressed: _canUse
                            ? () => unawaited(session.refreshTimeline())
                            : null,
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: palette.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  spacing: 7,
                  children: [
                    Expanded(
                      child: _action(
                        key: const ValueKey('set-intro-start'),
                        icon: Icons.play_arrow_rounded,
                        label: '片头开始',
                        action: _canUse
                            ? () => _setBoundary(
                                PlaybackMarkerKind.intro,
                                isStart: true,
                                at: current,
                              )
                            : null,
                      ),
                    ),
                    Expanded(
                      child: _action(
                        key: const ValueKey('set-intro-end'),
                        icon: Icons.skip_next_rounded,
                        label: '片头结束',
                        action: _canUse
                            ? () => _setBoundary(
                                PlaybackMarkerKind.intro,
                                isStart: false,
                                at: current,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                Row(
                  spacing: 7,
                  children: [
                    Expanded(
                      child: _action(
                        key: const ValueKey('set-credits-start'),
                        icon: Icons.subject_rounded,
                        label: '片尾开始',
                        action: _canUse
                            ? () => _setBoundary(
                                PlaybackMarkerKind.credits,
                                isStart: true,
                                at: current,
                              )
                            : null,
                      ),
                    ),
                    Expanded(
                      child: _action(
                        key: const ValueKey('set-credits-end'),
                        icon: Icons.stop_rounded,
                        label: '片尾结束',
                        action: _canUse
                            ? () => _setBoundary(
                                PlaybackMarkerKind.credits,
                                isStart: false,
                                at: current,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                Row(
                  spacing: 7,
                  children: [
                    Expanded(
                      child: _action(
                        key: const ValueKey('add-playback-chapter'),
                        icon: Icons.bookmark_add_outlined,
                        label: '在 ${formatPrecisionTime(current)} 添加章节',
                        action: _canUse ? () => _addChapter(current) : null,
                      ),
                    ),
                    Expanded(
                      child: _action(
                        key: const ValueKey('add-playback-bookmark'),
                        icon: Icons.bookmarks_outlined,
                        label: '在 ${formatPrecisionTime(current)} 添加书签',
                        action: _canUse ? () => _addBookmark(current) : null,
                      ),
                    ),
                  ],
                ),
                // This phase exposes current-video analysis beside its review
                // list. The original media-item context-menu entry, series
                // batch analysis and task-center flow remain later migrations.
                SizedBox(
                  width: double.infinity,
                  child: _action(
                    key: const ValueKey('analyze-intro-outro-markers'),
                    icon: Icons.auto_awesome_rounded,
                    label: _analyzing ? '正在检测…' : '检测片头片尾',
                    busy: _analyzing,
                    action: _canUse && !_analyzing ? _analyze : null,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  child: _actionStatus == null
                      ? const SizedBox.shrink()
                      : Text(
                          _actionStatus!,
                          key: const ValueKey('marker-action-status'),
                          style: TextStyle(
                            color: palette.secondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                Divider(height: 1, color: palette.divider),
                if (state.markers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '当前视频还没有章节或手动标记。',
                      style: TextStyle(color: palette.secondary, fontSize: 11),
                    ),
                  )
                else
                  for (final marker in state.markers)
                    _markerRow(marker, current),
                AnimatedBuilder(
                  animation: session,
                  builder: (context, _) => session.controlError == null
                      ? const SizedBox.shrink()
                      : Text(
                          session.controlError!,
                          style: TextStyle(
                            color: palette.secondary,
                            fontSize: 10.5,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
  );

  Widget _action({
    required Key key,
    required IconData icon,
    required String label,
    required Future<void> Function()? action,
    bool busy = false,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: key,
      onTap: action == null ? null : () => unawaited(action()),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: palette.choiceFill,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: palette.rowStroke, width: .7),
        ),
        child: Row(
          spacing: 6,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: palette.primary,
                ),
              )
            else
              Icon(icon, size: 13, color: palette.primary),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _markerRow(PlaybackMarker marker, Duration current) {
    final selected =
        marker.contains(current) ||
        (marker.end == null &&
            (current - marker.start).abs().inMilliseconds < 500);
    return Row(
      key: ValueKey('playback-marker-${marker.id}'),
      spacing: 7,
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _canUse
                  ? () => unawaited(session.seekPlaybackMarker(marker.id))
                  : null,
              borderRadius: BorderRadius.circular(9),
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? palette.selectedFill : palette.rowFill,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected
                        ? palette.selectedStroke
                        : palette.rowStroke,
                    width: .7,
                  ),
                ),
                child: Row(
                  spacing: 8,
                  children: [
                    Icon(
                      switch (marker.kind) {
                        PlaybackMarkerKind.bookmark => Icons.bookmark_rounded,
                        PlaybackMarkerKind.intro => Icons.fast_forward_rounded,
                        PlaybackMarkerKind.credits => Icons.last_page_rounded,
                        PlaybackMarkerKind.chapter => Icons.flag_outlined,
                      },
                      size: 14,
                      color: palette.primary,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            marker.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _markerSubtitle(marker),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.subdued,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (marker.origin == PlaybackMarkerOrigin.manual)
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              tooltip: '删除标记',
              padding: EdgeInsets.zero,
              onPressed: _canUse ? () => unawaited(_delete(marker)) : null,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 14,
                color: Colors.redAccent,
              ),
            ),
          ),
        if (marker.isPendingReview) ...[
          SizedBox(
            width: 26,
            height: 26,
            child: IconButton(
              key: ValueKey('accept-automatic-marker-${marker.id}'),
              tooltip: '采用自动标记',
              padding: EdgeInsets.zero,
              onPressed: _canUse && !_reviewingMarkerIds.contains(marker.id)
                  ? () => unawaited(_review(marker, accepted: true))
                  : null,
              icon: const Icon(
                Icons.check_rounded,
                size: 11,
                color: Colors.green,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              key: ValueKey('reject-automatic-marker-${marker.id}'),
              tooltip: '忽略自动标记',
              padding: EdgeInsets.zero,
              onPressed: _canUse && !_reviewingMarkerIds.contains(marker.id)
                  ? () => unawaited(_review(marker, accepted: false))
                  : null,
              icon: const Icon(
                Icons.close_rounded,
                size: 11,
                color: Colors.orange,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _markerSubtitle(PlaybackMarker marker) {
    final origin = switch (marker.origin) {
      PlaybackMarkerOrigin.embedded => '内嵌章节',
      PlaybackMarkerOrigin.manual => '手动标记',
      PlaybackMarkerOrigin.automatic =>
        '${marker.isPendingReview ? '待审核' : '自动标记'}${marker.confidence == null ? '' : ' · ${(marker.confidence! * 100).round()}%'}',
    };
    final range = marker.end != null && marker.end! > marker.start
        ? ' – ${formatPrecisionTime(marker.end!)}'
        : '';
    return '$origin · ${formatPrecisionTime(marker.start)}$range';
  }
}

/// PlayerMarkerSkipLayer's prompt-only presentation. Automatic skipping is
/// performed by PlaybackSession; this widget never watches time or seeks on
/// behalf of the automatic policy.
class PlayerMarkerSkipPrompt extends StatelessWidget {
  const PlayerMarkerSkipPrompt({
    required this.session,
    required this.palette,
    super.key,
  });

  final PlaybackSession session;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PlaybackTimelineState>(
        valueListenable: session.precision,
        builder: (context, state, _) {
          final marker = state.skipBehavior == VideoMarkerSkipBehavior.prompt
              ? state.activeSkipMarker
              : null;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            reverseDuration: const Duration(milliseconds: 120),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .32),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: marker == null
                ? const SizedBox.shrink()
                : Material(
                    key: ValueKey('skip-marker-${marker.id}'),
                    type: MaterialType.transparency,
                    child: PlayerPanelSurface(
                      palette: palette,
                      radius: 17,
                      shadowRadius: 12,
                      shadowOffset: const Offset(0, 5),
                      child: InkWell(
                        key: const ValueKey('skip-active-playback-marker'),
                        onTap: session.loading || session.engine == null
                            ? null
                            : () => unawaited(
                                session.skipPlaybackMarker(marker.id),
                              ),
                        borderRadius: BorderRadius.circular(17),
                        child: SizedBox(
                          height: 34,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 7,
                              children: [
                                Icon(
                                  Icons.skip_next_rounded,
                                  size: 16,
                                  color: palette.primary,
                                ),
                                Text(
                                  '跳过${marker.kind.title}',
                                  style: TextStyle(
                                    color: palette.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          );
        },
      );
}

class PlayerTimelineMarkers extends StatelessWidget {
  const PlayerTimelineMarkers({
    required this.duration,
    required this.state,
    required this.palette,
    super.key,
  });

  final Duration duration;
  final PlaybackTimelineState state;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) {
    if (duration <= Duration.zero) return const SizedBox.shrink();
    final micros = duration.inMicroseconds;
    double fraction(Duration time) =>
        (time.inMicroseconds / micros).clamp(0.0, 1.0);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final usable = (width - 20).clamp(1.0, width);
          final loop = state.loop;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (loop.start != null)
                Positioned(
                  key: const ValueKey('ab-loop-indicator'),
                  left: 10 + usable * fraction(loop.start!),
                  right: loop.end == null
                      ? null
                      : 10 + usable * (1 - fraction(loop.end!)),
                  top: 11,
                  child: Container(
                    width: loop.end == null ? 2 : null,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              for (final marker in state.markers.where(
                (m) => m.isAcceptedForPlayback,
              ))
                Positioned(
                  key: ValueKey('timeline-marker-${marker.id}'),
                  left: 10 + usable * fraction(marker.start) - 1,
                  top: marker.kind == PlaybackMarkerKind.bookmark ? 5 : 7,
                  child: Container(
                    width: 2,
                    height: marker.kind == PlaybackMarkerKind.bookmark ? 11 : 9,
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(
                        alpha: marker.kind == PlaybackMarkerKind.bookmark
                            ? .96
                            : .82,
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> showPlayerPrecisionMenu(
  BuildContext context, {
  required Offset position,
  required PlaybackSession session,
  required PlayerPalette palette,
  required PlayerNotice onNotice,
  required VoidCallback onOpenPlaybackInfo,
  required VoidCallback? onToggleMiniMode,
  required bool miniMode,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '关闭播放器菜单',
  barrierColor: Colors.transparent,
  transitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => _PlayerPrecisionMenu(
    position: position,
    session: session,
    palette: palette,
    onNotice: onNotice,
    onOpenPlaybackInfo: onOpenPlaybackInfo,
    onToggleMiniMode: onToggleMiniMode,
    miniMode: miniMode,
  ),
);

class _PlayerPrecisionMenu extends StatelessWidget {
  const _PlayerPrecisionMenu({
    required this.position,
    required this.session,
    required this.palette,
    required this.onNotice,
    required this.onOpenPlaybackInfo,
    required this.onToggleMiniMode,
    required this.miniMode,
  });

  final Offset position;
  final PlaybackSession session;
  final PlayerPalette palette;
  final PlayerNotice onNotice;
  final VoidCallback onOpenPlaybackInfo;
  final VoidCallback? onToggleMiniMode;
  final bool miniMode;

  bool get _canControl =>
      !session.loading &&
      session.engine != null &&
      session.error == null &&
      session.precision.value.supported;

  Future<void> _loop(bool enabled) async {
    await session.setLoopCurrentItem(enabled);
    if (session.controlError == null) {
      onNotice(enabled ? '已开启单片循环' : '已关闭单片循环');
    }
  }

  Future<void> _cycleAB() async {
    await session.cycleABLoop();
    if (session.controlError != null) return;
    final loop = session.precision.value.loop;
    if (loop.start == null) return;
    onNotice(
      loop.end == null
          ? 'A-B 循环：A 点 ${formatPrecisionTime(loop.start!)}'
          : 'A-B 循环：${formatPrecisionTime(loop.start!)} - ${formatPrecisionTime(loop.end!)}',
    );
  }

  Future<void> _clearAB() async {
    await session.clearABLoop();
    if (session.controlError == null) onNotice('A-B 循环已清除');
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    const width = 286.0;
    const estimatedHeight = 360.0;
    final left = position.dx.clamp(12, screen.width - width - 12).toDouble();
    final top = position.dy
        .clamp(12, screen.height - estimatedHeight - 12)
        .toDouble();
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: PlayerPanelEntrance(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                session,
                session.precision,
                session.timeline,
              ]),
              builder: (context, _) {
                final state = session.precision.value;
                final loop = state.loop;
                return Material(
                  color: Colors.transparent,
                  child: PlayerPanelSurface(
                    key: const ValueKey('player-precision-menu'),
                    palette: palette,
                    radius: 15,
                    shadowRadius: 18,
                    shadowOffset: const Offset(0, 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _section('播放'),
                          _item(
                            key: const ValueKey('restart-playback'),
                            icon: Icons.first_page_rounded,
                            title: '从头播放',
                            shortcut: 'Home',
                            onTap: _canControl
                                ? () => session.seek(Duration.zero)
                                : null,
                          ),
                          _item(
                            key: const ValueKey('open-playback-info'),
                            icon: Icons.info_outline_rounded,
                            title: '播放信息',
                            shortcut: 'I',
                            onTap: () async {
                              Navigator.of(context).pop();
                              onOpenPlaybackInfo();
                            },
                          ),
                          if (onToggleMiniMode != null)
                            _item(
                              key: const ValueKey('toggle-mini-mode'),
                              icon: miniMode
                                  ? Icons.open_in_full_rounded
                                  : Icons.picture_in_picture_alt_rounded,
                              title: miniMode ? '还原窗口' : '迷你悬浮窗',
                              shortcut: 'P',
                              onTap: () async {
                                Navigator.of(context).pop();
                                onToggleMiniMode!();
                              },
                            ),
                          Divider(height: 11, color: palette.divider),
                          _section('循环'),
                          _item(
                            key: const ValueKey('toggle-current-loop'),
                            icon: Icons.repeat_one_rounded,
                            title: '单片循环',
                            value: loop.loopCurrentItem ? '已开启' : '已关闭',
                            selected: loop.loopCurrentItem,
                            onTap: _canControl
                                ? () => _loop(!loop.loopCurrentItem)
                                : null,
                          ),
                          _item(
                            key: const ValueKey('cycle-ab-loop'),
                            icon: Icons.repeat_rounded,
                            title: loop.start == null
                                ? '设置 A 点'
                                : loop.end == null
                                ? '设置 B 点'
                                : '重设 A 点',
                            value: _loopValue(loop),
                            shortcut: 'B',
                            onTap: _canControl ? _cycleAB : null,
                          ),
                          if (loop.start != null)
                            _item(
                              key: const ValueKey('clear-ab-loop'),
                              icon: Icons.cancel_outlined,
                              title: '清除 A-B 循环',
                              shortcut: 'Shift+B',
                              onTap: _canControl ? _clearAB : null,
                            ),
                          Divider(height: 11, color: palette.divider),
                          _section('逐帧'),
                          Row(
                            spacing: 6,
                            children: [
                              Expanded(
                                child: _compactAction(
                                  key: const ValueKey('step-frame-backward'),
                                  icon: Icons.skip_previous_rounded,
                                  title: '上一帧',
                                  shortcut: ',',
                                  action: _canControl
                                      ? () => session.stepFrame(backward: true)
                                      : null,
                                ),
                              ),
                              Expanded(
                                child: _compactAction(
                                  key: const ValueKey('step-frame-forward'),
                                  icon: Icons.skip_next_rounded,
                                  title: '下一帧',
                                  shortcut: '.',
                                  action: _canControl
                                      ? () => session.stepFrame()
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          if (!state.supported)
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Text(
                                '当前播放引擎不支持循环或逐帧操作。',
                                style: TextStyle(
                                  color: palette.subdued,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(7, 3, 7, 4),
    child: Text(
      title,
      style: TextStyle(
        color: palette.subdued,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _item({
    required Key key,
    required IconData icon,
    required String title,
    Future<void> Function()? onTap,
    String? value,
    String? shortcut,
    bool selected = false,
  }) => PlayerMenuRowSurface(
    key: key,
    palette: palette,
    selected: selected,
    minHeight: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    onTap: onTap == null ? null : () => unawaited(onTap()),
    fill: Colors.transparent,
    stroke: Colors.transparent,
    child: Row(
      spacing: 8,
      children: [
        Icon(icon, size: 15, color: palette.primary),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (value != null)
          Text(
            value,
            style: TextStyle(color: palette.secondary, fontSize: 10.5),
          ),
        if (shortcut != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              shortcut,
              style: TextStyle(color: palette.subdued, fontSize: 9.5),
            ),
          ),
      ],
    ),
  );

  Widget _compactAction({
    required Key key,
    required IconData icon,
    required String title,
    required String shortcut,
    required Future<void> Function()? action,
  }) => PlayerMenuRowSurface(
    key: key,
    palette: palette,
    minHeight: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    fill: palette.choiceFill,
    stroke: palette.rowStroke,
    onTap: action == null ? null : () => unawaited(action()),
    child: Row(
      spacing: 5,
      children: [
        Icon(icon, size: 14, color: palette.primary),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: palette.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(shortcut, style: TextStyle(color: palette.subdued, fontSize: 9.5)),
      ],
    ),
  );

  String? _loopValue(PlaybackLoopState loop) {
    final start = loop.start;
    if (start == null) return null;
    final end = loop.end;
    return end == null
        ? 'A ${formatPrecisionTime(start)}'
        : '${formatPrecisionTime(start)} – ${formatPrecisionTime(end)}';
  }
}

String formatPrecisionTime(Duration duration) {
  final total = duration.inSeconds.clamp(0, 1 << 32);
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = ((total ~/ 60) % 60).toString().padLeft(2, '0');
  return total >= 3600
      ? '${total ~/ 3600}:$minutes:$seconds'
      : '${total ~/ 60}:$seconds';
}
