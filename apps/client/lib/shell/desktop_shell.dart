import 'package:flutter/material.dart';

import '../ui/theme/design_tokens.dart';
import '../ui/widgets/source_icons.dart';
import 'destinations.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: DesignTokens.sidebarWidth,
              child: Material(
                color: theme.colorScheme.surfaceContainerLow,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 0, 8, 28),
                      child: Row(
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 38,
                            color: DesignTokens.blue,
                          ),
                          SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ReelNest',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '映栖 · 家庭影音库',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (var index = 0; index < appDestinations.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Ink(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.controlRadius,
                            ),
                            gradient: selectedIndex == index
                                ? LinearGradient(
                                    colors: [
                                      DesignTokens.blue.withValues(
                                        alpha: dark ? 0.22 : 0.14,
                                      ),
                                      DesignTokens.pink.withValues(
                                        alpha: dark ? 0.16 : 0.10,
                                      ),
                                    ],
                                  )
                                : null,
                            border: selectedIndex == index
                                ? Border.all(
                                    color: DesignTokens.blue.withValues(
                                      alpha: dark ? 0.28 : 0.18,
                                    ),
                                    width: 0.8,
                                  )
                                : null,
                          ),
                          child: ListTile(
                            key: ValueKey(
                              'nav-${appDestinations[index].label}',
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                DesignTokens.controlRadius,
                              ),
                            ),
                            leading: appDestinations[index].label == '仪表盘'
                                ? const SourceLineIcon(
                                    SourceGlyph.dashboard,
                                    size: 24,
                                  )
                                : Icon(appDestinations[index].icon),
                            title: Text(appDestinations[index].label),
                            selected: selectedIndex == index,
                            onTap: () => onSelected(index),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
