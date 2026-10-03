import 'package:flutter/material.dart';

import '../../../ui/widgets/page_content.dart';

class ServersPage extends StatelessWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageContent(
      title: '服务器',
      subtitle: '管理你的媒体来源。',
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.dns_outlined, size: 36),
                SizedBox(height: 20),
                Text('还没有服务器'),
                SizedBox(height: 8),
                Text('服务器连接即将开放。'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
