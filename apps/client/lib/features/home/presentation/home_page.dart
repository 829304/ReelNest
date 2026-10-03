import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../ui/widgets/page_content.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
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
                  '你的媒体，从这里开始',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text('连接媒体服务器，将喜欢的电影、音乐与照片收藏在一起。'),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/servers'),
                  icon: const Icon(Icons.dns_outlined),
                  label: const Text('管理服务器'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
