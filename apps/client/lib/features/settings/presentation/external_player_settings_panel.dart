import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_menu_control.dart';
import '../../../ui/widgets/settings_surfaces.dart';
import '../../playback/application/external_playback_providers.dart';
import '../../playback/domain/external_player_settings.dart';

/// SettingsView.videoPlaybackSettings launch-mode controls.
///
/// System file association is deliberately absent from this panel: the
/// current desktop batch only chooses how ReelNest starts video playback.
class ExternalPlayerSettingsPanel extends ConsumerStatefulWidget {
  const ExternalPlayerSettingsPanel({super.key});

  @override
  ConsumerState<ExternalPlayerSettingsPanel> createState() =>
      _ExternalPlayerSettingsPanelState();
}

class _ExternalPlayerSettingsPanelState
    extends ConsumerState<ExternalPlayerSettingsPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _change(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is SourceFailure ? error.message : '外部播放器设置保存失败，请重试。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectApplication() async {
    final groups = Platform.isWindows
        ? const [
            XTypeGroup(label: '播放器程序', extensions: ['exe']),
          ]
        : Platform.isMacOS
        ? const [
            XTypeGroup(label: '播放器应用', extensions: ['app']),
          ]
        : const <XTypeGroup>[];
    try {
      final application = await openFile(acceptedTypeGroups: groups);
      if (application == null || !mounted) return;
      await _change(
        () => ref
            .read(externalPlayerSettingsProvider.notifier)
            .selectApplication(application.path),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is SourceFailure ? error.message : '无法选择播放器应用，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(externalPlayerSettingsProvider);
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return asyncSettings.when(
      loading: () => const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => AppSettingsNotice(
        message: _error ?? '外部播放器设置已损坏，请重置后重新选择播放器。',
        error: true,
        actionLabel: _busy ? '正在重置…' : '重置播放器设置',
        onAction: _busy
            ? null
            : () => _change(
                () => ref
                    .read(externalPlayerSettingsProvider.notifier)
                    .save(const ExternalPlayerSettings()),
              ),
      ),
      data: (settings) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSettingsSubsectionHeader(
            title: '启动方式',
            icon: Icons.ondemand_video_outlined,
          ),
          const SizedBox(height: 12),
          AppSettingsRow(
            title: '视频播放器',
            subtitle: '选择内置播放器或交给系统播放器打开',
            icon: Icons.play_circle_outline_rounded,
            trailing: AppMenuControl<ExternalPlayerMode>(
              key: const ValueKey('external-player-mode'),
              value: settings.mode,
              label: settings.mode == ExternalPlayerMode.builtIn ? '内置' : '系统',
              values: ExternalPlayerMode.values,
              itemLabel: (mode) =>
                  mode == ExternalPlayerMode.builtIn ? '内置' : '系统',
              enabled: !_busy,
              busy: _busy,
              tooltip: '视频播放器',
              onSelected: (mode) => _change(
                () => ref
                    .read(externalPlayerSettingsProvider.notifier)
                    .setMode(mode),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: settings.mode == ExternalPlayerMode.external
                ? Column(
                    key: const ValueKey('external-player-application-row'),
                    children: [
                      const AppSettingsDivider(),
                      AppSettingsRow(
                        title: '视频系统播放器',
                        subtitle: '留空时使用系统默认应用',
                        icon: Icons.apps_rounded,
                        trailing: _ApplicationControl(
                          path: settings.applicationPath,
                          busy: _busy,
                          onUseSystem: settings.applicationPath == null
                              ? null
                              : () => _change(
                                  () => ref
                                      .read(
                                        externalPlayerSettingsProvider.notifier,
                                      )
                                      .selectApplication(null),
                                ),
                          onChoose: _selectApplication,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          const AppSettingsDescription(
            text: '选“内置”使用 ReelNest 播放器；选“系统”交给系统默认或指定的视频播放器打开。播放窗口中的显式“用系统播放器打开”不会改变这里的默认选择。',
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            AppSettingsNotice(message: _error!, error: true),
          ],
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: palette.selectedTint,
                backgroundColor: palette.control,
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplicationControl extends StatelessWidget {
  const _ApplicationControl({
    required this.path,
    required this.busy,
    required this.onUseSystem,
    required this.onChoose,
  });

  final String? path;
  final bool busy;
  final VoidCallback? onUseSystem;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 460),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = Wrap(
          spacing: 7,
          runSpacing: 7,
          alignment: WrapAlignment.end,
          children: [
            if (path != null)
              TextButton(
                key: const ValueKey('use-system-video-player'),
                onPressed: busy ? null : onUseSystem,
                child: const Text('系统默认'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('choose-external-video-player'),
              onPressed: busy ? null : onChoose,
              icon: const Icon(Icons.apps_rounded, size: 16),
              label: const Text('选择…'),
            ),
          ],
        );
        if (constraints.maxWidth < 390) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSettingsPathText(text: path ?? '系统默认'),
              const SizedBox(height: 8),
              actions,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: AppSettingsPathText(text: path ?? '系统默认')),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    ),
  );
}
