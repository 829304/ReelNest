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

/// The migrated source-selection step; remaining connector cards are deferred.
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
        const _Steps(0),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final kind in [
              MediaSourceKind.localFolder,
              MediaSourceKind.emby,
            ])
              SizedBox(
                width: 264,
                child: InkWell(
                  onTap: () => setState(() => _kind = kind),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(minHeight: 88),
                    decoration: BoxDecoration(
                      color: _kind == kind
                          ? palette.iconChip
                          : palette.staticSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _kind == kind
                            ? palette.selectedTint
                            : palette.border,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 11,
                      children: [
                        SizedBox(
                          width: 26,
                          child: kind == MediaSourceKind.emby
                              ? Image.asset(
                                  'assets/brands/emby.png',
                                  width: 19,
                                  height: 19,
                                  fit: BoxFit.contain,
                                  excludeFromSemantics: true,
                                )
                              : Icon(
                                  Icons.folder_outlined,
                                  size: 19,
                                  color: palette.selectedTint,
                                ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              Text(
                                kind.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                kind.isFileSource
                                    ? '本地文件夹、移动硬盘与已挂载 NAS'
                                    : '服务器地址与账号登录',
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
          ],
        ),
      ],
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.current);
  final int current;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: SourceSheetPalette(Theme.of(context).brightness == Brightness.dark)
          .staticSurface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (var n = 0; n < 3; n++) ...[
          if (n > 0)
            const Expanded(
              child: Divider(thickness: 2, indent: 8, endIndent: 8),
            ),
          SizedBox(
            width: 92,
            child: Row(
              spacing: 7,
              mainAxisAlignment: n == 0
                  ? MainAxisAlignment.start
                  : n == 2
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  n < current ? Icons.check_circle : Icons.radio_button_checked,
                  size: 16,
                  color: n <= current
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).disabledColor,
                ),
                Text(
                  ['来源', '连接', '设置'][n],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
  const EmbyConnectionSheet({required this.repository, this.source, super.key});
  final EmbyConnectionRepository repository;
  final MediaSource? source;
  @override
  State<EmbyConnectionSheet> createState() => _EmbyConnectionSheetState();
}

class _EmbyConnectionSheetState extends State<EmbyConnectionSheet> {
  final _server = TextEditingController(),
      _username = TextEditingController(),
      _password = TextEditingController();
  bool _busy = false, _settings = false, _metadata = true, _health = true;
  RemoteTraceSyncMode _trace = RemoteTraceSyncMode.bidirectional;
  String? _error;
  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
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
        await widget.repository.reauthenticate(
          source.id,
          _username.text,
          _password.text,
        );
        result = source;
      } else {
        result = await widget.repository.connect(
          _server.text,
          _username.text,
          _password.text,
          options: SourceOptions(
            autoScan: false,
            preferLocalArtwork: false,
            networkScrapingEnabled: false,
            screenshotFallbackEnabled: false,
            includeInMetadataFetch: _metadata,
            includeInHealthCheck: _health,
            remoteTraceSyncMode: _trace,
          ),
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
      title: reauth ? 'Emby 重新认证' : '添加媒体源',
      subtitle: _settings ? '确认扫描、健康检查和同步策略。' : '填写服务器地址和登录凭据。',
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
              ? 'Emby 连接中'
              : _settings || reauth
              ? (reauth ? '登录' : '登录并同步')
              : '下一步',
          prominent: true,
          onPressed: _busy
              ? null
              : () {
                  if (!_settings && !reauth) {
                    try {
                      embyServerUri(_server.text);
                      if (_username.text.trim().isEmpty) {
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
        if (!reauth) ...[_Steps(_settings ? 2 : 1), const SizedBox(height: 14)],
        if (!_settings)
          AppSheetSection(
            title: '服务器连接',
            subtitle: '填写服务器地址和登录凭据。',
            icon: const Icon(Icons.dns_outlined, size: 17),
            colors: palette.section,
            child: Column(
              spacing: 12,
              children: [
                if (!reauth)
                  _field(
                    _server,
                    '服务器地址，例如 http://192.168.1.20:8096',
                    'emby-server',
                  ),
                _field(_username, '用户名', 'emby-username'),
                _field(_password, '密码', 'emby-password', password: true),
              ],
            ),
          ),
        if (_settings)
          AppSheetSection(
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
        const SizedBox(height: 14),
        Text(
          '凭据仅保存在本机安全存储中。',
          style: TextStyle(fontSize: 12, color: palette.secondary),
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
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
      DropdownButton<RemoteTraceSyncMode>(
        value: trace,
        isExpanded: true,
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
      if (mounted) setState(() => _libraries = libraries);
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
              InkWell(
                onTap: _saving ? null : () => setState(() => _all = true),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    spacing: 10,
                    children: [
                      Icon(
                        _all ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Text(
                              '同步全部媒体库',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '服务器新增库也会自动纳入。',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('读取媒体库列表…'),
                ),
              if (_error != null) ...[
                const Text('媒体库列表读取失败'),
                Text(_error!),
                TextButton(
                  onPressed: _loading || _saving ? null : _load,
                  child: const Text('重试'),
                ),
              ],
              if (!_loading && _error == null && _libraries.isEmpty) ...[
                const Text('服务器未返回媒体库'),
                const Text('可以保持同步全部，稍后再重新打开设置。'),
              ],
              if (!_loading && _error == null)
                for (final library in _libraries)
                  InkWell(
                    onTap: _saving
                        ? null
                        : () => setState(() {
                            _all = false;
                            if (!_selected.add(library.id)) {
                              _selected.remove(library.id);
                            }
                          }),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: !_all && _selected.contains(library.id)
                            ? palette.iconChip
                            : palette.staticSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        spacing: 10,
                        children: [
                          Icon(
                            !_all && _selected.contains(library.id)
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 18,
                          ),
                          const Icon(Icons.video_library_outlined, size: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 2,
                              children: [
                                Text(
                                  library.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  library.typeLabel,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
}
