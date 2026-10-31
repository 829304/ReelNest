import 'dart:async';

import 'package:flutter/widgets.dart';

/// Suppresses pointer hover effects while the nearest scrollable is moving.
///
/// MediaLib keeps hover disabled until scrolling has been quiet for roughly
/// 200 ms. The quiet period matters on desktop: enabling hover in the same
/// frame as [ScrollEndNotification] can briefly lift the poster still under a
/// stationary pointer and leave its overlay shadow behind while the grid
/// settles.
class ScrollHoverScope extends StatefulWidget {
  const ScrollHoverScope({required this.child, super.key});

  final Widget child;

  static bool suppressed(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ScrollHoverInherited>()
          ?.suppressed ??
      false;

  @override
  State<ScrollHoverScope> createState() => _ScrollHoverScopeState();
}

class _ScrollHoverScopeState extends State<ScrollHoverScope> {
  static const _quietPeriod = Duration(milliseconds: 200);

  Timer? _releaseTimer;
  bool _suppressed = false;

  bool _handle(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _releaseTimer?.cancel();
    if (!_suppressed) setState(() => _suppressed = true);
    _releaseTimer = Timer(_quietPeriod, () {
      if (mounted && _suppressed) setState(() => _suppressed = false);
    });
    return false;
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _handle,
        child: _ScrollHoverInherited(
          suppressed: _suppressed,
          child: widget.child,
        ),
      );
}

class _ScrollHoverInherited extends InheritedWidget {
  const _ScrollHoverInherited({required this.suppressed, required super.child});

  final bool suppressed;

  @override
  bool updateShouldNotify(_ScrollHoverInherited oldWidget) =>
      suppressed != oldWidget.suppressed;
}
