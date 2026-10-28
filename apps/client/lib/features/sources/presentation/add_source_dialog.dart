import 'package:flutter/material.dart';

import '../../../domain/source_media_type.dart';
import '../../../platform/directory_access.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/source_providers.dart';
import 'local_source_configuration.dart';
import 'source_behavior_settings_panel.dart';

class SourceDraft {
  const SourceDraft({
    required this.locations,
    required this.mediaType,
    required this.autoScan,
    required this.includeInMetadataFetch,
    required this.includeInHealthCheck,
    required this.preferMetadataWriteToSource,
    this.backToSourceSelection = false,
  });

  const SourceDraft.back()
    : locations = const [],
      mediaType = SourceMediaType.auto,
      autoScan = true,
      includeInMetadataFetch = true,
      includeInHealthCheck = true,
      preferMetadataWriteToSource = false,
      backToSourceSelection = true;

  final List<String> locations;
  final SourceMediaType mediaType;
  final bool autoScan;
  final bool includeInMetadataFetch;
  final bool includeInHealthCheck;
  final bool preferMetadataWriteToSource;
  final bool backToSourceSelection;
}

enum _LocalSourceWizardStep { configure, settings }

/// Hosts the migrated local configuration body while the original source and
/// policy steps are still being migrated. This is not the completed wizard.
class AddSourceDialog extends StatefulWidget {
  const AddSourceDialog({required this.access, super.key});
  final DirectoryAccess access;

