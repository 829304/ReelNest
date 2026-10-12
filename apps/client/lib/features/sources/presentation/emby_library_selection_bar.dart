import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../ui/theme/source_sheet_palette.dart';

/// LibraryView's floating selection bar: 16px corners, 30px controls, 8px gaps.
class EmbyLibrarySelectionBar extends StatelessWidget {
  const EmbyLibrarySelectionBar({
    required this.count,
    required this.allSelected,
    required this.busy,
    required this.onSelectAll,
    required this.onWatched,
    required this.onWatchlist,
    required this.onRating,
    required this.onClearHistory,
    required this.onRemove,
    super.key,
  });
  final int count;
  final bool allSelected, busy;
  final VoidCallback onSelectAll, onWatchlist, onClearHistory, onRemove;
  final ValueChanged<bool> onWatched;
  final ValueChanged<double?> onRating;
  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final enabled = count > 0 && !busy;
    Widget button(String title, VoidCallback? action) => SizedBox(
      height: 30,
      child: TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          textStyle: const TextStyle(fontSize: 13),
          foregroundColor: palette.text,
          backgroundColor: palette.control,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Text(title),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.card.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border, width: 1.04),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                button(allSelected ? '取消全选' : '全选', busy ? null : onSelectAll),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text(
                    '已选 $count',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                button('已看', enabled ? () => onWatched(true) : null),
                button('未看', enabled ? () => onWatched(false) : null),
                button('想看', enabled ? onWatchlist : null),
                MenuAnchor(
                  menuChildren: [
                    for (var stars = 5; stars >= 1; stars--)
                      MenuItemButton(
                        onPressed: enabled
                            ? () => onRating(stars.toDouble())
                            : null,
                        child: Text('★' * stars),
                      ),
                    const Divider(),
                    MenuItemButton(
                      onPressed: enabled ? () => onRating(null) : null,
                      child: const Text('清除评级'),
                    ),
                  ],
                  builder: (_, controller, _) => button(
                    '评级',
                    enabled
                        ? () => controller.isOpen
                              ? controller.close()
                              : controller.open()
                        : null,
                  ),
                ),
                button('清除记录', enabled ? onClearHistory : null),
                button('移出库', enabled ? onRemove : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
