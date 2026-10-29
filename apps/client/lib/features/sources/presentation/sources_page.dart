import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../domain/source_scan.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/source_settings_draft.dart';
import '../../../domain/source_options.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/page_content.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/source_providers.dart';
import 'add_source_dialog.dart';
import 'emby_sheets.dart';
import '../application/emby_providers.dart';
import '../application/url_video_providers.dart';
import 'media_server_brand_mark.dart';
import 'source_page_sections.dart';
import 'source_settings_sheet.dart';
import 'source_alias_dialog.dart';
import 'source_confirmation_dialog.dart';
import 'url_source_sheet.dart';

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
    while (true) {
      if (!mounted) return;
      final kind = await showDialog<MediaSourceKind>(
        context: context,
        builder: (_) => const SourceKindSheet(),
      );
      if (kind == null || !mounted) return;
      if (kind == MediaSourceKind.url) {
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const UrlSourceAddSheet(),
        );
        if (mounted) {
          ref.invalidate(sourcesProvider);
          ref.invalidate(sourceReachabilityProvider);
        }
        return;
      }
      if (kind.isRemoteVideoSource) {
        final added = await showDialog<MediaSource>(
          context: context,
          barrierDismissible: false,
          builder: (_) => EmbyConnectionSheet(
            repository: ref.read(embyConnectionProvider),
            kind: kind,
          ),
        );
        if (mounted) {
          ref.invalidate(sourceReachabilityProvider);
          if (added != null) {
            unawaited(ref.read(sourceScansProvider.notifier).scan(added.id));
          }
        }
        return;
      }
      final draft = await showDialog<SourceDraft>(
        context: context,
        builder: (_) =>
            AddSourceDialog(access: ref.read(directoryAccessProvider)),
      );
      if (draft == null || !mounted) return;
      if (draft.backToSourceSelection) continue;
      await _perform(() async {
        final scans = ref.read(sourceScansProvider.notifier);
        final result = await ref
            .read(sourceRepositoryProvider)
            .addFolders(
              locations: draft.locations,
              mediaType: draft.mediaType,
              options: SourceOptions(
                autoScan: draft.autoScan,
                includeInMetadataFetch: draft.includeInMetadataFetch,
                includeInHealthCheck: draft.includeInHealthCheck,
                preferMetadataWriteToSource: draft.preferMetadataWriteToSource,
              ),
            );
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
      return;
    }
  }

  Future<void> _relocate(MediaSource source) => _perform(() async {
    final location = await ref.read(directoryAccessProvider).choose();
    if (location == null || !mounted) return;
    // A full scan prunes absent index rows. Make the mapping explicit.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SourceConfirmationDialog(
        title: '重新定位来源',
        subtitle: source.name,
        message: '请确认这是原目录的新位置：\n$location\n\n会保留来源 ID 和已有索引，重新扫描后更新文件状态。',
        confirmLabel: '确认位置',
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sourceRepositoryProvider).relocate(source.id, location);
    if (mounted) {
      unawaited(ref.read(sourceScansProvider.notifier).scan(source.id));
    }
  });

  Future<void> _settings(MediaSource source) async {
    if (source.kind == MediaSourceKind.url) {
      await showDialog<void>(
        context: context,
        builder: (_) => const UrlSourceManagementSheet(),
      );
      if (mounted) {
        ref.invalidate(sourcesProvider);
        ref.invalidate(sourceReachabilityProvider);
      }
      return;
    }
    if (source.kind.isRemoteVideoSource) {
      final scopeChanged = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => EmbyLibrarySheet(
          source: source,
          repository: ref.read(embyConnectionProvider),
        ),
      );
      if (mounted) {
        ref.invalidate(sourceReachabilityProvider);
        if (scopeChanged == true) {
          unawaited(ref.read(sourceScansProvider.notifier).scan(source.id));
        }
      }
      return;
    }
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
      showAppToast(context, '媒体源设置已保存', kind: AppFeedbackKind.success);
    });
  }

  Future<void> _reauthenticate(MediaSource source) async {
    await showDialog<MediaSource>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmbyConnectionSheet(
        source: source,
        repository: ref.read(embyConnectionProvider),
      ),
    );
    if (mounted) ref.invalidate(sourceReachabilityProvider);
  }

  Future<void> _remove(MediaSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SourceConfirmationDialog(
        title: '移除媒体源？',
        subtitle: source.name,
        message: '将移除该来源及其应用内索引，原目录和媒体文件不会被删除。',
        confirmLabel: '移除',
        destructive: true,
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() async {
        if (source.kind == MediaSourceKind.url) {
          final items = await ref.read(urlVideoRepositoryProvider).list();
          await ref
              .read(urlVideoRepositoryProvider)
              .remove(items.map((item) => item.identity).toSet());
          ref.invalidate(urlVideosProvider);
        } else if (source.kind.isRemoteVideoSource) {
          await ref.read(embyConnectionProvider).remove(source.id);
        } else {
          await ref.read(sourceRepositoryProvider).remove(source.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final scans = ref.watch(sourceScansProvider);
    final reachable = ref.watch(sourceReachabilityProvider);
    final access = ref.watch(directoryAccessProvider);
    final isScanning = scans.values.any((scan) => scan.busy);
    return PageContent(
      title: '媒体源',
      subtitle: sourcesSubtitle,
      header: SourcesHeader(
        actions: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SourceSheetButton(
              key: const ValueKey('add-source'),
              label: '添加媒体源…',
              prominent: true,
              onPressed: _busy ? null : _add,
              icon: const SourceLineIcon(
                SourceGlyph.plus,
                size: 15,
                lineWidth: 2.2,
              ),
            ),
            SourceSheetButton(
              key: const ValueKey('scan-all'),
              label: '扫描全部',
              outlined: true,
              onPressed:
                  _busy ||
                      isScanning ||
                      !(sources.asData?.value.any(
                            (s) =>
                                (s.kind.isFileSource ||
                                s.kind.isRemoteVideoSource),
                          ) ??
                          false)
                  ? null
                  : () => ref
                        .read(sourceScansProvider.notifier)
                        .scanAll(sources.requireValue),
              icon: const SourceLineIcon(SourceGlyph.refresh, size: 15),
            ),
          ],
        ),
      ),
      children: [
        if (!access.supported) ...[
          _SourcePageNotice(
            icon: SourceGlyph.warning,
            message: access.unavailableReason,
            warning: true,
          ),
          const SizedBox(height: 18),
        ],
        if (_busy) ...[
          const _SourcePageNotice(
            icon: SourceGlyph.refresh,
            message: '正在处理媒体源，请稍候…',
          ),
          const SizedBox(height: 18),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: _SourcePageNotice(
              icon: SourceGlyph.warning,
              message: _error!,
              warning: true,
            ),
          ),
        ...sources.when(
          loading: () => [const _SourcesLoadingState()],
          error: (error, stack) => [
            _SourcePageNotice(
              icon: SourceGlyph.warning,
              message: sourceErrorMessage(error),
              warning: true,
            ),
          ],
          data: (items) {
            if (items.isEmpty) return [const _SourcesEmptyState()];
            return reachable.when(
              loading: () => [const _SourcesLoadingState(rows: 2)],
              error: (error, stack) => [
                _SourcePageNotice(
                  icon: SourceGlyph.warning,
                  message: sourceErrorMessage(error),
                  warning: true,
                ),
              ],
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

  // SourcesView.SourceRowView: one compact row, with state and actions kept at
  // the same visual level instead of the earlier dashboard-card treatment.
  Widget _sourceCard(
    MediaSource source,
    SourceScanState scan, {
    required bool connected,
    required bool isScanning,
    required bool canChoose,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = SourceSheetPalette(dark);
    final statusColor = connected
        ? Color(dark ? 0xFF45D67F : 0xFF1F9D57)
        : Color(dark ? 0xFFFFB84D : 0xFFD98A00);
    final accent = !connected
        ? statusColor
        : source.kind == MediaSourceKind.url
        ? const Color(0xFF22CDA4)
        : source.kind.isRemoteVideoSource
        ? mediaServerBrandColor(source.kind)
        : source.kind == MediaSourceKind.mountedNas ||
              source.mediaType == SourceMediaType.homeVideo
        ? const Color(0xFF38BDF8)
        : source.mediaType == SourceMediaType.music
        ? Color(dark ? 0xFFFFC66D : 0xFFD98A00)
        : palette.selectedTint;
    final secondaryTextStyle = TextStyle(
      fontSize: 11.5,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final urlItems = source.kind == MediaSourceKind.url
        ? ref.watch(urlVideosProvider).value
        : null;
    final urlHealth = source.kind == MediaSourceKind.url
        ? ref.watch(urlVideoHealthProvider)
        : const <MediaIdentity, UrlVideoHealth>{};
    final unhealthyUrls = urlHealth.values
        .where((state) => state.isUnhealthy)
        .length;
    final sourceStatusLabel = source.kind == MediaSourceKind.url
        ? unhealthyUrls == 0
              ? '链接正常'
              : '$unhealthyUrls 个链接失效'
        : connected
        ? '可访问'
        : '不可访问';
    return _SourceCardSurface(
      key: ValueKey('source-${source.id}'),
      sourceId: source.id,
      accent: accent,
      onTap: () => context.go('/sources/${source.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SourceAvatar(
                  key: ValueKey('source-avatar-${source.id}'),
                  source: source,
                  connected: connected,
                  accent: accent,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            source.kind.isRemoteVideoSource
                                ? source.kind.label
                                : source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _SourceBadge(
                            label: sourceStatusLabel,
                            color:
                                source.kind == MediaSourceKind.url &&
                                    unhealthyUrls > 0
                                ? Color(dark ? 0xFFFFB84D : 0xFFD98A00)
                                : statusColor,
                            icon: SourceLineIcon(
                              source.kind == MediaSourceKind.url &&
                                      unhealthyUrls > 0
                                  ? SourceGlyph.warning
                                  : connected
                                  ? SourceGlyph.checkCircle
                                  : SourceGlyph.warning,
                              size: 11.5,
                              lineWidth: 1.9,
                            ),
                          ),
                          _SourceBadge(
                            label: source.kind.label,
                            color: accent,
                            icon: source.kind == MediaSourceKind.url
                                ? const Icon(Icons.link_rounded, size: 12)
                                : SourceLineIcon(
                                    source.kind.isRemoteVideoSource
                                        ? SourceGlyph.server
                                        : SourceGlyph.drive,
                                    size: 11.5,
                                    lineWidth: 1.9,
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (source.kind == MediaSourceKind.url)
                        Text(
                          '${urlItems?.length ?? source.itemCount} 个视频地址 · 在「其他视频」中查看',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondaryTextStyle,
                        )
                      else
                        Tooltip(
                          message: source.location,
                          waitDuration: const Duration(milliseconds: 550),
                          child: Text(
                            source.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondaryTextStyle,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _SourceRowActions(
                  key: ValueKey('source-actions-${source.id}'),
                  source: source,
                  scan: scan,
                  showAlias: source.kind != MediaSourceKind.url,
                  showRelocate: source.kind.isFileSource,
                  showReauthenticate: source.kind.isRemoteVideoSource,
                  onSettings:
                      _busy ||
                          (source.kind.isRemoteVideoSource && scan.busy) ||
                          source.mediaType == SourceMediaType.privateCollection
                      ? null
                      : () => _settings(source),
                  onScan: source.kind == MediaSourceKind.url
                      ? null
                      : scan.busy
                      ? () => ref
                            .read(sourceScansProvider.notifier)
                            .cancel(source.id)
                      : _busy || isScanning || !connected
                      ? null
                      : () => ref
                            .read(sourceScansProvider.notifier)
                            .scan(source.id),
                  onAlias: _busy || scan.busy
                      ? null
                      : () => showSourceAliasDialog(
                          context,
                          source: source,
                          repository: ref.read(sourceRepositoryProvider),
                        ),
                  onRelocate:
                      _busy ||
                          scan.busy ||
                          !canChoose ||
                          !source.kind.isFileSource
                      ? null
                      : () => _relocate(source),
                  onReauthenticate:
                      _busy || scan.busy || !source.kind.isRemoteVideoSource
                      ? null
                      : () => _reauthenticate(source),
                  onRemove: _busy || scan.busy ? null : () => _remove(source),
                ),
              ],
            ),
            if (scan.running) ...[
              const SizedBox(height: 14),
              _SourceProgressPanel(
                accent: accent,
                fraction: scan.progress.totalFiles > 0
                    ? scan.progress.fraction
                    : null,
                label: source.kind.isRemoteVideoSource
                    ? scan.progress.phase == SourceScanPhase.persisting
                          ? '正在入库 ${scan.progress.processedFiles}/${scan.progress.totalFiles} 个媒体条目'
                          : '已读取 ${scan.progress.processedFiles} 个媒体条目'
                    : '已处理 ${scan.progress.processedFiles}/${scan.progress.totalFiles} 个文件',
              ),
            ],
            if (scan.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _SourceMessagePill(message: scan.message!),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceRowActions extends StatelessWidget {
  const _SourceRowActions({
    required this.source,
    required this.scan,
    required this.showAlias,
    required this.showRelocate,
    required this.showReauthenticate,
    required this.onSettings,
    required this.onScan,
    required this.onAlias,
    required this.onRelocate,
    required this.onReauthenticate,
    required this.onRemove,
    super.key,
  });

  final MediaSource source;
  final SourceScanState scan;
  final bool showAlias;
  final bool showRelocate;
  final bool showReauthenticate;
  final VoidCallback? onSettings;
  final VoidCallback? onScan;
  final VoidCallback? onAlias;
  final VoidCallback? onRelocate;
  final VoidCallback? onReauthenticate;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final hasMore = showAlias || showRelocate || showReauthenticate;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SourceRowIconButton(
          key: ValueKey('source-settings-${source.id}'),
          tooltip: source.kind == MediaSourceKind.url ? '管理 URL 视频地址' : '设置',
          onPressed: onSettings,
          child: const SourceLineIcon(SourceGlyph.sliders, size: 17),
        ),
        if (source.kind != MediaSourceKind.url) ...[
          const SizedBox(width: 14),
          _SourceRowIconButton(
            key: ValueKey('source-scan-${source.id}'),
            tooltip: scan.busy
                ? (source.kind.isRemoteVideoSource ? '取消同步' : '取消扫描')
                : source.kind.isRemoteVideoSource
                ? '同步媒体'
                : '扫描',
            onPressed: onScan,
            child: Icon(
              scan.busy ? Icons.close_rounded : Icons.refresh_rounded,
              size: 18,
            ),
          ),
        ],
        if (hasMore) ...[
          const SizedBox(width: 14),
          MenuAnchor(
            menuChildren: [
              if (showAlias)
                MenuItemButton(
                  key: ValueKey('source-alias-${source.id}'),
                  leadingIcon: const Icon(Icons.edit_outlined, size: 17),
                  onPressed: onAlias,
                  child: const Text('设置别名'),
                ),
              if (showRelocate)
                MenuItemButton(
                  key: ValueKey('source-relocate-${source.id}'),
                  leadingIcon: const Icon(
                    Icons.drive_file_move_outline,
                    size: 17,
                  ),
                  onPressed: onRelocate,
                  child: const Text('重新定位'),
                ),
              if (showReauthenticate)
                MenuItemButton(
                  key: ValueKey('source-reauthenticate-${source.id}'),
                  leadingIcon: const Icon(Icons.key_rounded, size: 17),
                  onPressed: onReauthenticate,
                  child: const Text('重新认证'),
                ),
            ],
            builder: (context, controller, child) => _SourceRowIconButton(
              key: ValueKey('source-more-${source.id}'),
              tooltip: '更多操作',
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: const Icon(Icons.more_horiz_rounded, size: 19),
            ),
          ),
        ],
        const SizedBox(width: 14),
        _SourceRowIconButton(
          key: ValueKey('source-remove-${source.id}'),
          tooltip: '删除',
          onPressed: onRemove,
          foreground: const Color(0xFFFF4D6B),
          child: const Icon(Icons.delete_outline_rounded, size: 18),
        ),
      ],
    );
  }
}

class _SourceRowIconButton extends StatelessWidget {
  const _SourceRowIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.foreground,
    super.key,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.square(34)),
        maximumSize: const WidgetStatePropertyAll(Size.square(34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? (foreground ?? palette.secondary).withValues(alpha: .34)
              : foreground ?? palette.secondary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? palette.control.withValues(alpha: .86)
              : Colors.transparent,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      icon: child,
    );
  }
}

class _SourceCardSurface extends StatefulWidget {
  const _SourceCardSurface({
    required this.sourceId,
    required this.accent,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String sourceId;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_SourceCardSurface> createState() => _SourceCardSurfaceState();
}

class _SourceCardSurfaceState extends State<_SourceCardSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final active = _hovered || _focused;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return FocusableActionDetector(
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduceMotion ? 0 : 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          active && !reduceMotion ? -4 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: active
              ? Color.lerp(palette.staticSurface, palette.iconChip, .16)
              : palette.staticSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: palette.shadow.withValues(
                      alpha: palette.dark ? .20 : .11,
                    ),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ]
              : const [],
        ),
        // Swift strokeBorder overlays the row without adding layout insets.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _focused
                ? widget.accent.withValues(alpha: .72)
                : active
                ? widget.accent.withValues(alpha: .24)
                : palette.border,
            width: _focused ? 1.4 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('source-browse-${widget.sourceId}'),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({
    required this.source,
    required this.connected,
    required this.accent,
    super.key,
  });

  final MediaSource source;
  final bool connected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: connected ? 1 : .92),
            accent.withValues(alpha: connected ? .72 : .64),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? .24 : .42),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: connected ? .30 : .14),
            blurRadius: 16,
            offset: const Offset(-5, 8),
          ),
          BoxShadow(
            color: const Color(0xFF2E90FA)
                .withValues(alpha: connected ? .16 : .08),
            blurRadius: 10,
            offset: const Offset(5, -4),
          ),
        ],
      ),
      child: !connected
          ? const SourceLineIcon(
              SourceGlyph.warning,
              size: 25,
              color: Colors.white,
            )
          : source.kind.isRemoteVideoSource
          ? const SourceLineIcon(
              SourceGlyph.server,
              size: 25,
              color: Colors.white,
            )
          : source.kind == MediaSourceKind.url
          ? const Icon(Icons.link_rounded, size: 27, color: Colors.white)
          : const SourceLineIcon(
              SourceGlyph.drive,
              size: 25,
              color: Colors.white,
            ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final Widget icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: .13)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme(
          data: IconThemeData(color: color),
          child: icon,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _SourceProgressPanel extends StatelessWidget {
  const _SourceProgressPanel({
    required this.accent,
    required this.fraction,
    required this.label,
  });

  final Color accent;
  final double? fraction;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SourceLineIcon(SourceGlyph.refresh, size: 13, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.secondary,
                  ),
                ),
              ),
              if (fraction != null)
                Text(
                  '${(fraction! * 100).clamp(0, 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: fraction,
              color: accent,
              backgroundColor: accent.withValues(alpha: .12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceMessagePill extends StatelessWidget {
  const _SourceMessagePill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.control.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 11.5, color: palette.secondary),
      ),
    );
  }
}

class _SourcePageNotice extends StatelessWidget {
  const _SourcePageNotice({
    required this.icon,
    required this.message,
    this.warning = false,
  });

  final SourceGlyph icon;
  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SourceSheetPalette(theme.brightness == Brightness.dark);
    final color = warning ? theme.colorScheme.error : palette.selectedTint;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .065),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: SourceLineIcon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: warning ? color : palette.secondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesLoadingState extends StatefulWidget {
  const _SourcesLoadingState({this.rows = 3});

  final int rows;

  @override
  State<_SourcesLoadingState> createState() => _SourcesLoadingStateState();
}

class _SourcesLoadingStateState extends State<_SourcesLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(min: .72, max: 1, reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return FadeTransition(
      opacity: _controller,
      child: Container(
        key: const ValueKey('sources-loading-state'),
        constraints: const BoxConstraints(minHeight: 320),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.staticSurface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: palette.dark ? .10 : .05),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 38,
                  child: Center(
                    child: SourceLineIcon(
                      SourceGlyph.drive,
                      size: 32,
                      color: palette.selectedTint.withValues(alpha: .90),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '正在加载媒体源',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '正在准备当前页面',
                      style: TextStyle(fontSize: 11, color: palette.secondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < widget.rows; index++) ...[
              Container(
                key: ValueKey('sources-loading-row-$index'),
                height: 72,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.control.withValues(alpha: .34),
                  borderRadius: BorderRadius.circular(16),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: palette.border.withValues(alpha: .86),
                  ),
                ),
                child: Row(
                  children: [
                    _SourceSkeletonBlock(
                      width: 52,
                      height: 52,
                      radius: 8,
                      color: palette.control,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SourceSkeletonBlock(
                            width: 180 + index * 18,
                            height: 10,
                            radius: 4,
                            color: palette.control,
                          ),
                          const SizedBox(height: 7),
                          _SourceSkeletonBlock(
                            width: 120 + index * 11,
                            height: 8,
                            radius: 4,
                            color: palette.control.withValues(alpha: .72),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index != widget.rows - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceSkeletonBlock extends StatelessWidget {
  const _SourceSkeletonBlock({
    required this.width,
    required this.height,
    required this.color,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _SourcesEmptyState extends StatefulWidget {
  const _SourcesEmptyState();

  @override
  State<_SourcesEmptyState> createState() => _SourcesEmptyStateState();
}

class _SourcesEmptyStateState extends State<_SourcesEmptyState> {
  bool _appeared = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_appeared) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _appeared = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _appeared = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      key: const ValueKey('sources-empty-state'),
      opacity: _appeared ? 1 : 0,
      duration: Duration(milliseconds: reduceMotion ? 0 : 240),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _appeared ? Offset.zero : const Offset(0, .035),
        duration: Duration(milliseconds: reduceMotion ? 0 : 240),
        curve: Curves.easeOutCubic,
        child: _buildContent(context, palette),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SourceSheetPalette palette,
  ) => Container(
    constraints: const BoxConstraints(minHeight: 320),
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 112,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                key: const ValueKey('sources-empty-icon-glow'),
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-.28, -.44),
                    radius: .72,
                    colors: [
                      Colors.white.withValues(alpha: palette.dark ? .12 : .64),
                      palette.selectedTint.withValues(
                        alpha: palette.dark ? .14 : .20,
                      ),
                      palette.solar.withValues(alpha: palette.dark ? .08 : .16),
                      Colors.transparent,
                    ],
                    stops: const [0, .34, .68, 1],
                  ),
                ),
              ),
              Container(
                key: const ValueKey('sources-empty-icon-tile'),
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.control.withValues(
                    alpha: palette.dark ? .40 : .72,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: palette.dark ? .22 : .74,
                    ),
                  ),
                ),
                child: SourceLineIcon(
                  SourceGlyph.drive,
                  size: 46,
                  lineWidth: 2.2,
                  color: palette.selectedTint.withValues(alpha: .92),
                ),
              ),
            ],
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
            '接入本地文件夹、移动硬盘、网络挂载、URL 视频、ReelNest Server、Emby、Jellyfin 或 Plex 媒体库后，ReelNest 会整理索引。',
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
  );
}
