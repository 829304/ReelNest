import 'package:flutter/material.dart';

import 'destinations.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({
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
    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        destinations: [
          for (final destination in appDestinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
