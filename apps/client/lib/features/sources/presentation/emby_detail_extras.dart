import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../api/emby/emby_detail.dart';
import '../../../domain/media_source.dart';
import '../../../platform/external_links.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../application/emby_providers.dart';
import '../data/emby_detail_repository.dart';
import 'local_media_artwork.dart';

void openIndexedDetail(BuildContext context, MediaIdentity id) =>
    _pushIndexedDetail(GoRouter.of(context), id);

void _pushIndexedDetail(GoRouter router, MediaIdentity id) => router.pushNamed(
  'local-media-detail',
  pathParameters: {
    'sourceId': id.sourceId,
    'mediaKey': base64Url.encode(utf8.encode(id.localId)).replaceAll('=', ''),
  },
);

/// MediaTMDBExtrasView: a collapsible section, crew then cast then artwork.
/// Fixed person/artwork strip dimensions keep the episode list from jumping.
class EmbyDetailExtras extends ConsumerStatefulWidget {
  const EmbyDetailExtras({
    required this.source,
    required this.item,
    required this.snapshot,
    required this.onRefresh,
    super.key,
  });
  final MediaSource source;
  final IndexedMedia item;
  final EmbyDetailSnapshot snapshot;
  final VoidCallback onRefresh;
  @override
  ConsumerState<EmbyDetailExtras> createState() => _EmbyDetailExtrasState();
}

