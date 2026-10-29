import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

abstract interface class PlayerWindowGateway {
  Future<Rect> getBounds();
  Future<Rect> getVisibleScreenBounds(Rect windowBounds);
  Future<bool> isFullScreen();
  Future<bool> isMaximized();
  Future<void> unmaximize();
  Future<void> maximize();
  Future<void> setBounds(Rect bounds);
  Future<void> setMinimumSize(Size size);
  Future<void> setAspectRatio(double aspectRatio);
  Future<void> setAlwaysOnTop(bool enabled);
  Future<void> setVisibleOnAllWorkspaces(bool enabled);
  Future<void> focus();
}

class DesktopPlayerWindowGateway implements PlayerWindowGateway {
  const DesktopPlayerWindowGateway();

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<Rect> getVisibleScreenBounds(Rect windowBounds) async {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) {
      final primary = await screenRetriever.getPrimaryDisplay();
      return _visibleBounds(primary);
    }
    final center = windowBounds.center;
    final bounds = displays.map(_visibleBounds).toList(growable: false);
    return bounds.reduce((nearest, candidate) {
      if (candidate.contains(center)) return candidate;
      if (nearest.contains(center)) return nearest;
      return _distanceSquared(candidate, center) <
              _distanceSquared(nearest, center)
          ? candidate
          : nearest;
    });
  }

  static Rect _visibleBounds(Display display) =>
      (display.visiblePosition ?? Offset.zero) &
      (display.visibleSize ?? display.size);

  static double _distanceSquared(Rect bounds, Offset point) {
    final dx = point.dx < bounds.left
        ? bounds.left - point.dx
        : point.dx > bounds.right
        ? point.dx - bounds.right
        : 0.0;
    final dy = point.dy < bounds.top
        ? bounds.top - point.dy
        : point.dy > bounds.bottom
        ? point.dy - bounds.bottom
        : 0.0;
    return dx * dx + dy * dy;
  }

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> setBounds(Rect bounds) =>
      windowManager.setBounds(bounds, animate: false);

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> setAspectRatio(double aspectRatio) =>
      windowManager.setAspectRatio(aspectRatio);

  @override
  Future<void> setAlwaysOnTop(bool enabled) =>
      windowManager.setAlwaysOnTop(enabled);

  @override
  Future<void> setVisibleOnAllWorkspaces(bool enabled) => Platform.isMacOS
      ? windowManager.setVisibleOnAllWorkspaces(
          enabled,
          visibleOnFullScreen: enabled,
        )
      : Future.value();

  @override
  Future<void> focus() => windowManager.focus();
}

@immutable
class PlayerWindowSnapshot {
  const PlayerWindowSnapshot({required this.bounds, required this.maximized});

  final Rect bounds;
  final bool maximized;
}

/// Keeps mini-window platform mutations and the frame restoration contract in
/// one place. The page only reacts to [miniMode] and invokes these actions.
class PlayerWindowCoordinator extends ChangeNotifier {
  PlayerWindowCoordinator(this.gateway);

  static const normalMinimumSize = Size(680, 382);
  static const defaultPreferredWidth = 1120.0;
  static const portraitMinimumWidth = 360.0;
  static const portraitMinimumHeight = 560.0;
  static const normalScreenWidthInsetRatio = .985;
  static const normalScreenHeightRatio = .94;
  static const portraitScreenHeightRatio = .90;
  static const minimumMiniWidth = 280.0;
  static const minimumMiniHeight = 168.0;
  static const preferredMiniWidth = 380.0;
  static const screenInset = 16.0;

  final PlayerWindowGateway gateway;
  PlayerWindowSnapshot? _restore;
  bool _busy = false;
  bool _preferredAlwaysOnTop = false;
  double _normalAspect = 16 / 9;
  double _preferredWidth = defaultPreferredWidth;
  Size _normalMinimum = normalMinimumSize;
  bool _configured = false;
  bool _applyingNormalBounds = false;

  bool get miniMode => _restore != null;
  bool get busy => _busy;
  bool get preferredAlwaysOnTop => _preferredAlwaysOnTop;
  bool get configured => _configured;
  bool get applyingNormalBounds => _applyingNormalBounds;
  double get preferredWidth => _preferredWidth;
  double get normalAspect => _normalAspect;
  Size get currentNormalMinimumSize => _normalMinimum;

