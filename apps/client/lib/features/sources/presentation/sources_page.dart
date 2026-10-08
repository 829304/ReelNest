import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/source_settings_draft.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/source_icons.dart';
import '../application/source_providers.dart';
import 'add_source_dialog.dart';
import 'source_page_sections.dart';
import 'source_settings_sheet.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});
  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage>
    with WidgetsBindingObserver {
  bool _busy = false;
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
      ref.invalidate(sourceReachabilityProvider);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final draft = await showDialog<SourceDraft>(
      context: context,
      builder: (_) =>
          AddSourceDialog(access: ref.read(directoryAccessProvider)),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      final scans = ref.read(sourceScansProvider.notifier);
      final result = await ref
          .read(sourceRepositoryProvider)
          .addFolders(locations: draft.locations, mediaType: draft.mediaType);
      if (result.added.isNotEmpty) {
        unawaited(scans.scanAll(result.added));
      }
      if (mounted && result.failures.isNotEmpty) {
        final private = draft.mediaType == SourceMediaType.privateCollection;
        final details = result.failures
            .map((failure) {
              final name = private ? '保险库目录' : p.basename(failure.location);
              return '$name：${sourceErrorMessage(failure.error)}';
            })
            .join('\n');
        setState(() {
          _error =
              '已添加 ${result.added.length} 个来源，'
              '${result.failures.length} 个目录添加失败。\n$details';
        });
      }
    });
  }

  Future<void> _relocate(MediaSource source) => _perform(() async {
    final location = await ref.read(directoryAccessProvider).choose();
    if (location == null || !mounted) return;
    // A full scan prunes absent index rows. Make the mapping explicit.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新定位来源'),
        content: Text(
          '请确认这是“${source.name}”原目录的新位置：\n$location\n\n会保留来源 ID 和已有索引，重新扫描后更新文件状态。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认位置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sourceRepositoryProvider).relocate(source.id, location);
    if (mounted) {
      unawaited(ref.read(sourceScansProvider.notifier).scan(source.id));
    }
  });

  Future<void> _settings(MediaSource source) async {
    final draft = await showDialog<SourceSettingsDraft>(
      context: context,
      builder: (_) => SourceSettingsSheet(source: source),
    );
    if (draft == null || !mounted) return;
    await _perform(() async {
      await ref
          .read(sourceScansProvider.notifier)
          .saveSettings(source.id, draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('媒体源设置已保存')));
    });
  }

  Future<void> _remove(MediaSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除媒体源？'),
        content: Text('移除“${source.name}”及其应用内索引，原目录和媒体文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(
        () => ref.read(sourceRepositoryProvider).remove(source.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final scans = ref.watch(sourceScansProvider);
    final reachable = ref.watch(sourceReachabilityProvider);
    final access = ref.watch(directoryAccessProvider);
    final isScanning = scans.values.any((scan) => scan.busy);
    final actionStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 41)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    return PageContent(
      title: '媒体源',
      subtitle: sourcesSubtitle,
      header: SourcesHeader(
        actions: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              key: const ValueKey('add-source'),
              style: actionStyle,
              onPressed: _busy || !access.supported ? null : _add,
              icon: const SourceLineIcon(
                SourceGlyph.plus,
                size: 15,
                lineWidth: 2.2,
              ),
              label: const Text('添加媒体源…'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('scan-all'),
              style: actionStyle,
              onPressed:
                  _busy || isScanning || (sources.asData?.value.isEmpty ?? true)
                  ? null
                  : () => ref
                        .read(sourceScansProvider.notifier)
                        .scanAll(sources.requireValue),
              icon: const SourceLineIcon(SourceGlyph.refresh, size: 15),
              label: const Text('扫描全部'),
            ),
          ],
        ),
      ),
      children: [
        if (!access.supported) Text(access.unavailableReason),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ...sources.when(
          loading: () => [const LinearProgressIndicator()],
          error: (error, stack) => [Text(sourceErrorMessage(error))],
          data: (items) {
            if (items.isEmpty) return [const _SourcesEmptyState()];
            return reachable.when(
              loading: () => [const LinearProgressIndicator()],
              error: (error, stack) => [Text(sourceErrorMessage(error))],
              data: (statuses) => [
                for (final connected in [true, false])
                  if (items.any(
                    (source) => statuses[source.id] == connected,
                  )) ...[
                    SourceSectionHeading(
                      connected: connected,
                      count: items
                          .where((source) => statuses[source.id] == connected)
                          .length,
                    ),
                    const SizedBox(height: 22),
                    for (final source in items.where(
                      (source) => statuses[source.id] == connected,
                    )) ...[
                      _sourceCard(
                        source,
                        scans[source.id] ?? const SourceScanState(),
                        connected: connected,
                        isScanning: isScanning,
                        canChoose: access.supported,
                      ),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 8),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }

  // This remains the transitional index card. The original compact SourceRow
  // and full original SourceRow layout still needs visual parity work.
  Widget _sourceCard(
    MediaSource source,
    SourceScanState scan, {
    required bool connected,
    required bool isScanning,
    required bool canChoose,
  }) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = connected
        ? Color(dark ? 0xFF45D67F : 0xFF1F9D57)
        : Color(dark ? 0xFFFFB84D : 0xFFD98A00);
    return Card(
      key: ValueKey('source-${source.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  source.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SourceLineIcon(
                          connected
                              ? SourceGlyph.checkCircle
                              : SourceGlyph.warning,
                          size: 11.5,
                          lineWidth: 1.9,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          connected ? '可访问' : '不可访问',
                          style: TextStyle(fontSize: 11, color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              source.location,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text('${source.kind.label} · ${source.itemCount} 项'),
            if (source.lastScan != null)
              Text(
                '上次完整扫描：${source.lastScan!.toLocal().toString().split('.').first}',
              ),
            if (scan.running) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: scan.progress.totalFiles > 0
                    ? scan.progress.fraction
                    : null,
              ),
              Text(
                '已处理 ${scan.progress.processedFiles}/${scan.progress.totalFiles} 个文件',
              ),
            ],
            if (scan.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(scan.message!),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => context.go('/sources/${source.id}'),
                  child: const Text('浏览媒体'),
                ),
                IconButton(
                  tooltip: '设置',
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  onPressed:
                      _busy ||
                          !source.kind.isFileSource ||
                          source.mediaType == SourceMediaType.privateCollection
                      ? null
                      : () => _settings(source),
                  icon: const SourceLineIcon(SourceGlyph.sliders, size: 20),
                ),
                OutlinedButton(
                  onPressed: scan.busy
                      ? () => ref
                            .read(sourceScansProvider.notifier)
                            .cancel(source.id)
                      : _busy || isScanning || !connected
                      ? null
                      : () => ref
                            .read(sourceScansProvider.notifier)
                            .scan(source.id),
                  child: Text(scan.busy ? '取消扫描' : '重新扫描'),
                ),
                TextButton(
                  onPressed: _busy || scan.busy || !canChoose
                      ? null
                      : () => _relocate(source),
                  child: const Text('重新定位'),
                ),
                TextButton(
                  onPressed: _busy || scan.busy ? null : () => _remove(source),
                  child: const Text('移除来源'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesEmptyState extends StatelessWidget {
  const _SourcesEmptyState();
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 320),
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 112,
            height: 104,
            child: Center(
              child: SourceLineIcon(
                SourceGlyph.drive,
                size: 46,
                lineWidth: 2.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '媒体源待添加',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Text(
              '接入本地文件夹、移动硬盘、网络挂载、ReelNest Server、Emby、Jellyfin 或 Plex 媒体库后，ReelNest 会整理索引。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