class _EmbyDetailExtrasState extends ConsumerState<EmbyDetailExtras> {
  bool _expanded = true;
  @override
  Widget build(BuildContext context) {
    final detail = widget.snapshot.detail;
    final revision = widget.snapshot.fetchedAt.millisecondsSinceEpoch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 16,
              ),
              const SizedBox(width: 10),
              const Text(
                '详情',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
            ],
          ),
        ),
        if (widget.snapshot.refreshError != null)
          Row(
            children: [
              Expanded(child: Text(widget.snapshot.refreshError!)),
              TextButton(onPressed: widget.onRefresh, child: const Text('重试')),
            ],
          ),
        if (_expanded) ...[
          if (detail.crew.isNotEmpty)
            _people('主创', Icons.person, detail.crew, revision),
          if (detail.cast.isNotEmpty)
            _people('演员', Icons.people_outline, detail.cast, revision),
          if (detail.backdropCount > 0 || detail.hasPoster)
            _section(
              context,
              '艺术照',
              Icons.photo_library_outlined,
              SizedBox(
                height: detail.hasPoster ? 164 : 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  itemCount: detail.backdropCount + (detail.hasPoster ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final backdrop = index < detail.backdropCount;
                    return Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: backdrop ? 220 : 104,
                        height: backdrop ? 220 / 1.78 : 156,
                        child: Tooltip(
                          message: backdrop ? '查看艺术照' : '查看海报',
                          child: GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              useSafeArea: false,
                              builder: (_) => EmbyArtworkViewer(
                                source: widget.source,
                                title: widget.item.title,
                                detail: detail,
                                initialIndex: index,
                                revision: revision,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: EmbyDetailImage(
                                sourceId: widget.source.id,
                                itemId: detail.itemId,
                                backdrop: backdrop,
                                index: backdrop ? index : 0,
                                width: 500,
                                revision: revision,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          _section(
            context,
            '相关链接',
            Icons.link,
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: detailLinks(widget.item.title, detail).entries
                  .map(
                    (entry) => TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(externalLinkOpenerProvider)(
                            entry.value,
                          );
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('无法打开浏览器，请重试。')),
                            );
                          }
                        }
                      },
                      child: Text(entry.key),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _people(
    String title,
    IconData icon,
    List<EmbyPerson> values,
    int revision,
  ) => _section(
    context,
    title,
    icon,
    SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final person = values[index];
          return SizedBox(
            width: 88,
            child: Tooltip(
              message: '查看${person.name}的资料和库中作品',
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EmbyPersonPage(
                      source: widget.source,
                      person: person,
                      revision: revision,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 72,
                        child: person.imageId == null
                            ? const ColoredBox(
                                color: Color(0xffe7ebf0),
                                child: Icon(
                                  Icons.person,
                                  color: Color(0xff708094),
                                ),
                              )
                            : EmbyDetailImage(
                                sourceId: widget.source.id,
                                itemId: person.imageId!,
                                width: 185,
                                revision: revision,
                                person: true,
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      person.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      person.role,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

Widget _section(
  BuildContext context,
  String title,
  IconData icon,
  Widget child,
) {
  final palette = SourceSheetPalette(
    Theme.of(context).brightness == Brightness.dark,
  );
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ),
  );
}

Map<String, Uri> detailLinks(String title, EmbyDetail detail) => {
  '豆瓣': Uri.https('search.douban.com', '/movie/subject_search', {
    'search_text': title,
  }),
  if (detail.imdbId != null)
    'IMDb': Uri.https('www.imdb.com', '/title/${detail.imdbId}/'),
  if (detail.tmdbId != null)
    'TMDB': Uri.https(
      'www.themoviedb.org',
      '/${detail.tmdbKind}/${detail.tmdbId}',
    ),
  '维基百科': Uri.https('zh.wikipedia.org', '/w/index.php', {'search': title}),
};

class EmbyDetailImage extends ConsumerWidget {
  const EmbyDetailImage({
    required this.sourceId,
    required this.itemId,
    required this.width,
    required this.revision,
    this.backdrop = false,
    this.index = 0,
    this.person = false,
    this.fit = BoxFit.cover,
    super.key,
  });
  final String sourceId, itemId;
  final int width, revision, index;
  final bool backdrop, person;
  final BoxFit fit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(person ? Icons.person : Icons.photo_outlined)),
    );
    return ref
        .watch(
          embyDetailImageProvider((
            sourceId: sourceId,
            itemId: itemId,
            backdrop: backdrop,
            index: index,
            width: width,
            revision: revision,
          )),
        )
        .when(
          loading: () => placeholder,
          error: (_, _) => placeholder,
          data: (bytes) => Image(
            image: ResizeImage(
              MemoryImage(bytes),
              width: width,
              height: backdrop ? (width / 1.78).ceil() : width * 3 ~/ 2,
              policy: ResizeImagePolicy.fit,
            ),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
  }
}

/// MediaImageViewer's top bar, image area and bottom strip. Remote resources
/// are fetched by identity with live authentication, not Image.network URLs.
class EmbyArtworkViewer extends StatefulWidget {
  const EmbyArtworkViewer({
    required this.source,
    required this.title,
    required this.detail,
    required this.initialIndex,
    required this.revision,
    super.key,
  });
  final MediaSource source;
  final String title;
  final EmbyDetail detail;
  final int initialIndex, revision;
  @override
  State<EmbyArtworkViewer> createState() => _EmbyArtworkViewerState();
}

class _EmbyArtworkViewerState extends State<EmbyArtworkViewer> {
  late int _index = widget.initialIndex;
  bool _info = false;
  final _transform = TransformationController();
  int get count =>
      widget.detail.backdropCount + (widget.detail.hasPoster ? 1 : 0);
  void _select(int value) {
    setState(() {
      _index = value.clamp(0, count - 1);
      _transform.value = Matrix4.identity();
    });
  }

  Widget _image(int index, int width) => EmbyDetailImage(
    sourceId: widget.source.id,
    itemId: widget.detail.itemId,
    backdrop: index < widget.detail.backdropCount,
    index: index < widget.detail.backdropCount ? index : 0,
    width: width,
    revision: widget.revision,
    fit: BoxFit.contain,
  );
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: const Color(0xee101722),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _select(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _select(_index + 1),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${_index + 1} / $count',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    tooltip: '上一张',
                    onPressed: _index == 0 ? null : () => _select(_index - 1),
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: '下一张',
                    onPressed: _index == count - 1
                        ? null
                        : () => _select(_index + 1),
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: '信息',
                    onPressed: () => setState(() => _info = !_info),
                    icon: const Icon(Icons.info_outline, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: '关闭图片',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (_info)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${widget.title} · ${_index < widget.detail.backdropCount ? '剧照' : '海报'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            Expanded(
              child: GestureDetector(
                onDoubleTap: () => setState(() {
                  _transform.value = _transform.value.getMaxScaleOnAxis() > 1
                      ? Matrix4.identity()
                      : Matrix4.diagonal3Values(2, 2, 1);
                }),
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 8,
                  child: _image(_index, 1280),
                ),
              ),
            ),
            if (count > 1)
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(width: 4),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: () => _select(index),
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _index == index
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _image(index, 185),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class EmbyPersonPage extends ConsumerWidget {
  const EmbyPersonPage({
    required this.source,
    required this.person,
    required this.revision,
    super.key,
  });
  final MediaSource source;
  final EmbyPerson person;
  final int revision;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        children: [
          Row(
            children: [
              const Text(
                '人物',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (person.imageId != null)
                SizedBox(
                  width: 160,
                  height: 240,
                  child: EmbyDetailImage(
                    sourceId: source.id,
                    itemId: person.imageId!,
                    width: 500,
                    revision: revision,
                  ),
                ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(person.role),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            '库中作品',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<IndexedMedia>>(
            future: ref
                .watch(embyDetailRepositoryProvider)
                .personWorks(source.id, person.key),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Text('人物作品读取失败，请返回后重试。');
              if (!snapshot.hasData) return const Text('正在整理库中作品…');
              final works = snapshot.data!;
              if (works.isEmpty) return const Text('暂无已缓存的库中作品。');
              return SizedBox(
                height: 234,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: works.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) => SizedBox(
                    width: 112,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 168,
                          child: LocalMediaCard(
                            source: source,
                            item: works[index],
                            onOpen: () {
                              final router = GoRouter.of(context);
                              Navigator.of(context).pop();
                              _pushIndexedDetail(router, works[index].identity);
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          works[index].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}