  static double safeAspect(double aspect) =>
      aspect.isFinite && aspect > 0 ? aspect : 16 / 9;

  /// Matches the original player presenter's content minimums. Landscape
  /// windows reserve the 680x382 control-safe area, while portrait media keeps
  /// a genuinely portrait minimum instead of being forced into a wide frame.
  static Size normalMinimumSizeForAspect(double aspect) {
    final safe = safeAspect(aspect);
    if (safe < 1) {
      return Size(
        portraitMinimumWidth,
        (portraitMinimumWidth / safe).clamp(
          portraitMinimumHeight,
          double.infinity,
        ),
      );
    }
    final width = (normalMinimumSize.height * safe).clamp(
      normalMinimumSize.width,
      double.infinity,
    );
    return Size(
      width,
      (width / safe).clamp(normalMinimumSize.height, double.infinity),
    );
  }

  /// Original launch geometry: landscape prefers the remembered width;
  /// portrait uses screen height because a remembered landscape width is not
  /// meaningful. Both stay inside the display's visible work area.
  static Size preferredNormalSize({
    required double aspect,
    required Rect visibleScreenBounds,
    double preferredWidth = defaultPreferredWidth,
  }) {
    final safe = safeAspect(aspect);
    final visible = visibleScreenBounds.size;
    Size target;
    if (safe < 1) {
      final height = visible.height * portraitScreenHeightRatio;
      target = Size(height * safe, height);
    } else {
      final width = preferredWidth
          .clamp(normalMinimumSize.width, visible.width)
          .toDouble();
      target = Size(width, width / safe);
    }
    final maxWidth = visible.width * normalScreenWidthInsetRatio;
    final maxHeight = visible.height * normalScreenHeightRatio;
    final scale = <double>[
      1,
      maxWidth / target.width,
      maxHeight / target.height,
    ].reduce((a, b) => a < b ? a : b);
    return Size(target.width * scale, target.height * scale);
  }

  static Rect centeredBounds(Size size, Rect visibleScreenBounds) {
    final left = (visibleScreenBounds.center.dx - size.width / 2).clamp(
      visibleScreenBounds.left,
      visibleScreenBounds.right - size.width,
    );
    final top = (visibleScreenBounds.center.dy - size.height / 2).clamp(
      visibleScreenBounds.top,
      visibleScreenBounds.bottom - size.height,
    );
    return Rect.fromLTWH(left, top, size.width, size.height);
  }

  Future<void> configureNormalWindow({
    required double aspect,
    double preferredWidth = defaultPreferredWidth,
  }) async {
    final bounds = await gateway.getBounds();
    final screen = await gateway.getVisibleScreenBounds(bounds);
    _preferredWidth = preferredWidth.isFinite
        ? preferredWidth.clamp(normalMinimumSize.width, double.infinity)
        : defaultPreferredWidth;
    await _applyNormalGeometry(aspect: aspect, screen: screen, resize: true);
    _configured = true;
  }

  Future<void> applyMediaAspect(double aspect) async {
    final safe = safeAspect(aspect);
    _normalAspect = safe;
    _normalMinimum = normalMinimumSizeForAspect(safe);
    if (miniMode) {
      await _applyMiniAspect(safe);
      return;
    }
    if (await gateway.isFullScreen() || await gateway.isMaximized()) return;
    final bounds = await gateway.getBounds();
    final screen = await gateway.getVisibleScreenBounds(bounds);
    await _applyNormalGeometry(aspect: safe, screen: screen, resize: true);
    _configured = true;
  }

  void rememberPreferredWidth(double width) {
    if (!width.isFinite || width < normalMinimumSize.width) return;
    _preferredWidth = width;
  }

  Future<void> _applyNormalGeometry({
    required double aspect,
    required Rect screen,
    required bool resize,
  }) async {
    final safe = safeAspect(aspect);
    _normalAspect = safe;
    _normalMinimum = normalMinimumSizeForAspect(safe);
    final size = preferredNormalSize(
      aspect: safe,
      visibleScreenBounds: screen,
      preferredWidth: _preferredWidth,
    );
    _applyingNormalBounds = true;
    try {
      await gateway.setMinimumSize(_normalMinimum);
      await gateway.setAspectRatio(safe);
      if (resize) await gateway.setBounds(centeredBounds(size, screen));
    } finally {
      _applyingNormalBounds = false;
    }
  }

