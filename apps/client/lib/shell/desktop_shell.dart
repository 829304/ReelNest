import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/sources/presentation/emby_sidebar.dart';
import '../ui/theme/app_palette.dart';
import '../ui/theme/design_tokens.dart';
import '../ui/widgets/source_icons.dart';
import 'destinations.dart';
import 'sidebar_components.dart';

class DesktopShell extends StatefulWidget {
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
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  double _sidebarWidth = DesignTokens.sidebarIdealWidth;

  void _resizeSidebar(double delta) {
    setState(() {
      _sidebarWidth = (_sidebarWidth + delta)
          .clamp(DesignTokens.sidebarMinWidth, DesignTokens.sidebarMaxWidth)
          .toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final uri = GoRouterState.of(context).uri;
    return Scaffold(
      backgroundColor: palette.page,
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              key: const ValueKey('desktop-sidebar'),
              width: _sidebarWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.sidebarTop, palette.sidebarBottom],
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: AppSidebarHoverRegion(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                      children: [
                        const _BrandHeader(),
                        const AppSidebarSectionHeader('媒体库'),
                        AppSidebarRow(
                          key: const ValueKey('nav-首页'),
                          label: appDestinations[0].label,
                          leading: Icon(appDestinations[0].icon),
                          selected: widget.selectedIndex == 0,
                          onTap: () => widget.onSelected(0),
                        ),
                        const EmbySidebar(),
                        const AppSidebarSectionHeader('管理'),
                        for (
                          var index = 1;
                          index < appDestinations.length;
                          index++
                        )
                          AppSidebarRow(
                            key: ValueKey(
                              'nav-${appDestinations[index].label}',
                            ),
                            label: appDestinations[index].label,
                            leading: _destinationIcon(index),
                            selected:
                                widget.selectedIndex == index &&
                                (index != 1 || uri.path == '/sources'),
                            onTap: () => widget.onSelected(index),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                key: const ValueKey('desktop-sidebar-resizer'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    _resizeSidebar(details.delta.dx),
                child: SizedBox(
                  width: 5,
                  child: Center(
                    child: VerticalDivider(
                      width: 1,
                      thickness: .8,
                      color: palette.border,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(color: palette.page, child: widget.child),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destinationIcon(int index) => switch (appDestinations[index].label) {
    '仪表盘' => const SourceLineIcon(SourceGlyph.dashboard, size: 18),
    _ => Icon(appDestinations[index].icon),
  };
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 14),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Image.asset(
              'assets/branding/reelnest_logo.png',
              key: const ValueKey('reelnest-brand-logo'),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              semanticLabel: 'ReelNest',
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ReelNest',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.title,
                    fontSize: 16,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '家庭影音库',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.subtle,
                    fontSize: DesignTokens.caption,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
