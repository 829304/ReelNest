import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../domain/media_source.dart';
import '../../../player/video_engine.dart';
import '../application/playback_session.dart';
import '../application/playback_timeline_controller.dart';
import 'player_precision_controls.dart';
import 'player_playback_info.dart';
import 'player_timeline_scrubber.dart';
import 'player_track_popovers.dart';
import 'player_visuals.dart';
import 'player_window_coordinator.dart';

String formatPlayerNetworkSpeed(int? bytesPerSecond) {
  if (bytesPerSecond == null) return '-- KB/s';
  final bytes = bytesPerSecond < 0 ? 0 : bytesPerSecond;
  if (bytes == 0) return '0 KB/s';
  const bytesPerKilobyte = 1024;
  const bytesPerMegabyte = 1024 * 1024;
  if (bytes < 10 * bytesPerKilobyte) {
    return '${(bytes / bytesPerKilobyte).toStringAsFixed(1)} KB/s';
  }
  if (bytes < bytesPerMegabyte) {
    return '${(bytes / bytesPerKilobyte).floor()} KB/s';
  }
  return '${(bytes / bytesPerMegabyte).toStringAsFixed(1)} MB/s';
}

bool shouldShowPlayerControlLayer({
  required bool miniMode,
  required bool loading,
  required bool hasError,
  required bool controlsLocked,
  required bool controlsVisible,
  required bool playing,
}) =>
    !miniMode &&
    !controlsLocked &&
    (controlsVisible || !playing || loading || hasError);

bool shouldShowPlayerNetworkSpeed({
  required bool miniMode,
  required bool remoteMedia,
  required bool localFile,
  required bool loading,
  required bool hasError,
  required bool controlsLocked,
  required bool controlsVisible,
  required bool playing,
}) =>
    remoteMedia &&
    !localFile &&
    shouldShowPlayerControlLayer(
      miniMode: miniMode,
      loading: loading,
      hasError: hasError,
      controlsLocked: controlsLocked,
      controlsVisible: controlsVisible,
      playing: playing,
    );

