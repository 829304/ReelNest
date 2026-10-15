import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/features/playback/presentation/player_window_coordinator.dart';

void main() {
  test('mini sizing preserves aspect and original minimums', () {
    expect(
      PlayerWindowCoordinator.preferredMiniSize(16 / 9),
      const Size(380, 214),
    );
    expect(PlayerWindowCoordinator.minimumMiniSize(1), const Size(280, 280));
    expect(
      PlayerWindowCoordinator.minimumMiniSize(21 / 9),
      const Size(392, 168),
    );
  });

  test(
    'enter docks bottom-right and exit restores frame and preference',
    () async {
      final gateway = _FakeGateway();
      final coordinator = PlayerWindowCoordinator(gateway);
      await coordinator.setPreferredAlwaysOnTop(false);

      expect(await coordinator.enterMiniMode(16 / 9), isTrue);
      expect(coordinator.miniMode, isTrue);
      expect(gateway.minimumSize, const Size(299, 169));
      expect(gateway.bounds, const Rect.fromLTWH(1524, 850, 380, 214));
      expect(gateway.alwaysOnTop, isTrue);
      expect(gateway.visibleOnAllWorkspaces, isTrue);

      expect(await coordinator.exitMiniMode(), isTrue);
      expect(coordinator.miniMode, isFalse);
      expect(gateway.minimumSize, PlayerWindowCoordinator.normalMinimumSize);
      expect(gateway.bounds, gateway.initialBounds);
      expect(gateway.alwaysOnTop, isFalse);
      expect(gateway.visibleOnAllWorkspaces, isFalse);
      expect(gateway.focusCount, 2);
    },
  );

  test(
    'maximized window is restored and fullscreen rejects mini mode',
    () async {
      final gateway = _FakeGateway()..maximized = true;
      final coordinator = PlayerWindowCoordinator(gateway);
      expect(await coordinator.enterMiniMode(16 / 9), isTrue);
      expect(gateway.unmaximizeCount, 1);
      expect(await coordinator.exitMiniMode(), isTrue);
      expect(gateway.maximizeCount, 1);

      gateway.fullScreen = true;
      expect(await coordinator.enterMiniMode(16 / 9), isFalse);
      expect(coordinator.miniMode, isFalse);
    },
  );

  test('always-on-top preference remains forced while mini', () async {
    final gateway = _FakeGateway();
    final coordinator = PlayerWindowCoordinator(gateway);
    await coordinator.enterMiniMode(16 / 9);
    await coordinator.setPreferredAlwaysOnTop(true);
    expect(gateway.alwaysOnTop, isTrue);
    await coordinator.exitMiniMode();
    expect(gateway.alwaysOnTop, isTrue);
  });
}

class _FakeGateway implements PlayerWindowGateway {
  final initialBounds = const Rect.fromLTWH(120, 90, 960, 540);
  Rect bounds = const Rect.fromLTWH(120, 90, 960, 540);
  Rect visibleBounds = const Rect.fromLTWH(0, 0, 1920, 1080);
  Size minimumSize = PlayerWindowCoordinator.normalMinimumSize;
  bool fullScreen = false;
  bool maximized = false;
  bool alwaysOnTop = false;
  bool visibleOnAllWorkspaces = false;
  int unmaximizeCount = 0;
  int maximizeCount = 0;
  int focusCount = 0;

  @override
  Future<Rect> getBounds() async => bounds;

  @override
  Future<Rect> getVisibleScreenBounds(Rect windowBounds) async => visibleBounds;

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> unmaximize() async {
    maximized = false;
    unmaximizeCount++;
  }

  @override
  Future<void> maximize() async {
    maximized = true;
    maximizeCount++;
  }

  @override
  Future<void> setBounds(Rect value) async => bounds = value;

  @override
  Future<void> setMinimumSize(Size value) async => minimumSize = value;

  @override
  Future<void> setAlwaysOnTop(bool enabled) async => alwaysOnTop = enabled;

  @override
  Future<void> setVisibleOnAllWorkspaces(bool enabled) async =>
      visibleOnAllWorkspaces = enabled;

  @override
  Future<void> focus() async => focusCount++;
}
