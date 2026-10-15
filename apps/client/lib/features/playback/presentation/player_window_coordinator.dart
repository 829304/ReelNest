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
  static const minimumMiniWidth = 280.0;
  static const minimumMiniHeight = 168.0;
  static const preferredMiniWidth = 380.0;
  static const screenInset = 16.0;

  final PlayerWindowGateway gateway;
  PlayerWindowSnapshot? _restore;
  bool _busy = false;
  bool _preferredAlwaysOnTop = false;

  bool get miniMode => _restore != null;
  bool get busy => _busy;
  bool get preferredAlwaysOnTop => _preferredAlwaysOnTop;

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
      await gateway.setMinimumSize(normalMinimumSize);
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
      await gateway.setMinimumSize(normalMinimumSize);
      if (snapshot != null) {
        await gateway.setBounds(snapshot.bounds);
        if (snapshot.maximized) await gateway.maximize();
      }
      await gateway.setAlwaysOnTop(_preferredAlwaysOnTop);
    } catch (_) {
      // Preserve the original platform failure; recovery is best effort.
    }
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }
}