/// Desktop video canvas and primary controls.
///
/// The transport keeps the original command layout and panel behavior, while
/// the presentation uses a responsive dark dock so the controls stay legible
/// over video instead of inheriting the poster's light/dark surface palette.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    required this.identity,
    required this.session,
    required this.closeWindow,
    required this.setFullscreen,
    this.windowCoordinator,
    super.key,
  });
  final MediaIdentity identity;
  final PlaybackSession session;
  final Future<void> Function() closeWindow;
  final Future<void> Function(bool) setFullscreen;
  final PlayerWindowCoordinator? windowCoordinator;
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
  bool _controlsLocked = false;
  bool _showingPlaybackInfo = false;
  PlayerPanel? _activePanel;
  bool _maximized = false;
  Offset? _pointerActivityAnchor;
  final PlayerPalette _palette = const PlayerPalette(lightContent: true);
  final _subtitleButton = GlobalKey();
  final _audioButton = GlobalKey();
  final _volumeButton = GlobalKey();
  final _episodeButton = GlobalKey();
  final _settingsButton = GlobalKey();
  final _qualityButton = GlobalKey();
  final _markerButton = GlobalKey();
  PlaybackSession get session => widget.session;
  bool get _miniMode => widget.windowCoordinator?.miniMode ?? false;
  @override
  void initState() {
    super.initState();
    session.waitForSurface = _waitForSurface;
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
    if (_controlsLocked) return;
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted &&
          session.clock.playing &&
          !_hoverControls &&
          !_popoverActive &&
          !_showingPlaybackInfo &&
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
      !_miniMode &&
      !_controlsLocked &&
      !_popoverActive &&
      !_showingPlaybackInfo &&
      session.clock.playing &&
      !session.loading &&
      session.error == null;

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
        onOpenPlaybackInfo: _showPlaybackInfo,
      );
    } finally {
      _popoverActive = false;
      if (mounted) _show();
    }
  }

  void _toggleControlsLock() {
    _hideTimer?.cancel();
    setState(() {
      _controlsLocked = !_controlsLocked;
      _controls = !_controlsLocked;
    });
    if (!_controlsLocked) _show();
  }

  void _showPlaybackInfo() {
    if (session.item == null) return;
    _hideTimer?.cancel();
    setState(() {
      _showingPlaybackInfo = true;
      _controls = true;
    });
  }

  void _hidePlaybackInfo() {
    if (!_showingPlaybackInfo) return;
    setState(() => _showingPlaybackInfo = false);
    if (_controlsLocked) {
      setState(() => _controls = false);
    } else {
      _show();
    }
  }

  double get _videoAspectRatio {
    final engine = session.engine;
    if (engine case final VideoAspectEngine aspectEngine) {
      final decoded = aspectEngine.videoAspectRatio;
      if (decoded != null && decoded.isFinite && decoded > 0) return decoded;
    }
    final resolution = session.item?.remote?.resolution;
    if (resolution != null) {
      final match = RegExp(
        r'(\d{2,5})\s*[x×*]\s*(\d{2,5})',
        caseSensitive: false,
      ).firstMatch(resolution);
      final width = double.tryParse(match?.group(1) ?? '');
      final height = double.tryParse(match?.group(2) ?? '');
      if (width != null && height != null && width > 0 && height > 0) {
        return width / height;
      }
    }
    return 16 / 9;
  }

  Future<void> _toggleMiniMode() async {
    final coordinator = widget.windowCoordinator;
    if (coordinator == null || coordinator.busy) return;
    try {
      if (coordinator.miniMode) {
        await coordinator.exitMiniMode();
      } else {
        final entered = await coordinator.enterMiniMode(_videoAspectRatio);
        if (!entered) {
          _showNotice('请先退出全屏，再进入迷你悬浮窗');
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _controlsLocked = false;
        _showingPlaybackInfo = false;
        _controls = true;
      });
      _show();
    } catch (_) {
      if (mounted) _showNotice('无法切换迷你悬浮窗，请重试');
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
        width: 32,
        height: 32,
        child: _PlayerDockActionSurface(
          enabled: enabled,
          selected: _activePanel == panel,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: 16,
            onPressed: enabled ? () => unawaited(_panel(panel, key)) : null,
            icon: PlayerSymbolIcon(
              symbol,
              color: enabled
                  ? const Color(0xEBFFFFFF)
                  : const Color(0x61FFFFFF),
              size: 16,
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _full() async {
    if (_miniMode) {
      await _toggleMiniMode();
      return;
    }
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

  Widget _dockIcon(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool emphasized = false,
    Key? key,
  }) => Semantics(
    container: true,
    button: true,
    enabled: action != null,
    label: label,
    child: Tooltip(
      message: label,
      child: SizedBox(
        key: key,
        width: emphasized ? 34 : 32,
        height: emphasized ? 34 : 32,
        child: _PlayerDockActionSurface(
          enabled: action != null,
          emphasized: emphasized,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            splashRadius: emphasized ? 17 : 16,
            onPressed: action,
            icon: Icon(
              icon,
              size: emphasized ? 18 : 17,
              color: action == null
                  ? const Color(0x61FFFFFF)
                  : emphasized
                  ? const Color(0xE6101216)
                  : const Color(0xEBFFFFFF),
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

  bool _controlsLayerVisible(VideoClock value) => shouldShowPlayerControlLayer(
    miniMode: _miniMode,
    loading: session.loading,
    hasError: session.error != null,
    controlsLocked: _controlsLocked,
    controlsVisible: _controls,
    playing: value.playing,
  );

  bool _showNetworkSpeed(VideoClock value) => shouldShowPlayerNetworkSpeed(
    miniMode: _miniMode,
    remoteMedia: session.item?.remote != null,
    localFile: session.filePath != null,
    loading: session.loading,
    hasError: session.error != null,
    controlsLocked: _controlsLocked,
    controlsVisible: _controls,
    playing: value.playing,
  );

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

  Widget _loadingOverlay() => Center(
    child: IgnorePointer(
      child: Semantics(
        key: const ValueKey('player-loading-overlay'),
        liveRegion: true,
        label: '正在打开视频，正在准备播放画面',
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
                shadows: [
                  Shadow(
                    color: Color(0xD9000000),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            SizedBox(height: 5),
            Text(
              '正在准备播放画面…',
              style: TextStyle(
                color: Color(0xB8FFFFFF),
                fontSize: 11.5,
                shadows: [
                  Shadow(
                    color: Color(0xE6000000),
                    blurRadius: 10,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _errorOverlay(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Semantics(
        key: const ValueKey('player-error-overlay'),
        liveRegion: true,
        label: '内置播放器无法播放，$message',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_disabled_rounded,
                size: 42,
                color: Colors.white.withValues(alpha: .78),
                shadows: const [
                  Shadow(
                    color: Color(0xD9000000),
                    blurRadius: 14,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '内置播放器无法播放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Color(0xE6000000),
                      blurRadius: 12,
                      offset: Offset(0, 2),
                    ),
                  ],
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
                  shadows: const [
                    Shadow(
                      color: Color(0xE6000000),
                      blurRadius: 10,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => unawaited(
                  session.open(session.item?.identity ?? widget.identity),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(92, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: Colors.white.withValues(alpha: .17),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: .15),
                    width: .8,
                  ),
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

  Widget _controlsLockOverlay() => Align(
    alignment: Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.only(right: 16),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: _controls || _controlsLocked ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_controls && !_controlsLocked,
          child: Semantics(
            key: const ValueKey('player-controls-lock'),
            container: true,
            button: true,
            toggled: _controlsLocked,
            label: _controlsLocked ? '显示控制栏' : '锁定控制栏',
            child: Tooltip(
              message: _controlsLocked ? '显示控制栏' : '锁定控制栏',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .34),
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xC91C2026), Color(0xE80B0D11)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: SizedBox.square(
                        dimension: 36,
                        child: _PlayerDockActionSurface(
                          enabled: true,
                          emphasized: _controlsLocked,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            splashRadius: 18,
                            onPressed: _toggleControlsLock,
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: .76,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: Icon(
                                _controlsLocked
                                    ? Icons.lock_rounded
                                    : Icons.lock_open_rounded,
                                key: ValueKey(_controlsLocked),
                                size: 19,
                                color: _controlsLocked
                                    ? const Color(0xE6101216)
                                    : const Color(0xEBFFFFFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _miniModeOverlay(VideoClock value) {
    final visible = _controls || !value.playing;
    return AnimatedOpacity(
      key: const ValueKey('player-mini-mode-controls'),
      duration: const Duration(milliseconds: 160),
      opacity: visible ? 1 : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PlayerPanelSurface(
              palette: _palette,
              radius: 18,
              shadowRadius: 14,
              shadowOffset: const Offset(0, 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    _icon(
                      value.playing ? '暂停' : '播放',
                      value.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      () => unawaited(session.toggle()),
                      width: 34,
                      emphasized: true,
                    ),
                    _icon(
                      '还原窗口',
                      Icons.open_in_full_rounded,
                      () => unawaited(_toggleMiniMode()),
                      width: 32,
                    ),
                    _icon(
                      '关闭播放器',
                      Icons.close_rounded,
                      () => unawaited(requestClose()),
                      width: 32,
                      danger: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
      const SingleActivator(LogicalKeyboardKey.keyP): () =>
          unawaited(_toggleMiniMode()),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        unawaited(_changeVolume(5.5));
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        unawaited(_changeVolume(-5.5));
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        unawaited(_toggleMuteWithHud());
      },
      const SingleActivator(LogicalKeyboardKey.keyI): () {
        if (_showingPlaybackInfo) {
          _hidePlaybackInfo();
        } else {
          _showPlaybackInfo();
        }
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
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (_showingPlaybackInfo) {
          _hidePlaybackInfo();
        } else if (_miniMode) {
          unawaited(_toggleMiniMode());
        } else {
          unawaited(_fullscreen ? _full() : requestClose());
        }
      },
    },
    child: TooltipTheme(
      key: const ValueKey('player-tooltip-theme'),
      data: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 350),
        showDuration: Duration(milliseconds: 1600),
        preferBelow: false,
        verticalOffset: 10,
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        textStyle: TextStyle(
          color: Color(0xF2FFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        decoration: BoxDecoration(
          color: Color(0xF21A1D22),
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border: Border.fromBorderSide(BorderSide(color: Color(0x29FFFFFF))),
          boxShadow: [
            BoxShadow(
              color: Color(0x52000000),
              blurRadius: 12,
              spreadRadius: -3,
              offset: Offset(0, 5),
            ),
          ],
        ),
      ),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: AnimatedBuilder(
            animation: Listenable.merge([
              session,
              if (widget.windowCoordinator != null) widget.windowCoordinator!,
            ]),
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
                  if (_miniMode)
                    DragToMoveArea(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _show,
                        onDoubleTap: () => unawaited(_toggleMiniMode()),
                        onSecondaryTapDown: (details) =>
                            unawaited(_precisionMenu(details.globalPosition)),
                        child: const SizedBox.expand(),
                      ),
                    )
                  else
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
                        !_miniMode &&
                        !_controlsLocked &&
                        (_controls ||
                            !session.clock.playing ||
                            session.loading ||
                            session.error != null),
                  ),
                  if (session.loading) _loadingOverlay(),
                  if (session.error != null) _errorOverlay(session.error!),
                  if (!_miniMode)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      opacity:
                          _controls || session.loading || session.error != null
                          ? 1
                          : 0,
                      child: IgnorePointer(
                        ignoring:
                            !_controls &&
                            !session.loading &&
                            session.error == null,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 17, 18, 0),
                            child: _windowChrome(),
                          ),
                        ),
                      ),
                    ),
                  ValueListenableBuilder<VideoClock>(
                    valueListenable: session.timeline,
                    builder: (context, value, _) => PlayerNetworkSpeedHud(
                      visible: _showNetworkSpeed(value),
                      bytesPerSecond: session.loading || session.error != null
                          ? null
                          : value.networkBytesPerSecond,
                    ),
                  ),
                  _noticeOverlay(),
                  _volumeHudOverlay(),
                  if (!_miniMode) _controlsLockOverlay(),
                  if (!_miniMode)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 114),
                        child: PlayerMarkerSkipPrompt(
                          session: session,
                          palette: _palette,
                        ),
                      ),
                    ),
                  if (!_miniMode)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: ValueListenableBuilder<VideoClock>(
                          valueListenable: session.timeline,
                          builder: (context, value, _) =>
                              ValueListenableBuilder<PlaybackTimelineState>(
                                valueListenable: session.precision,
                                builder: (context, precision, _) =>
                                    AnimatedOpacity(
                                      key: const ValueKey(
                                        'player-controls-layer',
                                      ),
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      opacity: _controlsLayerVisible(value)
                                          ? 1
                                          : 0,
                                      child: IgnorePointer(
                                        ignoring: !_controlsLayerVisible(value),
                                        child: _bar(value, precision),
                                      ),
                                    ),
                              ),
                        ),
                      ),
                    ),
                  if (_miniMode)
                    ValueListenableBuilder<VideoClock>(
                      valueListenable: session.timeline,
                      builder: (context, value, _) => _miniModeOverlay(value),
                    ),
                  if (!_miniMode &&
                      _showingPlaybackInfo &&
                      session.item != null)
                    PlayerPlaybackInfoOverlay(
                      session: session,
                      palette: _palette,
                      onDismiss: _hidePlaybackInfo,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bar(VideoClock value, PlaybackTimelineState precision) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final leadingWidth = compact ? 180.0 : 216.0;
    final trailingWidth = widget.windowCoordinator == null ? 106.0 : 143.0;
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
        key: const ValueKey('player-control-dock'),
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .44),
                blurRadius: 24,
                spreadRadius: -7,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: .22),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CustomPaint(
            foregroundPainter: _PlayerGlassBorderPainter(
              start: Colors.white.withValues(alpha: .22),
              end: Colors.white.withValues(alpha: .055),
              radius: 16,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xD91D2026), Color(0xED0C0E12)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
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
                            color: Colors.white.withValues(alpha: .70),
                            fontSize: 11,
                          ),
                        ),
                      if (session.transitionMessage != null)
                        Text(
                          session.transitionMessage!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .70),
                            fontSize: 11,
                          ),
                        ),
                      SizedBox(
                        height: 24,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 42,
                              child: Text(
                                formatVideoTime(
                                  Duration(milliseconds: position.toInt()),
                                ),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .64),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
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
                                  trackHeight: 3,
                                  activeTrackColor: const Color(0xEBFFFFFF),
                                  inactiveTrackColor: Colors.white.withValues(
                                    alpha: .17,
                                  ),
                                  thumbColor: Colors.white,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 4,
                                    elevation: 1,
                                    pressedElevation: 3,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  overlayColor: Colors.white.withValues(
                                    alpha: .12,
                                  ),
                                ),
                                child: PlayerTimelineScrubber(
                                  duration: value.duration,
                                  position: position,
                                  enabled: can,
                                  mode:
                                      session.options.videoScrubberPreviewMode,
                                  palette: _palette,
                                  previewLoader:
                                      (
                                        time, {
                                        required coarse,
                                        required prefetch,
                                        required cancellation,
                                      }) async => (await session.requestPreview(
                                        time: time,
                                        duration: value.duration,
                                        coarse: coarse,
                                        cancellation: cancellation,
                                        prefetch: prefetch,
                                      ))?.bytes,
                                  onChangeStart: (v) {
                                    _show();
                                    setState(() => _scrub = v);
                                  },
                                  onChanged: (v) => setState(() => _scrub = v),
                                  onChangeEnd: (v) {
                                    setState(() => _scrub = null);
                                    unawaited(
                                      session.seek(
                                        Duration(milliseconds: v.toInt()),
                                      ),
                                    );
                                    _show();
                                  },
                                  overlay: PlayerTimelineMarkers(
                                    duration: value.duration,
                                    state: precision,
                                    palette: const PlayerPalette(
                                      lightContent: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            SizedBox(
                              width: 50,
                              child: Tooltip(
                                message: '点击切换剩余 / 总时长',
                                child: TextButton(
                                  key: const ValueKey(
                                    'player-timeline-trailing-time',
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(50, 24),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    foregroundColor: Colors.white.withValues(
                                      alpha: .64,
                                    ),
                                  ),
                                  onPressed: can
                                      ? () => unawaited(
                                          session.changeOptions(
                                            (options) => options.copyWith(
                                              showRemainingTime:
                                                  !options.showRemainingTime,
                                            ),
                                          ),
                                        )
                                      : null,
                                  child: Text(
                                    session.options.showRemainingTime
                                        ? '-${formatVideoTime(Duration(milliseconds: (duration - position).clamp(0, duration).round()))}'
                                        : formatVideoTime(value.duration),
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: .64,
                                      ),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 34,
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedContainer(
                                key: const ValueKey('player-leading-actions'),
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                width: leadingWidth,
                                child: Row(
                                  children: [
                                    if (session.qualityOptions.length > 1) ...[
                                      SizedBox(
                                        key: _qualityButton,
                                        width: compact ? 32 : 60,
                                        height: 32,
                                        child: _PlayerDockActionSurface(
                                          enabled: can,
                                          selected:
                                              _activePanel ==
                                              PlayerPanel.quality,
                                          child: Tooltip(
                                            message: '画质',
                                            child: TextButton(
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                foregroundColor:
                                                    _palette.primary,
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
                                                    color: const Color(
                                                      0xEBFFFFFF,
                                                    ),
                                                    size: 15,
                                                  ),
                                                  if (!compact) ...[
                                                    const SizedBox(width: 5),
                                                    const Text(
                                                      '画质',
                                                      style: TextStyle(
                                                        fontSize: 10.5,
                                                        color: Color(
                                                          0xEBFFFFFF,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w600,
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
                            ),
                            Align(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _dockIcon(
                                    '上一集',
                                    Icons.skip_previous,
                                    can
                                        ? () => unawaited(session.adjacent(-1))
                                        : null,
                                  ),
                                  const SizedBox(width: 7),
                                  _dockIcon(
                                    '播放/暂停',
                                    value.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    can
                                        ? () => unawaited(session.toggle())
                                        : null,
                                    emphasized: true,
                                  ),
                                  const SizedBox(width: 7),
                                  _dockIcon(
                                    '下一集',
                                    Icons.skip_next,
                                    can
                                        ? () => unawaited(session.adjacent(1))
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: AnimatedContainer(
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
                                    if (widget.windowCoordinator != null) ...[
                                      _dockIcon(
                                        '迷你悬浮窗',
                                        Icons.picture_in_picture_alt_rounded,
                                        () => unawaited(_toggleMiniMode()),
                                        key: const ValueKey(
                                          'player-mini-mode-dock',
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                    ],
                                    _dockIcon(
                                      _fullscreen ? '退出全屏' : '全屏',
                                      _fullscreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      () => unawaited(_full()),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}

class PlayerNetworkSpeedHud extends StatelessWidget {
  const PlayerNetworkSpeedHud({
    required this.visible,
    required this.bytesPerSecond,
    super.key,
  });

  final bool visible;
  final int? bytesPerSecond;

  @override
  Widget build(BuildContext context) {
    final label = formatPlayerNetworkSpeed(bytesPerSecond);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 64, right: 18),
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            reverseDuration: const Duration(milliseconds: 120),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -.14),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: visible
                ? Semantics(
                    key: const ValueKey('player-network-speed-hud'),
                    liveRegion: true,
                    label: '当前下载速度 $label',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          size: 15,
                          color: Color(0xD9FFFFFF),
                          shadows: [
                            Shadow(
                              color: Color(0xE6000000),
                              blurRadius: 9,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        Text(
                          label,
                          key: const ValueKey('player-network-speed-label'),
                          style: const TextStyle(
                            color: Color(0xD9FFFFFF),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                            shadows: [
                              Shadow(
                                color: Color(0xF0000000),
                                blurRadius: 9,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey('player-network-speed-hidden'),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PlayerDockActionSurface extends StatefulWidget {
  const _PlayerDockActionSurface({
    required this.enabled,
    required this.child,
    this.selected = false,
    this.emphasized = false,
  });

  final bool enabled;
  final bool selected;
  final bool emphasized;
  final Widget child;

  @override
  State<_PlayerDockActionSurface> createState() =>
      _PlayerDockActionSurfaceState();
}

class _PlayerDockActionSurfaceState extends State<_PlayerDockActionSurface> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (_hovered || _focused || _pressed);
    final background = widget.emphasized
        ? Color.lerp(const Color(0xEBFFFFFF), Colors.white, active ? 1 : 0)!
        : widget.selected
        ? Colors.white.withValues(alpha: .18)
        : active
        ? Colors.white.withValues(alpha: _pressed ? .16 : .11)
        : Colors.transparent;
    final border = widget.emphasized
        ? Colors.white.withValues(alpha: active ? .62 : .32)
        : widget.selected
        ? Colors.white.withValues(alpha: .28)
        : _focused
        ? Colors.white.withValues(alpha: .24)
        : Colors.transparent;
    final scale = _pressed
        ? .94
        : widget.emphasized && _hovered
        ? 1.045
        : _hovered
        ? 1.025
        : 1.0;
    final radius = BorderRadius.circular(999);
    return Focus(
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
      },
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: widget.enabled ? (_) => setState(() => _hovered = true) : null,
        onExit: widget.enabled
            ? (_) => setState(() {
                _hovered = false;
                _pressed = false;
              })
            : null,
        child: Listener(
          onPointerDown: widget.enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onPointerUp: widget.enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          onPointerCancel: widget.enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: widget.enabled ? 1 : .48,
              duration: const Duration(milliseconds: 140),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: radius,
                  border: Border.all(color: border, width: 1),
                  boxShadow: widget.emphasized
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .30),
                            blurRadius: active ? 12 : 8,
                            spreadRadius: -2,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : widget.selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .14),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : const [],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Material(
                    color: Colors.transparent,
                    child: widget.child,
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
