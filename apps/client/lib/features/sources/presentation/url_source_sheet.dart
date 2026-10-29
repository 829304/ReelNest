import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/source_providers.dart';
import '../application/url_video_providers.dart';
import 'local_media_artwork.dart';
import 'source_confirmation_dialog.dart';

/// SourcesView.urlConfiguration. This is a persistent library entry, not the
/// player's temporary "open URL" action.
class UrlSourceAddSheet extends ConsumerStatefulWidget {
  const UrlSourceAddSheet({super.key});

  @override
  ConsumerState<UrlSourceAddSheet> createState() => _UrlSourceAddSheetState();
}

class _UrlSourceAddSheetState extends ConsumerState<UrlSourceAddSheet> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy || UrlVideoPolicy.normalize(_url.text) == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(urlVideoRepositoryProvider)
          .add(_url.text, title: _title.text);
      ref.invalidate(urlVideosProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = sourceErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return _UrlSheetFrame(
      title: '添加 URL 媒体源',
      subtitle: '添加一个网络视频地址，名称可选填。',
      busy: _busy,
      actions: [
        SourceSheetButton(
          label: '取消',
          outlined: true,
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        SourceSheetButton(
          key: const ValueKey('url-source-submit'),
          label: _busy ? '添加中' : '添加',
          prominent: true,
          onPressed: _busy || UrlVideoPolicy.normalize(_url.text) == null
              ? null
              : _add,
        ),
      ],
      children: [
        AppSheetSection(
          title: '视频地址',
          subtitle: '支持直链视频地址，名称可选填。',
          icon: const Icon(Icons.link_rounded),
          colors: palette.section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _UrlTextField(
                key: const ValueKey('url-source-url'),
                controller: _url,
                hintText: 'https://example.com/video.mp4 或 rtsp://…',
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
              ),
              const SizedBox(height: 12),
              _UrlTextField(
                key: const ValueKey('url-source-title'),
                controller: _title,
                hintText: '名称（留空则自动取文件名）',
                enabled: !_busy,
                onSubmitted: (_) => _add(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppInfoNote(
          text: '添加后会出现在「其他视频」分类。多个地址会合并到同一个 URL 媒体源，可在来源行的「管理」中增删改查。',
          icon: const Icon(Icons.link_rounded, size: 14),
          surface: palette.iconChip.withValues(alpha: .58),
          border: palette.border,
          iconTint: palette.accent,
          textColor: palette.secondary,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          AppInlineNotice(message: _error!, kind: AppFeedbackKind.error),
        ],
      ],
    );
  }
}

/// SourcesView.URLSourceManagementSheet.
class UrlSourceManagementSheet extends ConsumerStatefulWidget {
  const UrlSourceManagementSheet({super.key});

  @override
  ConsumerState<UrlSourceManagementSheet> createState() =>
      _UrlSourceManagementSheetState();
}

class _UrlSourceManagementSheetState
    extends ConsumerState<UrlSourceManagementSheet> {
  final _newUrl = TextEditingController();
  final _newTitle = TextEditingController();
  MediaIdentity? _editing;
  final _editUrl = TextEditingController();
  final _editTitle = TextEditingController();
  bool _busy = false;
  bool _checking = false;
  String? _message;
  AppFeedbackKind _messageKind = AppFeedbackKind.information;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refreshHealth(feedback: false));
      }
    });
  }

  @override
  void dispose() {
    _newUrl.dispose();
    _newTitle.dispose();
    _editUrl.dispose();
    _editTitle.dispose();
    super.dispose();
  }

  void _feedback(String message, AppFeedbackKind kind) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageKind = kind;
    });
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      _feedback(sourceErrorMessage(error), AppFeedbackKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshHealth({bool feedback = true}) async {
    if (_checking) return;
    if (mounted) setState(() => _checking = true);
    try {
      await ref.read(urlVideoHealthProvider.notifier).refresh();
      if (feedback && mounted) {
        _feedback('链接检查已完成。', AppFeedbackKind.success);
      }
    } catch (error) {
      if (mounted) {
        _feedback(sourceErrorMessage(error), AppFeedbackKind.error);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _add() => _perform(() async {
    final result = await ref
        .read(urlVideoRepositoryProvider)
        .add(_newUrl.text, title: _newTitle.text);
    _newUrl.clear();
    _newTitle.clear();
    ref.invalidate(urlVideosProvider);
    final skipped = result.skipped == 0 ? '' : '，跳过 ${result.skipped} 个无效或重复地址';
    _feedback('已添加 ${result.added} 个地址$skipped。', AppFeedbackKind.success);
  });

  Future<void> _save(UrlVideo item) => _perform(() async {
    await ref
        .read(urlVideoRepositoryProvider)
        .update(item.identity, url: _editUrl.text, title: _editTitle.text);
    setState(() => _editing = null);
    ref.invalidate(urlVideosProvider);
    _feedback('地址已保存。', AppFeedbackKind.success);
  });

  Future<void> _remove(UrlVideo item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => SourceConfirmationDialog(
        title: '删除 URL 地址？',
        subtitle: item.title,
        message: '将从「其他视频」移除该地址；已下载到本机的文件不会被删除。',
        confirmLabel: '删除',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() async {
      await ref.read(urlVideoRepositoryProvider).remove({item.identity});
      ref.invalidate(urlVideosProvider);
      _feedback('地址已删除。', AppFeedbackKind.success);
    });
  }

  Future<void> _captureCover(UrlVideo item) => _perform(() async {
    await ref.read(urlVideoCoverServiceProvider).capture(item.identity);
    ref.invalidate(sourceMediaDetailProvider(item.identity));
    _feedback('已完成封面截取尝试。', AppFeedbackKind.success);
  });

  @override
  Widget build(BuildContext context) {
    final videos = ref.watch(urlVideosProvider);
    final health = ref.watch(urlVideoHealthProvider);
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final addable = _addableCount(
      _newUrl.text,
      videos.value?.map((item) => item.url).toSet() ?? const {},
    );
    final batch = addable > 1;
    return _UrlSheetFrame(
      title: 'URL 媒体源',
      subtitle: '管理网络视频地址，增删改查会同步到「其他视频」分类。',
      busy: _busy,
      actions: [
        SourceSheetButton(
          key: const ValueKey('url-source-health-refresh'),
          label: _checking ? '检查中' : '重新检查链接',
          outlined: true,
          onPressed: _busy || _checking || videos.value?.isEmpty != false
              ? null
              : _refreshHealth,
        ),
        SourceSheetButton(
          label: '完成',
          prominent: true,
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
      ],
      children: [
        _UrlSectionSurface(
          key: const ValueKey('url-source-add-section'),
          palette: palette,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '添加地址',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              _UrlTextField(
                key: const ValueKey('url-source-manager-url'),
                controller: _newUrl,
                hintText: '每行一个视频地址，可批量添加',
                enabled: !_busy,
                minLines: 1,
                maxLines: 5,
                onChanged: (_) => setState(() {}),
              ),
              if (!batch) ...[
                const SizedBox(height: 10),
                _UrlTextField(
                  key: const ValueKey('url-source-manager-title'),
                  controller: _newTitle,
                  hintText: '名称（可选，留空则取文件名）',
                  enabled: !_busy,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (batch)
                    Expanded(
                      child: Text(
                        '检测到 $addable 个链接',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.secondary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  SourceSheetButton(
                    key: const ValueKey('url-source-manager-add'),
                    label: batch ? '批量添加 $addable 个' : '添加',
                    prominent: true,
                    height: 38,
                    onPressed: _busy || addable == 0 ? null : _add,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          AppInlineNotice(message: _message!, kind: _messageKind),
        ],
        const SizedBox(height: 14),
        videos.when(
          loading: () => const SizedBox(
            height: 150,
            child: Center(
              child: CircularProgressIndicator(value: .72, strokeWidth: 2),
            ),
          ),
          error: (error, stack) => AppInlineNotice(
            message: sourceErrorMessage(error),
            kind: AppFeedbackKind.error,
            actionLabel: '重试',
            onAction: () => ref.invalidate(urlVideosProvider),
          ),
          data: (items) => items.isEmpty
              ? const _UrlEmptyState()
              : Column(
                  children: [
                    for (final item in items) ...[
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              alignment: Alignment.topCenter,
                              children: [...previousChildren, ?currentChild],
                            ),
                        child: _editing == item.identity
                            ? _editRow(item, palette)
                            : _itemRow(item, health[item.identity], palette),
                      ),
                      if (item != items.last) const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  int _addableCount(String raw, Set<String> existing) {
    final candidates = <String>{};
    for (final line in UrlVideoPolicy.lines(raw)) {
      final normalized = UrlVideoPolicy.normalize(line);
      if (normalized != null && !existing.contains(normalized)) {
        candidates.add(normalized);
      }
    }
    return candidates.length;
  }

  Widget _editRow(UrlVideo item, SourceSheetPalette palette) =>
      _UrlSectionSurface(
        key: ValueKey('url-source-edit-${item.identity.localId}'),
        palette: palette,
        selected: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _UrlTextField(
              controller: _editUrl,
              hintText: '视频地址',
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _UrlTextField(
              controller: _editTitle,
              hintText: '名称',
              enabled: !_busy,
              onSubmitted: (_) => _save(item),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SourceSheetButton(
                  label: '取消',
                  outlined: true,
                  height: 36,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _editing = null),
                ),
                const SizedBox(width: 10),
                SourceSheetButton(
                  key: ValueKey('url-source-save-${item.identity.localId}'),
                  label: '保存',
                  prominent: true,
                  height: 36,
                  onPressed:
                      _busy || UrlVideoPolicy.normalize(_editUrl.text) == null
                      ? null
                      : () => _save(item),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _itemRow(
    UrlVideo item,
    UrlVideoHealth? health,
    SourceSheetPalette palette,
  ) => _UrlItemSurface(
    key: ValueKey('url-source-item-${item.identity.localId}'),
    palette: palette,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              width: 64,
              height: 40,
              child: _UrlThumbnail(identity: item.identity),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _UrlHealthIcon(health ?? UrlVideoHealth.unknown),
                  ],
                ),
                const SizedBox(height: 3),
                Tooltip(
                  message: item.url,
                  child: Text(
                    item.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: palette.secondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _UrlActionButton(
            key: ValueKey('url-source-cover-${item.identity.localId}'),
            tooltip: '从视频截取封面',
            icon: Icons.photo_outlined,
            palette: palette,
            onPressed: _busy ? null : () => _captureCover(item),
          ),
          const SizedBox(width: 4),
          _UrlActionButton(
            key: ValueKey('url-source-edit-button-${item.identity.localId}'),
            tooltip: '编辑',
            icon: Icons.edit_outlined,
            palette: palette,
            onPressed: _busy
                ? null
                : () {
                    _editUrl.text = item.url;
                    _editTitle.text = item.title;
                    setState(() => _editing = item.identity);
                  },
          ),
          const SizedBox(width: 4),
          _UrlActionButton(
            key: ValueKey('url-source-delete-${item.identity.localId}'),
            tooltip: '删除',
            icon: Icons.delete_outline_rounded,
            palette: palette,
            destructive: true,
            onPressed: _busy ? null : () => _remove(item),
          ),
        ],
      ),
    ),
  );
}

class _UrlSectionSurface extends StatelessWidget {
  const _UrlSectionSurface({
    required this.palette,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.selected = false,
    super.key,
  });

  final SourceSheetPalette palette;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: selected
          ? palette.iconChip.withValues(alpha: .46)
          : palette.staticSurface,
      borderRadius: BorderRadius.circular(selected ? 14 : 16),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(selected ? 14 : 16),
      border: Border.all(
        color: selected
            ? palette.selectedTint.withValues(alpha: .28)
            : palette.border,
      ),
    ),
    child: child,
  );
}

class _UrlItemSurface extends StatefulWidget {
  const _UrlItemSurface({
    required this.palette,
    required this.child,
    super.key,
  });

  final SourceSheetPalette palette;
  final Widget child;

  @override
  State<_UrlItemSurface> createState() => _UrlItemSurfaceState();
}

class _UrlItemSurfaceState extends State<_UrlItemSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _hovered
              ? Color.lerp(
                  widget.palette.staticSurface,
                  widget.palette.iconChip,
                  .12,
                )
              : widget.palette.staticSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: widget.palette.shadow.withValues(
                      alpha: widget.palette.dark ? .12 : .07,
                    ),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered
                ? widget.palette.selectedTint.withValues(alpha: .18)
                : widget.palette.border,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _UrlActionButton extends StatelessWidget {
  const _UrlActionButton({
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final SourceSheetPalette palette;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tint = destructive
        ? Theme.of(context).colorScheme.error
        : palette.secondary;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size.square(36)),
        minimumSize: const WidgetStatePropertyAll(Size.square(36)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tint.withValues(alpha: .34);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return destructive ? tint : palette.selectedTint;
          }
          return tint;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return destructive
                ? tint.withValues(alpha: .08)
                : palette.iconChip.withValues(alpha: .72);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return BorderSide(
              color: (destructive ? tint : palette.selectedTint).withValues(
                alpha: .62,
              ),
              width: 1.2,
            );
          }
          return BorderSide(color: palette.border.withValues(alpha: 0));
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _UrlThumbnail extends ConsumerWidget {
  const _UrlThumbnail({required this.identity});
  final MediaIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref
        .watch(sourcesProvider)
        .value
        ?.where((candidate) => candidate.id == identity.sourceId)
        .firstOrNull;
    final item = ref.watch(sourceMediaDetailProvider(identity)).value;
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final placeholder = ColoredBox(
      color: palette.iconChip,
      child: Icon(Icons.play_circle_outline_rounded, color: palette.accent),
    );
    if (source == null || item == null) return placeholder;
    return LocalMediaArtwork(
      source: source,
      item: item,
      fit: BoxFit.cover,
      placeholder: placeholder,
    );
  }
}

class _UrlHealthIcon extends StatelessWidget {
  const _UrlHealthIcon(this.health);
  final UrlVideoHealth health;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (health) {
      UrlVideoHealth.ok => Color(dark ? 0xFF67E19A : 0xFF1F9D57),
      UrlVideoHealth.unreachable ||
      UrlVideoHealth.unparseable => Color(dark ? 0xFFFFC66D : 0xFFD98A00),
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final icon = switch (health) {
      UrlVideoHealth.ok => Icons.check_circle_outline_rounded,
      UrlVideoHealth.unreachable => Icons.link_off_rounded,
      UrlVideoHealth.unparseable => Icons.warning_amber_rounded,
      UrlVideoHealth.checking => Icons.sync_rounded,
      UrlVideoHealth.unknown => Icons.help_outline_rounded,
    };
    return Tooltip(
      message: health.label,
      child: Icon(icon, size: 15, color: color),
    );
  }
}

class _UrlEmptyState extends StatelessWidget {
  const _UrlEmptyState();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 170,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_link_rounded,
            size: 34,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          const Text(
            '还没有 URL 视频',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '在上方粘贴 http、rtsp 等直链地址即可添加。',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class _UrlTextField extends StatelessWidget {
  const _UrlTextField({
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: maxLines > 1 ? TextInputType.multiline : TextInputType.url,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 12, color: palette.secondary),
        filled: true,
        fillColor: palette.control,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.selectedTint, width: 1.3),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
    );
  }
}

class _UrlSheetFrame extends StatelessWidget {
  const _UrlSheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.actions,
    this.busy = false,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return PopScope(
      canPop: !busy,
      child: Dialog(
        backgroundColor: palette.page,
        elevation: 0,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSheetHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.iconChip,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.link_rounded,
                      size: 26,
                      color: palette.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
                AppSheetActionFooter(
                  panelBorder: palette.panelBorder,
                  solarLightTint: palette.solar,
                  actions: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
