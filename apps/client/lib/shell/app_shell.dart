import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'desktop_shell.dart';
import 'mobile_shell.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedIndex = navigationShell.currentIndex;
        void select(int index) => navigationShell.goBranch(index);
        // Desktop window constraints live in the native runners, as in the
        // original MainWindowToolbarVisibilityGuard. Width is not a platform.
        final desktop = switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux => true,
          _ => false,
        };
        return desktop
            ? DesktopShell(
                selectedIndex: selectedIndex,
                onSelected: select,
                child: navigationShell,
              )
            : MobileShell(
                selectedIndex: selectedIndex,
                onSelected: select,
                child: navigationShell,
              );
      },
    );
  }
}
