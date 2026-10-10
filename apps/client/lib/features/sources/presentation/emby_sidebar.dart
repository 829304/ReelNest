import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../application/emby_library_providers.dart';
import '../application/source_providers.dart';
import '../domain/emby_library.dart';

class EmbySidebar extends ConsumerStatefulWidget {
  const EmbySidebar({super.key});
  @override
  ConsumerState<EmbySidebar> createState() => _EmbySidebarState();
}

class _EmbySidebarState extends ConsumerState<EmbySidebar> {
  static const _key = 'library.collapsedEmbySources';
  Set<String> _collapsed = {};
  bool _ready = false;
  @override
  void initState() {
    super.initState();
    ref
        .read(embyLibraryRepositoryProvider)
        .preference(_key)
        .then((value) {
          if (mounted) {
            setState(() {
              _collapsed = value == null
                  ? {}
                  : (jsonDecode(value) as List).cast<String>().toSet();
              _ready = true;
            });
          }
        })
        .catchError((Object _) {
          if (mounted) setState(() => _ready = true);
        });
  }

  Future<void> _toggle(String id) async {
    final next = {..._collapsed};
    if (!next.remove(id)) next.add(id);
    try {
      await ref
          .read(embyLibraryRepositoryProvider)
          .savePreference(_key, jsonEncode(next.toList()));
      if (mounted) setState(() => _collapsed = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('侧栏状态保存失败，请重试。')));
      }
    }
  }

  Future<void> _rename(MediaSource source) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSourceDialog(name: source.name),
    );
    if (title == null || !mounted) return;
    try {
      await ref
          .read(sourceRepositoryProvider)
          .updateSettings(source.id, name: title);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(sourceErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    return sources.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const Padding(
        padding: EdgeInsets.all(10),
        child: Text('媒体源读取失败', style: TextStyle(fontSize: 12)),
      ),
      data: (values) => Column(
        children: [
          for (final source in values.where(
            (s) => s.kind == MediaSourceKind.emby,
          ))
            _group(source),
        ],
      ),
    );
  }

  Widget _group(MediaSource source) {
    final snapshot = ref.watch(embyVideoSnapshotProvider(source.id));
    final expanded = !_collapsed.contains(source.id);
    final rows =
        <({String label, IconData icon, EmbyVideoDestination destination})>[];
    final data = snapshot.asData?.value;
    if (data != null) {
      for (final section in EmbyVideoSection.values) {
        final destination = (
          sourceId: source.id,
          section: section,
          libraryId: null as String?,
        );
        if (data.scope(destination).isNotEmpty) {
          rows.add((
            label: section.label,
            icon: switch (section) {
              EmbyVideoSection.videos => Icons.live_tv,
              EmbyVideoSection.watchlist => Icons.bookmark_border,
              EmbyVideoSection.favorites => Icons.favorite_border,
            },
            destination: destination,
          ));
        }
      }
      for (final view in data.libraries) {
        rows.add((
          label: view.name,
          icon: Icons.video_library_outlined,
          destination: (
            sourceId: source.id,
            section: EmbyVideoSection.videos,
            libraryId: view.id,
          ),
        ));
      }
    }
    final uri = GoRouter.of(context).routerDelegate.currentConfiguration.uri;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          GestureDetector(
            onSecondaryTapDown: (details) async {
              final choice = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                ],
              );
              if (choice == 'rename' && mounted) await _rename(source);
            },
            child: TextButton(
              onPressed: _ready ? () => _toggle(source.id) : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, size: 22),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!expanded)
                    Text(
                      '${rows.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            if (snapshot.hasError)
              TextButton(
                onPressed: () =>
                    ref.invalidate(embyVideoSnapshotProvider(source.id)),
                child: const Text('库目录读取失败，重试'),
              ),
            for (final row in rows)
              _row(
                row.label,
                row.icon,
                row.destination,
                uri.path ==
                        Uri(pathSegments: ['', 'sources', source.id]).path &&
                    uri.queryParameters['library'] ==
                        row.destination.libraryId &&
                    (uri.queryParameters['section'] ?? 'videos') ==
                        row.destination.section.name,
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    IconData icon,
    EmbyVideoDestination destination,
    bool selected,
  ) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 22),
      child: Material(
        color: selected
            ? palette.selectedTint.withValues(alpha: .13)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go(embyVideoLocation(destination)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 22, color: palette.text),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: palette.text,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RenameSourceDialog extends StatefulWidget {
  const _RenameSourceDialog({required this.name});
  final String name;
  @override
  State<_RenameSourceDialog> createState() => _RenameSourceDialogState();
}

class _RenameSourceDialogState extends State<_RenameSourceDialog> {
  late final _controller = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('重命名'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('保存'),
      ),
    ],
  );
}