  @override
  State<AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<AddSourceDialog> {
  List<String> _locations = const [];
  SourceMediaType _mediaType = SourceMediaType.auto;
  _LocalSourceWizardStep _step = _LocalSourceWizardStep.configure;
  bool _autoScan = true;
  bool _includeInMetadataFetch = true;
  bool _includeInHealthCheck = true;
  bool _preferMetadataWriteToSource = false;
  String? _error;
  bool _choosing = false;

  Future<void> _choose() async {
    setState(() {
      _choosing = true;
      _error = null;
    });
    try {
      final locations = await widget.access.chooseMany();
      // NSOpenPanel cancellation leaves the previous selection intact.
      if (!mounted || locations.isEmpty) return;
      setState(() => _locations = List.unmodifiable(locations.toSet()));
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  void _next() {
    if (_step == _LocalSourceWizardStep.configure) {
      setState(() {
        _step = _LocalSourceWizardStep.settings;
        _error = null;
      });
      return;
    }
    Navigator.pop(
      context,
      SourceDraft(
        locations: List<String>.unmodifiable(_locations),
        mediaType: _mediaType,
        autoScan: _autoScan,
        includeInMetadataFetch: _includeInMetadataFetch,
        includeInHealthCheck: _includeInHealthCheck,
        preferMetadataWriteToSource: _preferMetadataWriteToSource,
      ),
    );
  }

  void _back() {
    if (_step == _LocalSourceWizardStep.settings) {
      setState(() {
        _step = _LocalSourceWizardStep.configure;
        _error = null;
      });
    } else {
      Navigator.pop(context, const SourceDraft.back());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          onSurface: palette.text,
          onSurfaceVariant: palette.secondary,
        ),
      ),
      child: Dialog(
        backgroundColor: palette.page,
        elevation: 0,
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSheetMetrics.wideWidth,
            maxHeight: 680,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSheetHeader(
                  title: '添加媒体源',
                  subtitle: _step == _LocalSourceWizardStep.configure
                      ? '选择文件夹并指定分类。'
                      : '确认扫描、健康检查和元数据策略。',
                  icon: const OverflowBox(
                    maxWidth: 56,
                    maxHeight: 56,
                    child: SourceTitleIcon(),
                  ),
                ),
                const SizedBox(height: 16),
                _LocalSourceWizardSteps(
                  current: _step == _LocalSourceWizardStep.configure ? 1 : 2,
                  palette: palette,
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 460),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        child: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _step == _LocalSourceWizardStep.configure
                              ? LocalSourceConfiguration(
                                  key: const ValueKey(
                                    'local-source-configure-step',
                                  ),
                                  locations: _locations,
                                  mediaType: _mediaType,
                                  onChoose:
                                      _choosing || !widget.access.supported
                                      ? null
                                      : _choose,
                                  onMediaTypeChanged: _choosing
                                      ? null
                                      : (type) =>
                                            setState(() => _mediaType = type),
                                )
                              : _LocalSourcePolicyStep(
                                  key: const ValueKey(
                                    'local-source-settings-step',
                                  ),
                                  mediaType: _mediaType,
                                  autoScan: _autoScan,
                                  includeInMetadataFetch:
                                      _includeInMetadataFetch,
                                  includeInHealthCheck: _includeInHealthCheck,
                                  preferMetadataWriteToSource:
                                      _preferMetadataWriteToSource,
                                  enabled: !_choosing,
                                  onAutoScanChanged: (value) =>
                                      setState(() => _autoScan = value),
                                  onMetadataChanged: (value) => setState(() {
                                    _includeInMetadataFetch = value;
                                    if (!value) {
                                      _preferMetadataWriteToSource = false;
                                    }
                                  }),
                                  onHealthChanged: (value) => setState(
                                    () => _includeInHealthCheck = value,
                                  ),
                                  onWriteChanged: (value) => setState(
                                    () => _preferMetadataWriteToSource = value,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withValues(alpha: .065),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: .14),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SourceLineIcon(
                          SourceGlyph.warning,
                          size: 14,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!widget.access.supported)
                  Text(widget.access.unavailableReason),
                const SizedBox(height: 16),
                AppSheetActionFooter(
                  panelBorder: palette.panelBorder,
                  solarLightTint: palette.solar,
                  actions: [
                    SourceSheetButton(
                      label: '取消',
                      outlined: true,
                      onPressed: _choosing
                          ? null
                          : () => Navigator.pop(context),
                    ),
                    SourceSheetButton(
                      label: '上一步',
                      outlined: true,
                      onPressed: _choosing ? null : _back,
                    ),
                    SourceSheetButton(
                      label: _step == _LocalSourceWizardStep.configure
                          ? '下一步'
                          : '添加并扫描',
                      prominent: true,
                      horizontalPadding: 20,
                      icon: SourceLineIcon(
                        _step == _LocalSourceWizardStep.configure
                            ? SourceGlyph.chevronRight
                            : SourceGlyph.folder,
                        size: 13,
                      ),
                      onPressed: _choosing || _locations.isEmpty ? null : _next,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalSourcePolicyStep extends StatelessWidget {
  const _LocalSourcePolicyStep({
    required this.mediaType,
    required this.autoScan,
    required this.includeInMetadataFetch,
    required this.includeInHealthCheck,
    required this.preferMetadataWriteToSource,
    required this.enabled,
    required this.onAutoScanChanged,
    required this.onMetadataChanged,
    required this.onHealthChanged,
    required this.onWriteChanged,
    super.key,
  });

  final SourceMediaType mediaType;
  final bool autoScan;
  final bool includeInMetadataFetch;
  final bool includeInHealthCheck;
  final bool preferMetadataWriteToSource;
  final bool enabled;
  final ValueChanged<bool> onAutoScanChanged;
  final ValueChanged<bool> onMetadataChanged;
  final ValueChanged<bool> onHealthChanged;
  final ValueChanged<bool> onWriteChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Column(
      key: const ValueKey('local-source-policy-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetSection(
          title: '参与策略',
          subtitle: '控制此媒体源是否参与自动扫描、元数据拉取和健康检查。',
          icon: const SourceLineIcon(SourceGlyph.sliders, size: 17),
          colors: palette.section,
          child: SourceBehaviorSettingsPanel(
            mediaType: mediaType,
            autoScan: autoScan,
            includeInMetadataFetch: includeInMetadataFetch,
            includeInHealthCheck: includeInHealthCheck,
            preferMetadataWriteToSource: preferMetadataWriteToSource,
            onAutoScanChanged: enabled ? onAutoScanChanged : null,
            onMetadataChanged: enabled ? onMetadataChanged : null,
            onHealthChanged: enabled ? onHealthChanged : null,
            onWriteChanged: enabled ? onWriteChanged : null,
          ),
        ),
        const SizedBox(height: 14),
        AppInfoNote(
          text: '这些设置会随目录媒体源一起保存。“元数据优先写入源目录”仅对已迁移的本地电影、电视剧和动漫，在片库健康“一键补充”时尝试写回 NFO；普通单项、批量或定时匹配不会写入媒体目录。',
          icon: SourceLineIcon(
            SourceGlyph.sliders,
            size: 11,
            color: palette.selectedTint.withValues(alpha: .88),
          ),
          surface: palette.staticSurface,
          border: palette.border,
          iconTint: palette.selectedTint,
          textColor: palette.secondary,
        ),
      ],
    );
  }
}

class _LocalSourceWizardSteps extends StatelessWidget {
  const _LocalSourceWizardSteps({required this.current, required this.palette});

  final int current;
  final SourceSheetPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('local-source-wizard-steps'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: palette.staticSurface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border),
    ),
    child: Row(
      children: [
        for (var index = 0; index < 3; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: palette.text.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          _WizardStepLabel(
            index: index,
            current: current,
            label: const ['来源', '连接', '设置'][index],
            palette: palette,
          ),
        ],
      ],
    ),
  );
}

class _WizardStepLabel extends StatelessWidget {
  const _WizardStepLabel({
    required this.index,
    required this.current,
    required this.label,
    required this.palette,
  });

  final int index;
  final int current;
  final String label;
  final SourceSheetPalette palette;

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    final completed = index < current;
    final tint = active || completed ? palette.selectedTint : palette.secondary;
    return SizedBox(
      width: 92,
      child: Row(
        mainAxisAlignment: index == 0
            ? MainAxisAlignment.start
            : index == 2
            ? MainAxisAlignment.end
            : MainAxisAlignment.center,
        children: [
          if (completed)
            SourceLineIcon(
              SourceGlyph.checkCircle,
              size: 16,
              color: tint,
              lineWidth: 2.1,
            )
          else
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? tint : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: tint, width: 1.4),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: active ? Colors.white : tint,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: active ? palette.text : palette.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
