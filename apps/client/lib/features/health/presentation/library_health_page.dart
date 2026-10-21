import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/library_health.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_confirmation_dialog.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/dashboard_surfaces.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../../sources/application/source_providers.dart';
import '../application/health_providers.dart';
import '../../../app/runtime_observations.dart';
import 'health_overview.dart';
import '../../sources/presentation/emby_task_center.dart';

/// LibraryHealthCenterView's video scores, source/file checks and metadata /
/// duplicate candidates. Music, URL connectors and metadata repair are separate.
class LibraryHealthPage extends ConsumerStatefulWidget {
  const LibraryHealthPage({super.key});
  @override
  ConsumerState<LibraryHealthPage> createState() => _LibraryHealthPageState();
}

class _LibraryHealthPageState extends ConsumerState<LibraryHealthPage>
    with WidgetsBindingObserver {
  bool _expanded = true;
  bool _saving = false;
  bool _cleaning = false;
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
        showAppToast(
          context,
          '已忽略健康项，可在设置中恢复显示。',
          kind: AppFeedbackKind.success,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '健康项保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeMissing(
    LibraryHealthSnapshot snapshot,
    List<IndexedMedia> items,
  ) async {
    if (_cleaning || items.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmationDialog(
        title: items.length == 1
            ? '确认从索引移除“${items.single.title}”？'
            : '确认从索引移除 ${items.length} 个失效条目？',
        message: '仅移除 ReelNest 内部索引，不会修改媒体文件；离线来源中的条目会保留。',
        confirmLabel: '仅从 ReelNest 索引移除',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted || _cleaning) return;
    setState(() {
      _cleaning = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(missingIndexCleanupProvider)
          .remove(snapshot, items.map((item) => item.identity).toSet());
      ref.invalidate(rawLibraryHealthProvider);
      if (mounted) {
        showAppToast(
          context,
          result.removed == 0
              ? '没有可清理条目。离线、已恢复或状态不明的条目已保留。'
              : '索引已清理：已移除 ${result.removed} 个失效条目，保留 ${result.retained} 个条目。媒体文件没有被修改。',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _cleaning = false);
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
  Widget _pill(String label, Color tint) =>
      DashboardStatusBadge(label: label, tint: tint);
  Widget _heading(
    String title,
    String subtitle, {
    IconData? icon,
    String? badge,
  }) => DashboardSectionHeading(
    title: title,
    subtitle: subtitle,
    icon: icon,
    badge: badge,
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
      header: DashboardPageHeader(
        title: '仪表盘',
        subtitle: '汇总片库健康、后台任务和需要处理的维护事项。',
        icon: const SourceTitleIcon(kind: SourceTitleIconKind.dashboard),
        actions: [
          SourceSheetButton(
            label: '扫描全部',
            icon: const SourceLineIcon(SourceGlyph.refresh, size: 15),
            onPressed:
                scanning ||
                    _cleaning ||
                    health.asData?.value.inventory.sources.isNotEmpty != true
                ? null
                : () => ref
                      .read(sourceScansProvider.notifier)
                      .scanAll(health.requireValue.inventory.sources),
          ),
          if (health.asData?.value.safeMissing.isNotEmpty == true)
            SourceSheetButton(
              label: '清理失效索引',
              outlined: true,
              onPressed: scanning || _cleaning
                  ? null
                  : () {
                      final snapshot = health.requireValue;
                      _removeMissing(
                        snapshot,
                        snapshot.missingItems
                            .where(
                              (item) =>
                                  snapshot.safeMissing.contains(item.identity),
                            )
                            .toList(),
                      );
                    },
            ),
          SourceSheetButton(
            label: '任务中心',
            onPressed: () => context.go('/health/tasks'),
          ),
          SourceSheetButton(
            label: '重新检测',
            icon: const SourceLineIcon(SourceGlyph.refresh, size: 15),
            prominent: true,
            onPressed: () => ref.invalidate(rawLibraryHealthProvider),
          ),
        ],
      ),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppInlineNotice(
              message: _error!,
              kind: AppFeedbackKind.error,
            ),
          ),
        ...health.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const [
            DashboardPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 13),
                  Text('正在读取媒体库状态…'),
                ],
              ),
            ),
          ],
          error: (error, _) => [
            AppInlineNotice(
              message: sourceErrorMessage(error),
              kind: AppFeedbackKind.error,
              actionLabel: '重新检测',
              onAction: () => ref.invalidate(rawLibraryHealthProvider),
            ),
          ],
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
    if (snapshot.inventory.sources.isEmpty) {
      return [
        DashboardEmptyState(
          title: snapshot.configurationSources.isEmpty
              ? '尚未添加媒体源'
              : '没有可检测的视频媒体源',
          message: snapshot.configurationSources.isEmpty
              ? '添加媒体源后，可在这里查看片库健康状态。'
              : '当前没有参与视频检测的媒体源；音乐后续单独实现，照片已移出当前范围。',
          icon: Icons.monitor_heart_outlined,
          action: Column(
            children: [
              DashboardStatusBadge(
                label: snapshot.configurationSources.isEmpty
                    ? '暂无媒体库'
                    : '视频检测范围为空',
                tint: const Color(0xFF0EA5E9),
              ),
              const SizedBox(height: 12),
              SourceSheetButton(
                label: '管理媒体源',
                prominent: true,
                onPressed: () => context.go('/sources'),
              ),
            ],
          ),
        ),
      ];
    }
    final sources = snapshot.localSources;
    final missing = snapshot.missingItems;
    final gaps = snapshot.metadataGapItems;
    return [
      if (snapshot.evaluationComplete) ...[
        HealthOverview(
          snapshot: snapshot,
          tasks: ref.watch(observedTasksProvider),
        ),
        if (snapshot.partialIndex)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: AppInlineNotice(
              message: '当前检测仅覆盖已载入的媒体；完整同步后可重新检测。',
              kind: AppFeedbackKind.warning,
            ),
          ),
      ],
      const EmbyCacheDashboard(),
      _heading(
        '监测中心',
        '挂载源在线状态与元数据缺口集中管理，不再在下方重复列出。',
        icon: Icons.monitor_heart_outlined,
        badge: snapshot.offline.isEmpty && gaps.isEmpty
            ? '状态良好'
            : '${snapshot.offline.length + gaps.length} 项待处理',
      ),
      _HealthCard(
        title: '挂载源在线监测',
        status: snapshot.offline.isEmpty
            ? '全部在线'
            : '${snapshot.offline.length} 个离线',
        accent: const Color(0xFF0EA5E9),
        children: [
          if (sources.isEmpty)
            const Text('没有需要检测挂载路径的本地来源；远程视频资料检查显示在下方。')
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
      _heading(
        '健康详情',
        '失效文件、失效链接、重复条目与影视详情资料集中处理。',
        icon: Icons.fact_check_outlined,
        badge:
            '${missing.length + snapshot.duplicates.length + snapshot.detailGapItems.length + snapshot.unhealthyURLs.length} 项',
      ),
      if (missing.isEmpty)
        const AppInlineNotice(message: '未发现失效文件。')
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
                            SourceSheetButton(
                              label: '移出索引',
                              height: 30,
                              horizontalPadding: 9,
                              onPressed: scanning || _cleaning
                                  ? null
                                  : () => _removeMissing(snapshot, [item]),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ..._advancedSections(snapshot, palette),
    ];
  }

  List<Widget> _advancedSections(
    LibraryHealthSnapshot snapshot,
    SourceSheetPalette palette,
  ) {
    final details = snapshot.detailGapItems;
    final rows = snapshot.duplicateRows;
    return [
      if (rows.isNotEmpty) ...[
        const SizedBox(height: 14),
        _HealthCard(
          title: '疑似重复条目',
          status: '${snapshot.duplicates.length} 组',
          accent: palette.accent,
          children: [
            const Text(
              '按标题、类型和年份列出候选项，需要手动核对。',
              style: TextStyle(fontSize: 11),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: ListView.builder(
                shrinkWrap: true,
                primary: false,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return row.header
                      ? Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${row.item.title} · ${row.group.length} 项',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _action(
                              '忽略此重复组，可在设置中恢复',
                              SourceGlyph.eyeOff,
                              _saving
                                  ? null
                                  : () => _ignore(duplicateIssueKey(row.group)),
                            ),
                          ],
                        )
                      : _healthItemRow(
                          row.item,
                          '${row.item.displayType} · ${row.item.year ?? '未知年份'} · ${row.item.identity.localId}',
                        );
                },
              ),
            ),
          ],
        ),
      ],
      if (details.isNotEmpty) ...[
        const SizedBox(height: 14),
        _HealthCard(
          title: '影视详情资料不完整',
          status: '${details.length} 项',
          accent: palette.accent,
          children: [
            const Text(
              '区分缺少人物、艺术照、外部 ID 或推荐；查看详情核对已有资料。',
              style: TextStyle(fontSize: 11),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 430),
              child: ListView.builder(
                shrinkWrap: true,
                primary: false,
                itemCount: details.length,
                itemBuilder: (_, index) {
                  final item = details[index];
                  final id = item.identity;
                  return _healthItemRow(
                    item,
                    '缺少${snapshot.detailGaps[id]!.join('、')}',
                    issue: (
                      kind: HealthIssueKind.detailMetadata,
                      sourceId: id.sourceId,
                      localId: id.localId,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
      if (snapshot.evaluationComplete &&
          snapshot.missing.isEmpty &&
          rows.isEmpty &&
          details.isEmpty &&
          snapshot.unhealthyURLs.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Text('未发现其他待处理项。', style: TextStyle(fontSize: 11)),
        ),
    ];
  }

  Widget _healthItemRow(
    IndexedMedia item,
    String description, {
    HealthIssueKey? issue,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Tooltip(
            message: description,
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
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        SourceSheetButton(
          label: '查看详情',
          height: 30,
          horizontalPadding: 9,
          onPressed: () => _open(item),
        ),
        if (issue != null)
          _action(
            '忽略此详情资料检查，可在设置中恢复',
            SourceGlyph.eyeOff,
            _saving ? null : () => _ignore(issue),
          ),
      ],
    ),
  );

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
    return DashboardPanel(
      radius: 20,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(10),
              splashFactory: NoSplash.splashFactory,
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
                  DashboardStatusBadge(label: status, tint: accent),
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
