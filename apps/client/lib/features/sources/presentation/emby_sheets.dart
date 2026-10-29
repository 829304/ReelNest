import 'dart:async';

import 'package:flutter/material.dart';

import '../../../api/emby/emby_client.dart';
import '../../../domain/media_source.dart';
import '../../../domain/source_options.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_policy_switch.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../data/emby_connection_repository.dart';
import '../application/source_providers.dart';
import 'media_server_brand_mark.dart';
import 'source_wizard_steps.dart';

/// AddMediaSourceWizardSheet.sourceSelection for currently supported sources.
class SourceKindSheet extends StatefulWidget {
  const SourceKindSheet({super.key});
  @override
  State<SourceKindSheet> createState() => _SourceKindSheetState();
}

class _SourceKindSheetState extends State<SourceKindSheet> {
  MediaSourceKind _kind = MediaSourceKind.localFolder;
  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return EmbySheetFrame(
      title: '添加媒体源',
      subtitle: '选择要接入 ReelNest 的来源类型。',
      actions: [
        SourceSheetButton(
          label: '取消',
          outlined: true,
          onPressed: () => Navigator.pop(context),
        ),
        SourceSheetButton(
          label: '下一步',
          prominent: true,
          onPressed: () => Navigator.pop(context, _kind),
        ),
      ],
      children: [
        const SourceWizardSteps(
          key: ValueKey('source-kind-wizard-steps'),
          current: 0,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final kind in [
              MediaSourceKind.localFolder,
              MediaSourceKind.url,
              MediaSourceKind.emby,
              MediaSourceKind.jellyfin,
              MediaSourceKind.plex,
            ])
              SizedBox(
                width: 264,
                child: _SourceKindCard(
                  key: ValueKey('source-kind-${kind.name}'),
                  kind: kind,
                  selected: _kind == kind,
                  palette: palette,
                  onTap: () => setState(() => _kind = kind),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// AddMediaSourceWizardSheet.sourceKindCard. The original card has one
/// continuous hover/focus surface: selection changes the stroke and tint,
/// while pointer focus adds a restrained lift without nesting another card.
class _SourceKindCard extends StatefulWidget {
  const _SourceKindCard({
    required this.kind,
    required this.selected,
    required this.palette,
    required this.onTap,
    super.key,
  });

  final MediaSourceKind kind;
  final bool selected;
  final SourceSheetPalette palette;
  final VoidCallback onTap;

  @override
  State<_SourceKindCard> createState() => _SourceKindCardState();
}

class _SourceKindCardState extends State<_SourceKindCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = _hovered || _focused;
    final palette = widget.palette;
    final kind = widget.kind;
    final tint = widget.selected ? palette.selectedTint : palette.secondary;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: kind == MediaSourceKind.localFolder ? '本地目录' : kind.label,
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduceMotion ? 0 : 160),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(
          0,
          active && !reduceMotion ? -2 : 0,
          0,
        ),
        constraints: const BoxConstraints(minHeight: 88),
        decoration: BoxDecoration(
          color: widget.selected
              ? palette.iconChip
              : active
              ? Color.lerp(palette.staticSurface, palette.iconChip, .14)
              : palette.staticSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: palette.shadow.withValues(
                      alpha: palette.dark ? .16 : .08,
                    ),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused
                ? palette.selectedTint.withValues(alpha: .78)
                : widget.selected
                ? palette.selectedTint
                : active
                ? palette.selectedTint.withValues(alpha: .22)
                : palette.border,
            width: _focused ? 1.4 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 11,
                children: [
                  SizedBox(
                    width: 26,
                    child: kind == MediaSourceKind.url
                        ? Icon(Icons.link_rounded, size: 20, color: tint)
                        : kind.isRemoteVideoSource
                        ? MediaServerBrandMark(kind: kind, size: 19)
                        : SourceLineIcon(
                            SourceGlyph.drive,
                            size: 19,
                            color: tint,
                          ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          kind == MediaSourceKind.localFolder
                              ? '本地目录'
                              : kind.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          kind.isFileSource
                              ? '本机硬盘、移动硬盘或已挂载目录'
                              : kind == MediaSourceKind.url
                              ? '持久保存网络视频地址'
                              : kind == MediaSourceKind.plex
                              ? '服务器地址与 Plex Token 直连'
                              : '服务器地址与账号登录',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmbySheetFrame extends StatelessWidget {
  const EmbySheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.actions,
    this.busy = false,
    super.key,
  });
  final String title, subtitle;
  final List<Widget> children, actions;
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
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSheetHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: const SourceTitleIcon(),
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

class EmbyConnectionSheet extends StatefulWidget {
  const EmbyConnectionSheet({
    required this.repository,
    this.source,
    this.kind = MediaSourceKind.emby,
    super.key,
  });
  final EmbyConnectionRepository repository;
  final MediaSource? source;
  final MediaSourceKind kind;
  @override
  State<EmbyConnectionSheet> createState() => _EmbyConnectionSheetState();
}

class _EmbyConnectionSheetState extends State<EmbyConnectionSheet> {
  final _server = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController(),
      _token = TextEditingController();
  bool _busy = false, _settings = false, _metadata = true, _health = true;
  RemoteTraceSyncMode _trace = RemoteTraceSyncMode.bidirectional;
  String? _error;
  MediaSourceKind get _kind => widget.source?.kind ?? widget.kind;
  String get _brand => _kind.label;
  bool get _plex => _kind == MediaSourceKind.plex;
  SourceOptions get _options => SourceOptions(
    autoScan: false,
    preferLocalArtwork: false,
    networkScrapingEnabled: false,
    screenshotFallbackEnabled: false,
    includeInMetadataFetch: _metadata,
    includeInHealthCheck: _health,
    remoteTraceSyncMode: _trace,
  );
  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      MediaSource? result;
      if (widget.source case final source?) {
        if (_plex) {
          await widget.repository.reauthenticatePlex(source.id, _token.text);
        } else {
          await widget.repository.reauthenticate(
            source.id,
            _username.text,
            _password.text,
          );
        }
        result = source;
      } else {
        result = _plex
            ? await widget.repository.connectPlex(
                _server.text,
                _token.text,
                options: _options,
              )
            : await widget.repository.connect(
                _server.text,
                _username.text,
                _password.text,
                kind: _kind,
                options: _options,
              );
      }
      if (mounted) {
        setState(() => _busy = false);
        Navigator.pop(context, result);
      }
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
    final reauth = widget.source != null;
    return EmbySheetFrame(
      title: reauth ? '$_brand 重新认证' : '添加媒体源',
      subtitle: _settings
          ? '确认扫描、健康检查和同步策略。'
          : reauth
          ? (_plex ? '填写 Plex Token 以恢复服务器访问。' : '填写服务器地址和登录凭据。')
          : (_plex ? '连接后同步到独立的 Plex 目录。' : '登录后同步到独立的 $_brand 目录。'),
      busy: _busy,
      actions: [
        SourceSheetButton(
          label: _settings ? '上一步' : '取消',
          outlined: true,
          onPressed: _busy
              ? null
              : () {
                  if (_settings) {
                    setState(() => _settings = false);
                  } else {
                    Navigator.pop(context);
                  }
                },
        ),
        SourceSheetButton(
          label: _busy
              ? '$_brand 连接中'
              : _settings || reauth
              ? (reauth ? (_plex ? '连接' : '登录') : (_plex ? '连接并同步' : '登录并同步'))
              : '下一步',
          prominent: true,
          onPressed: _busy
              ? null
              : () {
                  if (!_settings && !reauth) {
                    try {
                      embyServerUri(_server.text);
                      if (_plex && _token.text.trim().isEmpty) {
                        throw const SourceFailure('请输入 Plex Token。');
                      }
                      if (!_plex && _username.text.trim().isEmpty) {
                        throw const SourceFailure('请输入用户名。');
                      }
                      setState(() {
                        _settings = true;
                        _error = null;
                      });
                    } catch (e) {
                      setState(() => _error = sourceErrorMessage(e));
                    }
                  } else {
                    unawaited(_submit());
                  }
                },
        ),
      ],
      children: [
        if (!reauth) ...[
          SourceWizardSteps(
            key: const ValueKey('remote-source-wizard-steps'),
            current: _settings ? 2 : 1,
          ),
          const SizedBox(height: 14),
        ],
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: !_settings
              ? AppSheetSection(
                  key: const ValueKey('remote-source-connect-step'),
                  title: '服务器连接',
                  subtitle: _plex ? '填写服务器地址和 Plex Token。' : '填写服务器地址和登录凭据。',
                  icon: const Icon(Icons.dns_outlined, size: 17),
                  colors: palette.section,
                  child: Column(
                    spacing: 12,
                    children: [
                      if (!reauth)
                        _field(
                          _server,
                          _plex
                              ? '服务器地址，例如 http://192.168.1.20:32400'
                              : '服务器地址，例如 http://192.168.1.20:8096',
                          '${_kind.name}-server',
                        ),
                      if (_plex)
                        _field(
                          _token,
                          'Plex Token',
                          'plex-token',
                          password: true,
                        )
                      else ...[
                        _field(_username, '用户名', '${_kind.name}-username'),
                        _field(
                          _password,
                          '密码',
                          '${_kind.name}-password',
                          password: true,
                        ),
                      ],
                    ],
                  ),
                )
              : AppSheetSection(
                  key: const ValueKey('remote-source-settings-step'),
                  title: '参与策略',
                  subtitle: '控制此媒体源是否参与元数据拉取、健康检查和同步。',
                  icon: const Icon(Icons.tune, size: 17),
                  colors: palette.section,
                  child: IgnorePointer(
                    ignoring: _busy,
                    child: RemotePolicyPanel(
                      metadata: _metadata,
                      health: _health,
                      trace: _trace,
                      onMetadata: (v) => setState(() => _metadata = v),
                      onHealth: (v) => setState(() => _health = v),
                      onTrace: (v) => setState(() => _trace = v),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 14),
        Text(
          _plex ? 'Plex Token 仅保存在本机安全存储中。' : '凭据仅保存在本机安全存储中。',
          style: TextStyle(fontSize: 12, color: palette.secondary),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          _SheetStatusNotice(message: '正在连接 $_brand，请稍候…'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          _SheetStatusNotice(message: _error!, error: true),
        ],
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint,
    String key, {
    bool password = false,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy,
    obscureText: password,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      hintText: hint,
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class RemotePolicyPanel extends StatelessWidget {
  const RemotePolicyPanel({
    required this.metadata,
    required this.health,
    required this.trace,
    required this.onMetadata,
    required this.onHealth,
    required this.onTrace,
    super.key,
  });
  final bool metadata, health;
  final RemoteTraceSyncMode trace;
  final ValueChanged<bool> onMetadata, onHealth;
  final ValueChanged<RemoteTraceSyncMode> onTrace;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      SourcePolicySwitch(
        label: '参与元数据拉取',
        value: metadata,
        onChanged: onMetadata,
      ),
      SourcePolicySwitch(label: '参与健康检查', value: health, onChanged: onHealth),
      const SizedBox(height: 2),
      const Text(
        '痕迹数据同步',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      DropdownButtonFormField<RemoteTraceSyncMode>(
        initialValue: trace,
        isExpanded: true,
        decoration: InputDecoration(
          filled: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          for (final mode in RemoteTraceSyncMode.values)
            DropdownMenuItem(
              value: mode,
              child: Text(switch (mode) {
                RemoteTraceSyncMode.bidirectional => '双向同步',
                RemoteTraceSyncMode.importOnly => '仅从服务器导入',
                RemoteTraceSyncMode.disabled => '关闭同步',
              }),
            ),
        ],
        onChanged: (v) {
          if (v != null) onTrace(v);
        },
      ),
    ],
  );
}

class EmbyLibrarySheet extends StatefulWidget {
  const EmbyLibrarySheet({
    required this.source,
    required this.repository,
    super.key,
  });
  final MediaSource source;
  final EmbyConnectionRepository repository;
  @override
  State<EmbyLibrarySheet> createState() => _EmbyLibrarySheetState();
}

class _EmbyLibrarySheetState extends State<EmbyLibrarySheet> {
  late bool _all, _metadata, _health;
  late RemoteTraceSyncMode _trace;
  late Set<String> _selected;
  List<EmbyLibrary> _libraries = const [];
  bool _loading = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final options = widget.source.options;
    _selected = options.selectedEmbyLibraryIDs.toSet();
    _all = _selected.isEmpty;
    _metadata = options.includeInMetadataFetch;
    _health = options.includeInHealthCheck;
    _trace = options.remoteTraceSyncMode;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final libraries = await widget.repository.libraries(widget.source.id);
      if (mounted) {
        setState(() {
          _libraries = libraries
              .where(
                (library) => library.collectionType?.toLowerCase() != 'photos',
              )
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = sourceErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _scopeChanged {
    final previous = widget.source.options.selectedEmbyLibraryIDs.toSet();
    final next = _all ? <String>{} : _selected;
    return previous.length != next.length || !previous.containsAll(next);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      await widget.repository.selectLibraries(
        widget.source.id,
        all: _all,
        selected: _selected,
        metadata: _metadata,
        health: _health,
        trace: _trace,
      );
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context, _scopeChanged);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = sourceErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return EmbySheetFrame(
      title: '媒体源设置',
      subtitle: widget.source.name,
      busy: _saving,
      actions: [
        SourceSheetButton(
          label: '取消',
          outlined: true,
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        SourceSheetButton(
          label: _saving
              ? '保存中'
              : _scopeChanged
              ? '保存并同步'
              : '保存设置',
          prominent: true,
          onPressed: _saving || (!_all && _selected.isEmpty) ? null : _save,
        ),
      ],
      children: [
        AppSheetSection(
          title: '同步库',
          subtitle: _all ? '全部媒体库' : '已选 ${_selected.length} 个库',
          icon: const Icon(Icons.dns_outlined, size: 17),
          colors: palette.section,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              _RemoteLibraryChoiceRow(
                key: const ValueKey('remote-library-all'),
                selected: _all,
                enabled: !_saving,
                title: '同步全部媒体库',
                subtitle: '服务器新增库也会自动纳入。',
                radio: true,
                onTap: () => setState(() => _all = true),
              ),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _buildLibraryList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppSheetSection(
          title: '参与策略',
          subtitle: '控制此媒体源是否参与元数据拉取、健康检查和同步。',
          icon: const Icon(Icons.tune, size: 17),
          colors: palette.section,
          child: IgnorePointer(
            ignoring: _saving,
            child: RemotePolicyPanel(
              metadata: _metadata,
              health: _health,
              trace: _trace,
              onMetadata: (v) => setState(() => _metadata = v),
              onHealth: (v) => setState(() => _health = v),
              onTrace: (v) => setState(() => _trace = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryList() {
    if (_loading) {
      return const _RemoteLibraryLoadingState(
        key: ValueKey('remote-libraries-loading'),
      );
    }
    if (_error case final error?) {
      return _SheetStatusNotice(
        key: const ValueKey('remote-libraries-error'),
        message: '媒体库列表读取失败\n$error',
        error: true,
        actionLabel: '重试',
        onAction: _saving ? null : _load,
      );
    }
    if (_libraries.isEmpty) {
      return const _RemoteLibrariesEmptyState(
        key: ValueKey('remote-libraries-empty'),
      );
    }
    return Column(
      key: const ValueKey('remote-libraries-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _libraries.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _RemoteLibraryChoiceRow(
            key: ValueKey('remote-library-${_libraries[index].id}'),
            selected: !_all && _selected.contains(_libraries[index].id),
            enabled: !_saving,
            title: _libraries[index].name,
            subtitle: _libraries[index].typeLabel,
            leadingIcon: _remoteLibraryIcon(_libraries[index]),
            onTap: () => setState(() {
              _all = false;
              if (!_selected.add(_libraries[index].id)) {
                _selected.remove(_libraries[index].id);
              }
            }),
          ),
        ],
      ],
    );
  }

  IconData _remoteLibraryIcon(EmbyLibrary library) =>
      switch (library.collectionType?.toLowerCase()) {
        'movies' => Icons.movie_outlined,
        'tvshows' => Icons.tv_outlined,
        'music' => Icons.music_note_rounded,
        'boxsets' => Icons.video_library_outlined,
        'playlists' => Icons.playlist_play_rounded,
        'homevideos' => Icons.video_file_outlined,
        'livetv' => Icons.live_tv_outlined,
        _ => Icons.view_module_outlined,
      };
}

class _RemoteLibraryChoiceRow extends StatefulWidget {
  const _RemoteLibraryChoiceRow({
    required this.selected,
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.leadingIcon,
    this.radio = false,
    super.key,
  });

  final bool selected;
  final bool enabled;
  final bool radio;
  final String title;
  final String subtitle;
  final IconData? leadingIcon;
  final VoidCallback onTap;

  @override
  State<_RemoteLibraryChoiceRow> createState() =>
      _RemoteLibraryChoiceRowState();
}

class _RemoteLibraryChoiceRowState extends State<_RemoteLibraryChoiceRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final active = widget.enabled && (_hovered || _focused);
    final indicator = widget.radio
        ? widget.selected
              ? Icons.check_circle_rounded
              : Icons.circle_outlined
        : widget.selected
        ? Icons.check_box_rounded
        : Icons.check_box_outline_blank_rounded;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduceMotion ? 0 : 140),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: widget.selected
              ? palette.iconChip
              : active
              ? Color.lerp(palette.staticSurface, palette.iconChip, .12)
              : palette.staticSurface,
          borderRadius: BorderRadius.circular(widget.radio ? 14 : 12),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radio ? 14 : 12),
          border: Border.all(
            color: _focused
                ? palette.selectedTint.withValues(alpha: .72)
                : widget.selected
                ? palette.selectedTint.withValues(alpha: .42)
                : active
                ? palette.selectedTint.withValues(alpha: .18)
                : palette.border,
            width: _focused ? 1.4 : .94,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(widget.radio ? 14 : 12),
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Padding(
              padding: widget.radio
                  ? const EdgeInsets.all(12)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    indicator,
                    size: 18,
                    color: widget.selected
                        ? palette.selectedTint
                        : palette.secondary,
                  ),
                  if (widget.leadingIcon != null) ...[
                    const SizedBox(width: 10),
                    Icon(
                      widget.leadingIcon,
                      size: 20,
                      color: palette.selectedTint.withValues(alpha: .88),
                    ),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteLibraryLoadingState extends StatelessWidget {
  const _RemoteLibraryLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 130),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.staticSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              value: .72,
              strokeWidth: 2,
              color: palette.selectedTint,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '正在读取服务器媒体库…',
            style: TextStyle(fontSize: 12, color: palette.secondary),
          ),
        ],
      ),
    );
  }
}

class _RemoteLibrariesEmptyState extends StatelessWidget {
  const _RemoteLibrariesEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 150),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.staticSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.layers_clear_outlined,
            size: 32,
            color: palette.selectedTint.withValues(alpha: .88),
          ),
          const SizedBox(height: 8),
          const Text(
            '服务器未返回媒体库',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '可以保持同步全部，稍后再重新打开设置。',
            style: TextStyle(fontSize: 12, color: palette.secondary),
          ),
        ],
      ),
    );
  }
}

class _SheetStatusNotice extends StatelessWidget {
  const _SheetStatusNotice({
    required this.message,
    this.error = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SourceSheetPalette(theme.brightness == Brightness.dark);
    final tint = error ? theme.colorScheme.error : palette.selectedTint;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .065),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: .14)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SourceLineIcon(
                error ? SourceGlyph.warning : SourceGlyph.info,
                size: 13,
                color: tint,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: error ? tint : palette.secondary,
                  ),
                ),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
