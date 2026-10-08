import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../application/source_providers.dart';
import 'local_media_artwork.dart';

class SourceLibraryPage extends ConsumerWidget {
  const SourceLibraryPage({required this.sourceId, super.key});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final source = sources.asData?.value
        .where((s) => s.id == sourceId)
        .firstOrNull;
    final firstPage = ref.watch(
      sourceMediaProvider((sourceId: sourceId, offset: 0)),
    );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source?.name ?? '媒体库',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (firstPage.asData case final data?)
                      Text('共 ${data.value.total} 项'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.go('/sources'),
                      child: const Text('管理媒体源'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (sources.hasError)
          _message(sourceErrorMessage(sources.error!))
        else if (sources.hasValue && source == null)
          _message('此媒体源已移除。')
        else if (source == null)
          const SliverToBoxAdapter(child: LinearProgressIndicator())
        else
          firstPage.when(
            loading: () =>
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
            error: (error, stack) => SliverToBoxAdapter(
              child: TextButton(
                onPressed: () => ref.invalidate(sourceMediaProvider),
                child: Text('${sourceErrorMessage(error)} 重试'),
              ),
            ),
            data: (page) => page.total == 0
                ? _message('没有可显示的媒体。请检查来源或重新扫描。')
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(32, 8, 32, 28),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        // PosterGridList: default minimum width 150; 20/30 column/row gap.
                        final columns =
                            ((constraints.crossAxisExtent + 20) / 170)
                                .floor()
                                .clamp(1, 100);
                        return SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 20,
                                mainAxisSpacing: 30,
                                childAspectRatio: 2 / 3,
                              ),
                          itemCount: page.total,
                          itemBuilder: (context, index) =>
                              _LibraryItemAtIndex(source: source, index: index),
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _message(String text) => SliverPadding(
    padding: const EdgeInsets.all(32),
    sliver: SliverToBoxAdapter(child: Text(text)),
  );
}

class _LibraryItemAtIndex extends ConsumerWidget {
  const _LibraryItemAtIndex({required this.source, required this.index});
  final MediaSource source;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (sourceId: source.id, offset: (index ~/ 60) * 60);
    return ref
        .watch(sourceMediaProvider(key))
        .when(
          loading: () => const Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (error, stack) => TextButton(
            onPressed: () => ref.invalidate(sourceMediaProvider(key)),
            child: const Text('重试'),
          ),
          data: (page) {
            final position = index % 60;
            if (position >= page.items.length) return const SizedBox.shrink();
            final item = page.items[position];
            return Align(
              alignment: Alignment.topCenter,
              child: AspectRatio(
                aspectRatio: item.type == 'music' ? 1 : 2 / 3,
                child: LocalMediaCard(
                  key: ValueKey(item.identity),
                  source: source,
                  item: item,
                  onOpen: () => context.pushNamed(
                    'local-media-detail',
                    pathParameters: {
                      'sourceId': source.id,
                      // Opaque token keeps slash-containing and Unicode file keys out
                      // of URL path parsing; source scope is still checked in SQL.
                      'mediaKey': base64Url
                          .encode(utf8.encode(item.identity.localId))
                          .replaceAll('=', ''),
                    },
                  ),
                ),
              ),
            );
          },
        );
  }
}
