import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../application/emby_library_providers.dart';
import '../application/source_providers.dart';
import '../application/emby_providers.dart';
import '../domain/emby_library.dart';
import 'source_alias_dialog.dart';

class EmbySidebar extends ConsumerStatefulWidget {
  const EmbySidebar({super.key});
  @override
  ConsumerState<EmbySidebar> createState() => _EmbySidebarState();
}

class _EmbySidebarState extends ConsumerState<EmbySidebar> {
  static const _key = 'library.collapsedEmbySources';
  Set<String> _collapsed = {};
  Set<String> _savedCollapsed = {};
  bool _ready = false;
  Future<void> _pendingSave = Future.value();
  int _toggleRevision = 0;
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
              _savedCollapsed = {..._collapsed};
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
    final revision = ++_toggleRevision;
    setState(() => _collapsed = next);
    final repository = ref.read(embyLibraryRepositoryProvider);
    // Apply the interaction now; serialize persistence so rapid toggles cannot
    // leave an older value on disk after a newer one.
    final save = _pendingSave.then((_) async {
      await repository.savePreference(_key, jsonEncode(next.toList()));
      _savedCollapsed = next;
    });
    _pendingSave = save.catchError((Object _) {});
    try {
      await save;
    } catch (_) {
      if (mounted) {
        if (revision == _toggleRevision) {
          setState(() => _collapsed = {..._savedCollapsed});
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('侧栏状态保存失败，请重试。')));
      }
    }
  }

  Future<void> _rename(MediaSource source) async {
    await showSourceAliasDialog(
      context,
      source: source,
      repository: ref.read(sourceRepositoryProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sidebarSourcesProvider);
    return sources.when(
      skipLoadingOnReload: true,
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
    final catalog = ref.watch(embyBrowseCatalogProvider(source.id));
    final sections = ref.watch(embySidebarSectionsProvider(source.id));
    final expanded = !_collapsed.contains(source.id);
    final rows =
        <({String label, IconData icon, EmbyVideoDestination destination})>[];
    final selected = source.options.selectedEmbyLibraryIDs;
    final libraries =
        (catalog.value ?? [])
            .where(
              (view) =>
                  (selected.isEmpty || selected.contains(view.id)) &&
                  view.collectionType?.toLowerCase() != 'music' &&
                  view.collectionType?.toLowerCase() != 'photos',
            )
            .toList()
          ..sort((a, b) => libraryTitleCompare(a.name, b.name));
    {
      for (final section in EmbyVideoSection.values) {
        final destination = (
          sourceId: source.id,
          section: section,
          libraryId: null as String?,
        );
        if ((sections.value?.contains(section) ?? false) ||
            (section == EmbyVideoSection.videos && libraries.isNotEmpty)) {
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
      for (final view in libraries) {
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
                  Image.asset(
                    'assets/brands/emby.png',
                    key: ValueKey('emby-source-logo-${source.id}'),
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
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
                  if (!expanded && catalog.hasValue && sections.hasValue)
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
            if (sections.hasError || catalog.hasError)
              TextButton(
                onPressed: () {
                  ref.invalidate(embyBrowseCatalogProvider(source.id));
                  ref.invalidate(embySidebarSectionsProvider(source.id));
                },
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
