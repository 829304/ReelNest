import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../ui/widgets/slider_overlay_scope.dart';
import '../../../domain/media_source.dart';
import '../../../player/video_engine.dart';
import '../application/playback_session.dart';
import '../application/playback_timeline_controller.dart';
import 'player_precision_controls.dart';
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
  Timer? _noticeTimer;
  Timer? _volumeHudTimer;
  String? _notice;
  double? _volumeHud;
  bool _popoverActive = false;
  PlayerPanel? _activePanel;
  bool _maximized = false;
  Offset? _pointerActivityAnchor;
  PlayerPalette _palette = const PlayerPalette();
  MediaIdentity? _paletteIdentity;
  final _subtitleButton = GlobalKey();
  final _audioButton = GlobalKey();
  final _volumeButton = GlobalKey();
  final _episodeButton = GlobalKey();
  final _settingsButton = GlobalKey();
  final _qualityButton = GlobalKey();
  final _markerButton = GlobalKey();
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
    _noticeTimer?.cancel();
    _volumeHudTimer?.cancel();
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
    _hideTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted &&
          session.clock.playing &&
          !_hoverControls &&
          !_popoverActive &&
          _scrub == null) {
        setState(() => _controls = false);
      }
    });
  }

  void _handlePointerHover(PointerHoverEvent event) {
    final previous = _pointerActivityAnchor;
    final threshold = _controls ? 1.5 : 3.0;
    if (previous != null &&
        (event.localPosition - previous).distance < threshold) {
      return;
    }
    _pointerActivityAnchor = event.localPosition;
    _show();
  }

  bool get _shouldHideCursor =>
      !_controls &&
      !_popoverActive &&
      session.clock.playing &&
      !session.loading &&
      session.error == null;

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
    setState(() {
      _popoverActive = true;
      _activePanel = panel;
    });
    _show();
    if (panel == PlayerPanel.episodes) {
      unawaited(session.refreshQueue());
    } else if (panel != PlayerPanel.settings && panel != PlayerPanel.quality) {
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
      if (mounted) {
        setState(() {
          _popoverActive = false;
          _activePanel = null;
        });
        _show();
      } else {
        _popoverActive = false;
        _activePanel = null;
      }
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _showVolumeHud(double volume) {
    if (!mounted) return;
    _volumeHudTimer?.cancel();
    setState(() => _volumeHud = volume.clamp(0, 100).toDouble());
    _volumeHudTimer = Timer(const Duration(milliseconds: 950), () {
      if (mounted) setState(() => _volumeHud = null);
    });
  }

  Future<void> _changeVolume(double delta) async {
    final next = (session.clock.volume + delta).clamp(0, 100).toDouble();
    _showVolumeHud(next);
    await session.volume(next);
  }

  Future<void> _toggleMuteWithHud() async {
    await session.mute();
    if (mounted) _showVolumeHud(session.clock.volume);
  }

  Future<void> _cycleABLoop() async {
    _show();
    await session.cycleABLoop();
    if (!mounted || session.controlError != null) return;
    final loop = session.precision.value.loop;
    if (loop.start == null) return;
    _showNotice(
      loop.end == null
          ? 'A-B 循环：A 点 ${formatPrecisionTime(loop.start!)}'
          : 'A-B 循环：${formatPrecisionTime(loop.start!)} - ${formatPrecisionTime(loop.end!)}',
    );
  }

  Future<void> _clearABLoop() async {
    _show();
    await session.clearABLoop();
    if (mounted && session.controlError == null) {
      _showNotice('A-B 循环已清除');
    }
  }

  Future<void> _precisionMenu(Offset position) async {
    _popoverActive = true;
    _show();
    try {
      await showPlayerPrecisionMenu(
        context,
        position: position,
        session: session,
        palette: _palette,
        onNotice: _showNotice,
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
  ) => Semantics(
    container: true,
    child: Tooltip(
      message: label,
      child: SizedBox(
        key: key,
        width: 28,
        height: 28,
        child: PlayerControlSurface(
          palette: _palette,
          enabled: enabled,
          selected: _activePanel == panel,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 14,
            onPressed: enabled ? () => unawaited(_panel(panel, key)) : null,
            icon: PlayerSymbolIcon(
              symbol,
              color: enabled ? _palette.primary : _palette.subdued,
              size: 14,
            ),
          ),
        ),
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

  Future<void> _minimize() => windowManager.minimize();

  Future<void> _toggleMaximize() async {
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (mounted) setState(() => _maximized = !maximized);
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
    bool chrome = false,
    bool emphasized = false,
    bool danger = false,
  }) => Semantics(
    container: true,
    child: Tooltip(
      message: label,
      child: SizedBox(
        width: width,
        height: emphasized ? 30 : 28,
        child: PlayerControlSurface(
          palette: _palette,
          enabled: action != null,
          chrome: chrome,
          capsule: emphasized,
          danger: danger,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: emphasized ? 20 : 14,
            onPressed: action,
            icon: Icon(
              icon,
              size: emphasized ? 18 : 15,
              color:
                  color ??
                  (chrome
                      ? Colors.white.withValues(alpha: .94)
                      : _palette.primary),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _windowChrome() {
    final customButtons = !Platform.isMacOS;
    return SizedBox(
      key: const ValueKey('player-window-chrome'),
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: Platform.isMacOS ? 72 : 2),
                  child: Text(
                    session.item?.cardTitle ?? 'ReelNest',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xF2FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .1,
                      shadows: [
                        Shadow(
                          color: Color(0xB3000000),
                          blurRadius: 9,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (customButtons) ...[
            _icon(
              '最小化',
              Icons.remove_rounded,
              () => unawaited(_minimize()),
              chrome: true,
            ),
            const SizedBox(width: 7),
            _icon(
              _maximized ? '还原窗口' : '最大化',
              _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              () => unawaited(_toggleMaximize()),
              chrome: true,
            ),
            const SizedBox(width: 7),
            _icon(
              '关闭播放器',
              Icons.close_rounded,
              () => unawaited(requestClose()),
              chrome: true,
              danger: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _edgeScrims({required bool visible}) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: const Column(
        children: [
          SizedBox(
            height: 96,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x9C000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          Spacer(),
          SizedBox(
            height: 156,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xA6000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _statusGlass({required Widget child, double radius = 22}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              decoration: BoxDecoration(
                color: const Color(0xB31D2026),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .18),
                  width: .8,
                ),
              ),
              child: child,
            ),
          ),
        ),
      );

  Widget _loadingOverlay() => Center(
    child: IgnorePointer(
      child: _statusGlass(
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 42,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Color(0x33FFFFFF),
              ),
            ),
            SizedBox(height: 14),
            Text(
              '正在打开视频',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '正在准备播放画面…',
              style: TextStyle(color: Color(0xB8FFFFFF), fontSize: 11.5),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _errorOverlay(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: _statusGlass(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_disabled_rounded,
                size: 44,
                color: Colors.white.withValues(alpha: .74),
              ),
              const SizedBox(height: 12),
              const Text(
                '内置播放器无法播放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .70),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => unawaited(
                  session.open(session.item?.identity ?? widget.identity),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _noticeOverlay() => Align(
    alignment: Alignment.topCenter,
    child: IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 58),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          reverseDuration: const Duration(milliseconds: 120),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -.2),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: _notice == null
              ? const SizedBox.shrink(key: ValueKey('player-notice-empty'))
              : PlayerPanelSurface(
                  key: ValueKey(_notice),
                  palette: _palette,
                  radius: 16,
                  liveMaterial: true,
                  shadowRadius: 12,
                  shadowOffset: const Offset(0, 5),
                  child: SizedBox(
                    height: 32,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 7,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 15,
                          ),
                          Text(
                            _notice!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _palette.primary,
                              fontSize: 11.5,
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
    ),
  );

  Widget _volumeHudOverlay() => Align(
    alignment: Alignment.bottomCenter,
    child: IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 94),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          reverseDuration: const Duration(milliseconds: 180),
          child: _volumeHud == null
              ? const SizedBox.shrink(key: ValueKey('player-volume-hud-empty'))
              : Semantics(
                  key: const ValueKey('player-volume-hud'),
                  liveRegion: true,
                  label: '音量 ${_volumeHud!.round()}%',
                  child: PlayerPanelSurface(
                    palette: _palette,
                    radius: 18,
                    liveMaterial: true,
                    shadowRadius: 12,
                    shadowOffset: const Offset(0, 5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          Icon(
                            _volumeHud == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                            size: 18,
                            color: _palette.primary,
                          ),
                          SizedBox(
                            width: 128,
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _palette.trackBase,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: _volumeHud! / 100,
                                  heightFactor: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: _palette.trackProgress,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            '${_volumeHud!.round()}%',
                            style: TextStyle(
                              color: _palette.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
        unawaited(_changeVolume(5.5));
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        unawaited(_changeVolume(-5.5));
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        unawaited(_toggleMuteWithHud());
      },
      const SingleActivator(LogicalKeyboardKey.keyB): () =>
          unawaited(_cycleABLoop()),
      const SingleActivator(LogicalKeyboardKey.keyB, shift: true): () =>
          unawaited(_clearABLoop()),
      const SingleActivator(LogicalKeyboardKey.comma): () {
        _show();
        unawaited(session.stepFrame(backward: true));
      },
      const SingleActivator(LogicalKeyboardKey.period): () {
        _show();
        unawaited(session.stepFrame());
      },
      const SingleActivator(LogicalKeyboardKey.home): () {
        _show();
        unawaited(session.seek(Duration.zero));
      },
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          unawaited(_fullscreen ? _full() : requestClose()),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: Listenable.merge([session, session.timeline]),
          builder: (context, _) => MouseRegion(
            key: const ValueKey('player-interaction-region'),
            cursor: _shouldHideCursor
                ? SystemMouseCursors.none
                : SystemMouseCursors.basic,
            onEnter: (event) {
              _pointerActivityAnchor = event.localPosition;
              _show();
            },
            onHover: _handlePointerHover,
            onExit: (_) => _pointerActivityAnchor = null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0A1119),
                        Color(0xFF000000),
                        Color(0xFF050A11),
                      ],
                      stops: [0, .52, 1],
                    ),
                  ),
                ),
                if (session.engine != null) session.engine!.surface(),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _show,
                  onDoubleTap: () => unawaited(_full()),
                  onSecondaryTapDown: (details) =>
                      unawaited(_precisionMenu(details.globalPosition)),
                  child: const SizedBox.expand(),
                ),
                _edgeScrims(
                  visible:
                      _controls ||
                      !session.clock.playing ||
                      session.loading ||
                      session.error != null,
                ),
                if (session.loading) _loadingOverlay(),
                if (session.error != null) _errorOverlay(session.error!),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  opacity: _controls || session.loading || session.error != null
                      ? 1
                      : 0,
                  child: IgnorePointer(
                    ignoring:
                        !_controls && !session.loading && session.error == null,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 17, 18, 0),
                        child: _windowChrome(),
                      ),
                    ),
                  ),
                ),
                _noticeOverlay(),
                _volumeHudOverlay(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 98),
                    child: PlayerMarkerSkipPrompt(
                      session: session,
                      palette: _palette,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: ValueListenableBuilder<VideoClock>(
                      valueListenable: session.timeline,
                      builder: (context, value, _) =>
                          ValueListenableBuilder<PlaybackTimelineState>(
                            valueListenable: session.precision,
                            builder: (context, precision, _) => AnimatedOpacity(
                              duration: const Duration(milliseconds: 160),
                              opacity: _controls || !value.playing ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_controls && value.playing,
                                child: _bar(value, precision),
                              ),
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

  Widget _bar(VideoClock value, PlaybackTimelineState precision) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final leadingWidth = compact ? 176.0 : 200.0;
    final trailingWidth = compact ? 112.0 : 200.0;
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _palette.shadow,
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: .07),
                blurRadius: 1,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: CustomPaint(
            foregroundPainter: _PlayerGlassBorderPainter(
              start: _palette.border.first,
              end: _palette.border.last,
              radius: 14,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _palette.barFill,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
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
                      if (session.cacheWarning != null)
                        Text(
                          session.cacheWarning!,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                          ),
                        ),
                      if (session.controlError != null)
                        Text(
                          session.controlError!,
                          style: TextStyle(
                            color: _palette.secondary,
                            fontSize: 11,
                          ),
                        ),
                      if (session.transitionMessage != null)
                        Text(
                          session.transitionMessage!,
                          style: TextStyle(
                            color: _palette.secondary,
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
                              style: TextStyle(
                                color: _palette.secondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 6,
                                activeTrackColor: _palette.trackProgress,
                                inactiveTrackColor: _palette.trackBase,
                                thumbColor: _palette.primary,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                  elevation: 3,
                                  pressedElevation: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                overlayColor: _palette.choiceFill,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SliderOverlayScope(
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
                                                  Duration(
                                                    milliseconds: v.toInt(),
                                                  ),
                                                ),
                                              );
                                              _show();
                                            }
                                          : null,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: PlayerTimelineMarkers(
                                      duration: value.duration,
                                      state: precision,
                                      palette: _palette,
                                    ),
                                  ),
                                ],
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
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          AnimatedContainer(
                            key: const ValueKey('player-leading-actions'),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            width: leadingWidth,
                            child: Row(
                              children: [
                                if (session.qualityOptions.length > 1) ...[
                                  SizedBox(
                                    key: _qualityButton,
                                    width: compact ? 28 : 58,
                                    height: 28,
                                    child: PlayerControlSurface(
                                      palette: _palette,
                                      enabled: can,
                                      capsule: true,
                                      selected:
                                          _activePanel == PlayerPanel.quality,
                                      child: Tooltip(
                                        message: '画质',
                                        child: TextButton(
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            foregroundColor: _palette.primary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: can
                                              ? () => unawaited(
                                                  _panel(
                                                    PlayerPanel.quality,
                                                    _qualityButton,
                                                  ),
                                                )
                                              : null,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              PlayerSymbolIcon(
                                                PlayerSymbol.quality,
                                                color: _palette.primary,
                                                size: 12,
                                              ),
                                              if (!compact) ...[
                                                const SizedBox(width: 5),
                                                const Text(
                                                  '画质',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                ],
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
                                const SizedBox(width: 5),
                                _panelButton(
                                  '章节与播放标记',
                                  PlayerSymbol.bookmark,
                                  PlayerPanel.markers,
                                  _markerButton,
                                  can && precision.identity != null,
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
                          _icon(
                            '播放/暂停',
                            value.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            can ? () => unawaited(session.toggle()) : null,
                            width: 44,
                            color: _palette.primary,
                            emphasized: true,
                          ),
                          const SizedBox(width: 8),
                          _icon(
                            '下一集',
                            Icons.skip_next,
                            can ? () => unawaited(session.adjacent(1)) : null,
                            color: _palette.primary,
                          ),
                          const Spacer(),
                          AnimatedContainer(
                            key: const ValueKey('player-trailing-actions'),
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            width: trailingWidth,
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
        ),
      ),
    );
  }
}

class _PlayerGlassBorderPainter extends CustomPainter {
  const _PlayerGlassBorderPainter({
    required this.start,
    required this.end,
    required this.radius,
  });

  final Color start;
  final Color end;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const width = .9;
    final rect = (Offset.zero & size).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlayerGlassBorderPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.radius != radius;
}

String formatVideoTime(Duration duration) {
  final total = duration.inSeconds.clamp(0, 1 << 32);
  final seconds = (total % 60).toString().padLeft(2, '0');
  final minutes = ((total ~/ 60) % 60).toString().padLeft(2, '0');
  return total >= 3600
      ? '${total ~/ 3600}:$minutes:$seconds'
      : '${total ~/ 60}:$seconds';
}
