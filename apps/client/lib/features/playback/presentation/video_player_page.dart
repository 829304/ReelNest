import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/media_source.dart';
import '../../../player/video_engine.dart';
import '../application/playback_session.dart';

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
  PlaybackSession get session => widget.session;
  @override
  void initState() {
    super.initState();
    unawaited(session.open(widget.identity));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _show() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          session.clock.playing &&
          !_hoverControls &&
          _scrub == null) {
        setState(() => _controls = false);
      }
    });
  }

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
  }) => Tooltip(
    message: label,
    child: SizedBox(
      width: width,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: action,
        icon: Icon(icon, size: 17, color: Colors.white.withValues(alpha: .95)),
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
        unawaited(
          session.seek(session.clock.position - const Duration(seconds: 5)),
        );
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        _show();
        unawaited(
          session.seek(session.clock.position + const Duration(seconds: 5)),
        );
      },
      const SingleActivator(LogicalKeyboardKey.keyF): () => unawaited(_full()),
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
                color: Colors.white.withValues(alpha: .20),
                border: Border.all(color: Colors.white.withValues(alpha: .25)),
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
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(
                          formatVideoTime(
                            Duration(milliseconds: position.toInt()),
                          ),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: Colors.white.withValues(
                              alpha: .82,
                            ),
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: .18,
                            ),
                            thumbColor: Colors.white,
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
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 170,
                        child: Row(
                          children: [
                            _icon(
                              '后退 5 秒',
                              Icons.replay_5,
                              can
                                  ? () => unawaited(
                                      session.seek(
                                        value.position -
                                            const Duration(seconds: 5),
                                      ),
                                    )
                                  : null,
                            ),
                            _icon(
                              '快进 5 秒',
                              Icons.forward_5,
                              can
                                  ? () => unawaited(
                                      session.seek(
                                        value.position +
                                            const Duration(seconds: 5),
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: _icon(
                          '播放/暂停',
                          value.playing ? Icons.pause : Icons.play_arrow,
                          can ? () => unawaited(session.toggle()) : null,
                          width: 44,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 170,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _icon(
                              value.volume == 0 ? '取消静音' : '静音',
                              value.volume == 0
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                              can
                                  ? () => unawaited(
                                      session.volume(
                                        value.volume == 0 ? 80 : 0,
                                      ),
                                    )
                                  : null,
                            ),
                            SizedBox(
                              width: 95,
                              child: Slider(
                                key: const ValueKey('video-volume'),
                                value: value.volume.clamp(0, 100),
                                min: 0,
                                max: 100,
                                activeColor: Colors.white70,
                                inactiveColor: Colors.white24,
                                onChanged: can
                                    ? (v) => unawaited(session.volume(v))
                                    : null,
                              ),
                            ),
                            _icon(
                              _fullscreen ? '退出全屏' : '全屏',
                              _fullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              () => unawaited(_full()),
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
