import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/status_notice.dart';
import '../../servers/application/connection_controller.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionControllerProvider);
    final controller = ref.read(connectionControllerProvider.notifier);
    final catalog = state.catalog;
    final signedIn = state.connection != null && !state.requiresLogin;
    final localizations = MaterialLocalizations.of(context);
    final fetchedAt = catalog?.fetchedAt.toLocal();
    return PageContent(
      title: '媒体库',
      subtitle: state.connection?.server.name ?? '连接服务器后读取媒体分类。',
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.go('/servers'),
              icon: const Icon(Icons.dns_outlined),
              label: const Text('管理服务器'),
            ),
            FilledButton.icon(
              onPressed: !signedIn || state.busy ? null : controller.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新媒体库'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (state.busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(state.activity ?? '正在读取…')),
          const SizedBox(height: 16),
        ],
        if (state.failure case final failure?) ...[
          StatusNotice(message: failure.message),
          const SizedBox(height: 16),
        ],
        if (!signedIn && !state.busy)
          const Text('请先在服务器页面登录。'),
        if (signedIn && catalog == null && !state.busy)
          const Text('尚未读取到分类，请刷新重试。'),
        if (catalog != null && fetchedAt != null) ...[
          Text(
            '最近读取：${localizations.formatMediumDate(fetchedAt)} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(fetchedAt))}',
          ),
          if (state.failure != null || state.busy) ...[
            const SizedBox(height: 8),
            const Text('以下为上次成功读取的分类。'),
          ],
          const SizedBox(height: 20),
          if (catalog.categories.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('服务器尚未提供媒体分类。请在服务端添加媒体来源后刷新。'),
              ),
            ),
          for (final category in catalog.categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                key: ValueKey(category.id),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text('${category.itemCount} 项'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text('当前显示分类与数量，媒体条目浏览将在后续版本接入。'),
        ],
      ],
    );
  }
}
