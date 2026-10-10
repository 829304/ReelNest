import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/media_source.dart';
import '../../../player/video_engine.dart';
import '../application/playback_session.dart';
import 'player_track_popovers.dart';
import 'player_visuals.dart';

/// First functional port of PlayerView's video canvas and primary controls.
/// Uses its 568px bar, 14px glass corner, 7px timeline spacing, 42/50px clocks,
/// and a 44x30 play capsule. Remaining original panels are separate ports.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    required this.identity,
    required this.session,
    required this.closeWindow,
    required this.setFullscreen,
    super.key,
  });
  final MediaIdentity identity;
  final PlaybackSession session;
  final Future<void> Function() closeWindow;
  final Future<void> Function(bool) setFullscreen;
  @override
  State<VideoPlayerPage> createState() => VideoPlayerPageState();
}

class VideoPlayerPageState extends State<VideoPlayerPage> {
  bool _fullscreen = false;
  bool _controls = true;
  bool _closing = false;
  bool _hoverControls = false;
  double? _scrub;
  Timer? _hideTimer;
  bool _popoverActive = false;
  PlayerPalette _palette = const PlayerPalette();
  MediaIdentity? _paletteIdentity;
  final _subtitleButton = GlobalKey();
  final _audioButton = GlobalKey();
  final _volumeButton = GlobalKey();
  final _episodeButton = GlobalKey();
  final _settingsButton = GlobalKey();
  PlaybackSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    session.waitForSurface = _waitForSurface;
    session.addListener(_updatePalette);
    session.closeRequests.addListener(_onEndClose);
    unawaited(session.open(widget.identity));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    if (session.waitForSurface == _waitForSurface) {
      session.waitForSurface = null;
    }
    session.removeListener(_updatePalette);
    session.closeRequests.removeListener(_onEndClose);
    super.dispose();
  }

  Future<void> _waitForSurface() async {
    if (!mounted) throw StateError('Player surface detached');
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) throw StateError('Player surface detached');
  }

  void _onEndClose() {
    if (mounted) unawaited(requestClose());
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          session.clock.playing &&
          !_hoverControls &&
          !_popoverActive &&
          _scrub == null) {
        setState(() => _controls = false);
      }
    });
  }

  void _updatePalette() {
    final item = session.item;
    if (item == null || item.identity == _paletteIdentity) return;
    _paletteIdentity = item.identity;
    unawaited(
      PlayerPalette.forPoster(item.posterPath).then((value) {
        if (mounted && session.item?.identity == item.identity) {
          setState(() => _palette = value);
        }
      }),
    );
  }

  Future<void> _panel(PlayerPanel panel, GlobalKey key) async {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _popoverActive = true;
    _show();
    if (panel == PlayerPanel.episodes) {
      unawaited(session.refreshQueue());
    } else if (panel != PlayerPanel.settings) {
      unawaited(session.refreshTracks());
    }
    try {
      await showPlayerPanel(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        panel: panel,
        session: session,
        palette: _palette,
      );
    } finally {
      _popoverActive = false;
      if (mounted) _show();
    }
  }

  Widget _panelButton(
    String label,
    PlayerSymbol symbol,
    PlayerPanel panel,
    GlobalKey key,
    bool enabled,
  ) => Tooltip(
    message: label,
    child: SizedBox(
      key: key,
      width: 27,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: enabled ? () => unawaited(_panel(panel, key)) : null,
        icon: PlayerSymbolIcon(symbol, color: _palette.primary),
      ),
    ),
  );

  Future<void> _full() async {
    try {
      await widget.setFullscreen(!_fullscreen);
      if (mounted) setState(() => _fullscreen = !_fullscreen);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法切换全屏，请重试。')));
      }
    }
    _show();
  }

  Future<void> requestClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await session.close();
      if (session.saveError != null && mounted) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('播放进度未保存'),
            content: Text(session.saveError!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('重试'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('仍然关闭'),
              ),
            ],
          ),
        );
        if (!mounted || leave == null) return;
        if (leave == true) {
          await session.close(discardProgress: true);
        } else {
          await session.close();
          if (session.saveError != null) return;
        }
      }
      if (mounted) await widget.closeWindow();
    } finally {
      _closing = false;
    }
  }

  Widget _icon(
    String label,
    IconData icon,
    VoidCallback? action, {
    double width = 27,
    Color? color,
  }) => Tooltip(
    message: label,
    child: SizedBox(
      width: width,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: action,
        icon: Icon(
          icon,
          size: 17,
          color: color ?? Colors.white.withValues(alpha: .95),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.space): () {
        _show();
        unawaited(session.toggle());
      },
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        _show();
        unawaited(session.skip(-1));
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        _show();
        unawaited(session.skip(1));
      },
      const SingleActivator(LogicalKeyboardKey.keyF): () => unawaited(_full()),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        _show();
        unawaited(session.volume(session.clock.volume + 5.5));
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        _show();
        unawaited(session.volume(session.clock.volume - 5.5));
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        _show();
        unawaited(session.mute());
      },
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(_fullscreen ? _full() : requestClose()),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) => _show(),
          child: AnimatedBuilder(
            animation: session,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                if (session.engine != null) session.engine!.surface(),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _show,
                  onDoubleTap: () => unawaited(_full()),
                  child: const SizedBox.expand(),
                ),
                if (session.loading)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text('正在打开视频…', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                if (session.error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            session.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => unawaited(
                              session.open(
                                session.item?.identity ?? widget.identity,
                              ),
                            ),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            session.item?.cardTitle ?? 'ReelNest',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _icon(
                          '关闭播放器',
                          Icons.close,
                          () => unawaited(requestClose()),
                        ),
                      ],
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: ValueListenableBuilder<VideoClock>(
                      valueListenable: session.timeline,
                      builder: (context, value, _) => AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: _controls || !value.playing ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !_controls && value.playing,
                          child: _bar(value),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bar(VideoClock value) {
    final can =
        !session.loading &&
        session.error == null &&
        value.duration > Duration.zero;
    final duration = value.duration.inMilliseconds.toDouble();
    final position = (_scrub ?? value.position.inMilliseconds.toDouble()).clamp(
      0.0,
      duration > 0 ? duration : 1.0,
    );
    return MouseRegion(
      onEnter: (_) {
        _hoverControls = true;
        _show();
      },
      onExit: (_) {
        _hoverControls = false;
        _show();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 568),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _palette.barFill,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border.all(color: _palette.border.first),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.buffering && !session.loading)
                    const Text(
                      '正在缓冲…',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  if (session.saveError != null)
                    Text(
                      session.saveError!,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                  if (session.syncError != null)
                    Text(
                      session.syncError!,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                  if (session.controlError != null)
                    Text(
                      session.controlError!,
                      style: TextStyle(color: _palette.secondary, fontSize: 11),
                    ),
                  if (session.transitionMessage != null)
                    Text(
                      session.transitionMessage!,
                      style: TextStyle(color: _palette.secondary, fontSize: 11),
                    ),
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(
                          formatVideoTime(
                            Duration(milliseconds: position.toInt()),
                          ),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: _palette.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: _palette.trackProgress,
                            inactiveTrackColor: _palette.trackBase,
                            thumbColor: _palette.primary,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            key: const ValueKey('video-timeline'),
                            min: 0,
                            max: duration > 0 ? duration : 1,
                            value: position,
                            onChangeStart: can
                                ? (v) {
                                    _show();
                                    setState(() => _scrub = v);
                                  }
                                : null,
                            onChanged: can
                                ? (v) => setState(() => _scrub = v)
                                : null,
                            onChangeEnd: can
                                ? (v) {
                                    setState(() => _scrub = null);
                                    unawaited(
                                      session.seek(
                                        Duration(milliseconds: v.toInt()),
                                      ),
                                    );
                                    _show();
                                  }
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 50,
                        child: Text(
                          formatVideoTime(value.duration),
                          style: TextStyle(
                            color: _palette.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 200,
                        child: Row(
                          children: [
                            if (session.queue.items.length > 1) ...[
                              _panelButton(
                                '剧集列表',
                                PlayerSymbol.episodes,
                                PlayerPanel.episodes,
                                _episodeButton,
                                can,
                              ),
                              const SizedBox(width: 5),
                            ],
                            _panelButton(
                              '字幕',
                              PlayerSymbol.subtitle,
                              PlayerPanel.subtitles,
                              _subtitleButton,
                              can,
                            ),
                            const SizedBox(width: 5),
                            _panelButton(
                              '音轨',
                              PlayerSymbol.audio,
                              PlayerPanel.audio,
                              _audioButton,
                              can,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _icon(
                        '上一集',
                        Icons.skip_previous,
                        can ? () => unawaited(session.adjacent(-1)) : null,
                        color: _palette.primary,
                      ),
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: _palette.choiceFill,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: _icon(
                          '播放/暂停',
                          value.playing ? Icons.pause : Icons.play_arrow,
                          can ? () => unawaited(session.toggle()) : null,
                          width: 44,
                          color: _palette.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _icon(
                        '下一集',
                        Icons.skip_next,
                        can ? () => unawaited(session.adjacent(1)) : null,
                        color: _palette.primary,
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 200,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _panelButton(
                              '音量',
                              value.volume == 0
                                  ? PlayerSymbol.muted
                                  : PlayerSymbol.speaker,
                              PlayerPanel.volume,
                              _volumeButton,
                              can,
                            ),
                            const SizedBox(width: 5),
                            _panelButton(
                              '播放器设置',
                              PlayerSymbol.settings,
                              PlayerPanel.settings,
                              _settingsButton,
                              can,
                            ),
                            const SizedBox(width: 5),
                            _icon(
                              _fullscreen ? '退出全屏' : '全屏',
                              _fullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              () => unawaited(_full()),
                              color: _palette.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String formatVideoTime(Duration duration) {
  final total = duration.inSeconds.clamp(0, 1 << 32);
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = ((total ~/ 60) % 60).toString().padLeft(2, '0');
  return total >= 3600
      ? '${total ~/ 3600}:$minutes:$seconds'
      : '${total ~/ 60}:$seconds';
}