  static Size minimumMiniSize(double aspect) {
    final safe = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
    final width = (minimumMiniHeight * safe).ceilToDouble().clamp(
      minimumMiniWidth,
      double.infinity,
    );
    return Size(width, (width / safe).ceilToDouble());
  }

  static Size preferredMiniSize(double aspect) {
    final safe = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
    final minimum = minimumMiniSize(safe);
    final width = preferredMiniWidth.clamp(minimum.width, double.infinity);
    return Size(width, (width / safe).roundToDouble());
  }

  Future<void> setPreferredAlwaysOnTop(bool enabled) async {
    if (_preferredAlwaysOnTop == enabled) return;
    final previous = _preferredAlwaysOnTop;
    _preferredAlwaysOnTop = enabled;
    try {
      if (!miniMode) await gateway.setAlwaysOnTop(enabled);
      notifyListeners();
    } catch (_) {
      _preferredAlwaysOnTop = previous;
      rethrow;
    }
  }

  Future<bool> enterMiniMode(double aspect) async {
    if (_busy || miniMode || await gateway.isFullScreen()) return false;
    _setBusy(true);
    PlayerWindowSnapshot? snapshot;
    try {
      final bounds = await gateway.getBounds();
      final maximized = await gateway.isMaximized();
      snapshot = PlayerWindowSnapshot(bounds: bounds, maximized: maximized);
      if (maximized) await gateway.unmaximize();

      final safeAspect = aspect.isFinite && aspect > 0 ? aspect : 16 / 9;
      final minimum = minimumMiniSize(safeAspect);
      final preferred = preferredMiniSize(safeAspect);
      final screen = await gateway.getVisibleScreenBounds(bounds);
      final target = Rect.fromLTWH(
        screen.right - preferred.width - screenInset,
        screen.bottom - preferred.height - screenInset,
        preferred.width,
        preferred.height,
      );
      await gateway.setMinimumSize(minimum);
      await gateway.setAspectRatio(safeAspect);
      await gateway.setAlwaysOnTop(true);
      await gateway.setVisibleOnAllWorkspaces(true);
      await gateway.setBounds(target);
      _restore = snapshot;
      await gateway.focus();
      notifyListeners();
      return true;
    } catch (_) {
      await _rollbackEnter(snapshot);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> exitMiniMode() async {
    final snapshot = _restore;
    if (_busy || snapshot == null) return false;
    _setBusy(true);
    try {
      await gateway.setVisibleOnAllWorkspaces(false);
      await gateway.setMinimumSize(_normalMinimum);
      await gateway.setAspectRatio(_normalAspect);
      await gateway.setBounds(snapshot.bounds);
      if (snapshot.maximized) await gateway.maximize();
      await gateway.setAlwaysOnTop(_preferredAlwaysOnTop);
      _restore = null;
      await gateway.focus();
      notifyListeners();
      return true;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _rollbackEnter(PlayerWindowSnapshot? snapshot) async {
    try {
      await gateway.setVisibleOnAllWorkspaces(false);
      await gateway.setMinimumSize(_normalMinimum);
      await gateway.setAspectRatio(_normalAspect);
      if (snapshot != null) {
        await gateway.setBounds(snapshot.bounds);
        if (snapshot.maximized) await gateway.maximize();
      }
      await gateway.setAlwaysOnTop(_preferredAlwaysOnTop);
    } catch (_) {
      // Preserve the original platform failure; recovery is best effort.
    }
  }

  Future<void> _applyMiniAspect(double aspect) async {
    final bounds = await gateway.getBounds();
    final minimum = minimumMiniSize(aspect);
    final width = bounds.width.clamp(minimum.width, double.infinity);
    final height = (width / aspect).roundToDouble();
    final target = Rect.fromLTWH(
      bounds.right - width,
      bounds.bottom - height,
      width,
      height,
    );
    await gateway.setMinimumSize(minimum);
    await gateway.setAspectRatio(aspect);
    await gateway.setBounds(target);
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
