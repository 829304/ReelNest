import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/widgets/page_content.dart';
import '../../servers/application/connection_controller.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionControllerProvider);
    final connection = state.connection;
    return PageContent(
      title: '首页',
      subtitle: '让喜欢的声音与影像，有处可栖。',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.video_library_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                Text(
                  connection?.server.name ?? '你的媒体，从这里开始',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  connection == null
                      ? '连接媒体服务器，将喜欢的电影、音乐与照片收藏在一起。'
                      : state.requiresLogin
                      ? '登录已过期，请到服务器页面重新登录。'
                      : state.pendingSave
                      ? '会话尚未保存，请到服务器页面重试。'
                      : '打开媒体库查看服务器提供的分类。',
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (connection != null &&
                        !state.requiresLogin &&
                        !state.pendingSave)
                      FilledButton.icon(
                        onPressed: () => context.go('/servers/library'),
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('打开媒体库'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/servers'),
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('管理服务器'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
