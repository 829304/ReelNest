import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/theme/design_tokens.dart';
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
        return constraints.maxWidth >= DesignTokens.desktopBreakpoint
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
