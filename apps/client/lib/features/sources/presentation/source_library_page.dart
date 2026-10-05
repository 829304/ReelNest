import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media.dart';
import '../../../domain/media_source.dart';
import '../../../ui/widgets/page_content.dart';
import '../application/source_providers.dart';

class SourceLibraryPage extends ConsumerStatefulWidget {
  const SourceLibraryPage({required this.sourceId, super.key});
  final String sourceId;
  @override
  ConsumerState<SourceLibraryPage> createState() => _SourceLibraryPageState();
}

class _SourceLibraryPageState extends ConsumerState<SourceLibraryPage> {
  int _offset = 0;

  void _details(IndexedMedia item) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mediaTypes[item.type] ?? item.type),
            const SizedBox(height: 12),
            SelectableText(item.identity.localId),
            const SizedBox(height: 12),
            Text('${(item.bytes / 1024 / 1024).toStringAsFixed(2)} MiB'),
            Text('文件修改：${item.modified.toLocal().toString().split('.').first}'),
            const SizedBox(height: 12),
            Text(item.missing ? '上次完整扫描未找到此文件，索引仍保留。' : '此处显示上次扫描的索引信息。'),
            const SizedBox(height: 12),
            const Text('内置播放和元数据读取将在下一阶段接入。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final matches = sources.asData?.value
        .where((s) => s.id == widget.sourceId)
        .toList();
    final source = matches == null || matches.isEmpty ? null : matches.first;
    final items = ref.watch(
      sourceMediaProvider((sourceId: widget.sourceId, offset: _offset)),
    );
    return PageContent(
      title: source?.name ?? '媒体库',
      subtitle: '本机索引 · 无需服务器登录',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => context.go('/sources'),
            icon: const Icon(Icons.folder_outlined),
            label: const Text('管理媒体源'),
          ),
        ),
        const SizedBox(height: 16),
        if (sources.hasError)
          Text(sourceErrorMessage(sources.error!))
        else if (matches != null && matches.isEmpty)
          const Text('此媒体源已移除。')
        else
          ...items.when(
            loading: () => [const LinearProgressIndicator()],
            error: (error, stack) => [
              Text(sourceErrorMessage(error)),
              TextButton(
                onPressed: () => ref.invalidate(sourceMediaProvider),
                child: const Text('重试'),
              ),
            ],
            data: (page) => [
              Text(
                '共 ${page.total} 项${source?.lastScan == null ? ' · 尚未完成扫描' : ''}',
              ),
              const SizedBox(height: 12),
              if (page.items.isEmpty) const Text('没有可显示的媒体文件。请检查来源或重新扫描。'),
              for (final item in page.items)
                Card(
                  child: ListTile(
                    key: ValueKey(item.identity),
                    leading: Icon(
                      item.type == 'music'
                          ? Icons.music_note_outlined
                          : item.type == 'photo'
                          ? Icons.image_outlined
                          : Icons.movie_outlined,
                    ),
                    title: Text(item.title),
                    subtitle: Text(
                      '${mediaTypes[item.type]} · ${item.identity.localId}${item.missing ? ' · 待找回' : ''}',
                    ),
                    isThreeLine: false,
                    onTap: () => _details(item),
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: _offset == 0
                        ? null
                        : () => setState(
                            () => _offset = (_offset - 60).clamp(0, _offset),
                          ),
                    child: const Text('上一页'),
                  ),
                  OutlinedButton(
                    onPressed: _offset + 60 >= page.total
                        ? null
                        : () => setState(() => _offset += 60),
                    child: const Text('下一页'),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}
