import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../../sources/application/source_providers.dart';
import '../application/health_providers.dart';

/// LibraryHealthCenterView's local source / video metadata / missing file
/// sections. Other dashboard sections remain separate, unfinished ports.
class LibraryHealthPage extends ConsumerStatefulWidget {
  const LibraryHealthPage({super.key});
  @override
  ConsumerState<LibraryHealthPage> createState() => _LibraryHealthPageState();
}

class _LibraryHealthPageState extends ConsumerState<LibraryHealthPage>
    with WidgetsBindingObserver {
  bool _expanded = true;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(rawLibraryHealthProvider);
    }
  }

  Future<void> _ignore(HealthIssueKey key) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(healthRepositoryProvider).ignore(key);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已忽略健康项，可在设置中恢复显示。')));
      }
    } catch (_) {
      if (mounted) setState(() => _error = '健康项保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _open(IndexedMedia item) => context.pushNamed(
    'local-media-detail',
    pathParameters: {
      'sourceId': item.identity.sourceId,
      'mediaKey': base64Url.encode(utf8.encode(item.identity.localId)),
    },
  );
  Widget _action(String label, SourceGlyph glyph, VoidCallback? onPressed) =>
      Tooltip(
        message: label,
        child: SourceSheetButton(
          label: '',
          icon: SourceLineIcon(glyph, size: 13),
          height: 27,
          horizontalPadding: 8,
          onPressed: onPressed,
        ),
      );
  Widget _pill(String label, Color tint) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tint),
    ),
  );
  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(libraryHealthProvider);
    final scanning = ref.watch(
      sourceScansProvider.select((scans) => scans.values.any((s) => s.busy)),
    );
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return PageContent(
      title: '仪表盘',
      subtitle: '汇总片库健康、后台任务和需要处理的维护事项。',
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              SizedBox(
                width: 62,
                height: 68,
                child: Center(
                  child: SourceTitleIcon(kind: SourceTitleIconKind.dashboard),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '仪表盘',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '汇总片库健康、后台任务和需要处理的维护事项。',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SourceSheetButton(
                label: '扫描全部',
                icon: const SourceLineIcon(SourceGlyph.refresh, size: 15),
                onPressed:
                    scanning ||
                        health.asData?.value.inventory.sources.isNotEmpty !=
                            true
                    ? null
                    : () => ref
                          .read(sourceScansProvider.notifier)
                          .scanAll(health.requireValue.inventory.sources),
              ),
              SourceSheetButton(
                label: '重新检测',
                icon: const SourceLineIcon(SourceGlyph.refresh, size: 15),
                onPressed: () => ref.invalidate(rawLibraryHealthProvider),
              ),
            ],
          ),
        ],
      ),
      children: [
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ...health.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => [
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            const Text('正在检测片库健康…'),
          ],
          error: (_, _) => [const Text('片库健康检测失败，请重新检测。')],
          data: (snapshot) => _sections(snapshot, palette, scanning),
        ),
      ],
    );
  }

  List<Widget> _sections(
    LibraryHealthSnapshot snapshot,
    SourceSheetPalette palette,
    bool scanning,
  ) {
    final sources = snapshot.localSources;
    final missing = snapshot.missingItems;
    final gaps = snapshot.metadataGapItems;
    return [
      _heading('监测中心', '挂载源在线状态与元数据缺口集中管理，不再在下方重复列出。'),
      _HealthCard(
        title: '挂载源在线监测',
        status: snapshot.offline.isEmpty
            ? '全部在线'
            : '${snapshot.offline.length} 个离线',
        accent: const Color(0xFF0EA5E9),
        children: [
          if (sources.isEmpty)
            const Text('尚未添加媒体源，先到「媒体源」接入本地或网络媒体库。')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = ((constraints.maxWidth + 10) / 274)
                    .floor()
                    .clamp(1, 100);
                final width =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final source in sources)
                      SizedBox(
                        width: width,
                        child: _sourceRow(source, snapshot, palette, scanning),
                      ),
                  ],
                );
              },
            ),
          Divider(color: palette.border),
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.offline.isEmpty
                      ? '全部来源连通正常'
                      : '${snapshot.offline.length} 个来源需要重新挂载或检查',
                  style: TextStyle(fontSize: 11, color: palette.secondary),
                ),
              ),
              SourceSheetButton(
                label: '源配置',
                height: 27,
                horizontalPadding: 11,
                onPressed: () => context.go('/sources'),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 14),
      _HealthCard(
        title: '影视元数据监测',
        status: gaps.isEmpty ? '完整' : '${gaps.length} 项缺口',
        accent: const Color(0xFF6366F1),
        children: [
          Text(
            '缺少封面、年份或简介的会列在这里。',
            style: TextStyle(fontSize: 11, color: palette.secondary),
          ),
          if (gaps.isEmpty)
            const Text('影视元数据完整，无需补充。', style: TextStyle(fontSize: 11))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 164),
              child: ListView.separated(
                shrinkWrap: true,
                primary: false,
                itemCount: gaps.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (_, index) {
                  final item = gaps[index],
                      fields = snapshot.metadataGaps[item.identity]!;
                  return Tooltip(
                    message: '缺少：${fields.join('、')}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: palette.control.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.cardTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            fields.length == 1
                                ? '缺${fields.first}'
                                : '缺${fields.first}等 ${fields.length} 项',
                            style: TextStyle(
                              fontSize: 10,
                              color: palette.secondary,
                            ),
                          ),
                          _action('搜索并补充元数据尚未接入', SourceGlyph.search, null),
                          _action(
                            '永久忽略此检查结果，可在设置中恢复',
                            SourceGlyph.eyeOff,
                            _saving
                                ? null
                                : () => _ignore((
                                    kind: HealthIssueKind.missingMetadata,
                                    sourceId: item.identity.sourceId,
                                    localId: item.identity.localId,
                                  )),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      _heading('健康详情', '失效文件、失效链接、重复条目与影视详情资料集中处理。'),
      // Do not claim every original health category passed while they are absent.
      if (missing.isEmpty)
        const Text('未发现失效文件。', style: TextStyle(fontSize: 11))
      else
        _HealthCard(
          title: '失效文件/播放路径',
          status: '${missing.length} 项',
          accent: palette.accent,
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
          children: [
            Text(
              '本地文件不存在或远程视频没有可播放路径。确认失效后可仅从内部索引移除。',
              style: TextStyle(fontSize: 11, color: palette.secondary),
            ),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 430),
                child: ListView.separated(
                  shrinkWrap: true,
                  primary: false,
                  itemCount: missing.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: palette.border),
                  itemBuilder: (_, index) {
                    final item = missing[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.cardTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.identity.localId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SourceSheetButton(
                            label: '查看',
                            height: 30,
                            horizontalPadding: 9,
                            onPressed: () => _open(item),
                          ),
                          _action(
                            '永久忽略此检查结果，可在设置中恢复',
                            SourceGlyph.eyeOff,
                            _saving
                                ? null
                                : () => _ignore((
                                    kind: HealthIssueKind.missingFile,
                                    sourceId: item.identity.sourceId,
                                    localId: item.identity.localId,
                                  )),
                          ),
                          if (snapshot.safeMissing.contains(item.identity))
                            const Tooltip(
                              message: '索引清理尚未接入',
                              child: SourceSheetButton(
                                label: '移出索引',
                                height: 30,
                                horizontalPadding: 9,
                                onPressed: null,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
    ];
  }

  Widget _sourceRow(
    MediaSource source,
    LibraryHealthSnapshot snapshot,
    SourceSheetPalette palette,
    bool scanning,
  ) {
    final online = !snapshot.offline.contains(source.id);
    final hidden = source.mediaType == SourceMediaType.privateCollection;
    return Tooltip(
      message: hidden ? '路径已隐藏' : source.location,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: palette.control.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SourceLineIcon(SourceGlyph.drive, size: 14, color: palette.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hidden ? '保险库' : source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${source.itemCount} 个条目',
                    style: TextStyle(fontSize: 10, color: palette.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _pill(
              online ? '在线' : '离线',
              online ? const Color(0xFF34C759) : const Color(0xFFD98A00),
            ),
            if (!online) ...[
              _action(
                '扫描',
                SourceGlyph.refresh,
                scanning || hidden
                    ? null
                    : () => ref
                          .read(sourceScansProvider.notifier)
                          .scan(source.id),
              ),
              _action(
                '忽略',
                SourceGlyph.eyeOff,
                _saving
                    ? null
                    : () => _ignore((
                        kind: HealthIssueKind.offlineSource,
                        sourceId: source.id,
                        localId: '',
                      )),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.title,
    required this.status,
    required this.accent,
    required this.children,
    this.expanded,
    this.onToggle,
  });
  final String title, status;
  final Color accent;
  final List<Widget> children;
  final bool? expanded;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.staticSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: palette.dark ? .16 : .08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 16,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(status, style: TextStyle(fontSize: 10, color: accent)),
                  if (expanded != null) ...[
                    const SizedBox(width: 8),
                    RotatedBox(
                      quarterTurns: expanded! ? 0 : 1,
                      child: const SourceLineIcon(
                        SourceGlyph.chevronDown,
                        size: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          for (final child in children) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }
}
