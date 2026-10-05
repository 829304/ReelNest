import 'package:flutter/material.dart';

import '../../../ui/theme/design_tokens.dart';
import '../../../ui/widgets/source_icons.dart';

const sourcesSubtitle =
    '管理本地文件夹、移动硬盘、网络挂载、ReelNest Server、Emby、Jellyfin 和 Plex 媒体库。';

/// SourcesView/PageHeader: 62-point icon slot, 8-point gap and bottom-aligned
/// actions. Typography and page spacing follow the original source constants.
class SourcesHeader extends StatelessWidget {
  const SourcesHeader({required this.actions, super.key});
  final Widget actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Row(
          children: [
            const SizedBox(
              width: 62,
              height: 68,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SourceTitleIcon(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '媒体源',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    sourcesSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        // The desktop runner enforces 1088x720. Keep the deferred mobile template
        // and large accessibility text usable without changing desktop navigation.
        if (constraints.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(13) > 19.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: title),
            const SizedBox(width: 20),
            actions,
          ],
        );
      },
    ),
  );
}

class SourceSectionHeading extends StatelessWidget {
  const SourceSectionHeading({
    required this.connected,
    required this.count,
    super.key,
  });
  final bool connected;
  final int count;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = connected
        ? DesignTokens.blue
        : Color(dark ? 0xFFFFB84D : 0xFFD98A00);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 46,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox.square(
            dimension: 54,
            child: OverflowBox(
              maxWidth: 56,
              maxHeight: 56,
              child: SourceTitleIcon(
                kind: connected
                    ? SourceTitleIconKind.connected
                    : SourceTitleIconKind.disconnected,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? '已连接媒体源' : '已断开媒体源',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  connected
                      ? '状态、参与策略和扫描操作集中在每个来源行中。'
                      : '这些来源暂时不可访问，可重新挂载、检查设置或稍后再扫描。',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(
                '$count个',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: tint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
