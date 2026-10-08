import 'package:flutter/material.dart';

import '../../../domain/media_source.dart';
import '../../../domain/source_media_type.dart';
import '../../../domain/source_settings_draft.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import 'media_type_grid_picker.dart';
import 'source_behavior_settings_panel.dart';

/// SourcesView.SourceSettingsSheet's local form. Return a draft after dismiss;
/// the page's controller owns persistence, notifications and scan coordination.
class SourceSettingsSheet extends StatefulWidget {
  const SourceSettingsSheet({required this.source, super.key});
  final MediaSource source;
  @override
  State<SourceSettingsSheet> createState() => _SourceSettingsSheetState();
}

class _SourceSettingsSheetState extends State<SourceSettingsSheet> {
  late SourceMediaType _mediaType;
  late SourceSettingsDraft _initial;
  bool _saving = false;
  late bool _includeInHealthCheck;

  @override
  void initState() {
    super.initState();
    _initial = SourceSettingsDraft.fromSource(widget.source);
    _mediaType = _initial.mediaType;
    _includeInHealthCheck = _initial.includeInHealthCheck;
  }

  void _save() {
    if (_saving) return;
    setState(() => _saving = true);
    Navigator.pop(
      context,
      SourceSettingsDraft(
        mediaType: _mediaType,
        includeInMetadataFetch: _initial.includeInMetadataFetch,
        includeInHealthCheck: _includeInHealthCheck,
        preferMetadataWriteToSource: _initial.preferMetadataWriteToSource,
      ),
    );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppSheetMetrics.wideWidth,
            maxHeight: 700,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSheetHeader(
                  title: '媒体源设置',
                  subtitle: _mediaType.label,
                  icon: const OverflowBox(
                    minWidth: 56,
                    maxWidth: 56,
                    minHeight: 56,
                    maxHeight: 56,
                    child: SourceTitleIcon(kind: SourceTitleIconKind.settings),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 520),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppSheetSection(
                              title: '分类',
                              subtitle: '决定内容归入哪个媒体库分类。',
                              icon: const SourceLineIcon(
                                SourceGlyph.grid,
                                size: 17,
                              ),
                              colors: palette.section,
                              child: MediaTypeGridPicker(
                                selection: _mediaType,
                                onChanged: _saving
                                    ? null
                                    : (type) =>
                                          setState(() => _mediaType = type),
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppSheetSection(
                              title: '参与策略',
                              subtitle: '控制此媒体源是否参与元数据拉取、健康检查和同步。',
                              icon: const SourceLineIcon(
                                SourceGlyph.sliders,
                                size: 17,
                              ),
                              colors: palette.section,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SourceBehaviorSettingsPanel(
                                    mediaType: _mediaType,
                                    includeInMetadataFetch:
                                        _initial.includeInMetadataFetch,
                                    includeInHealthCheck: _includeInHealthCheck,
                                    onHealthChanged: _saving
                                        ? null
                                        : (value) => setState(
                                            () => _includeInHealthCheck = value,
                                          ),
                                    preferMetadataWriteToSource:
                                        _initial.preferMetadataWriteToSource,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '元数据拉取和写回暂不可用。',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: palette.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppInfoNote(
                              text: '保存只更新 ReelNest 内部媒体源设置；不会移动、删除或重命名媒体文件。',
                              // Vivid's checkmark.shield mapping; the original
                              // note uses SF Symbols, whose asset is pending.
                              icon: SourceLineIcon(
                                SourceGlyph.checkCircle,
                                size: 11,
                                color: palette.selectedTint.withValues(
                                  alpha: .88,
                                ),
                              ),
                              surface: palette.staticSurface,
                              border: palette.border,
                              iconTint: palette.selectedTint,
                              textColor: palette.secondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppSheetActionFooter(
                  panelBorder: palette.panelBorder,
                  solarLightTint: palette.solar,
                  actions: [
                    SourceSheetButton(
                      label: '取消',
                      outlined: true,
                      onPressed: _saving ? null : () => Navigator.pop(context),
                    ),
                    SourceSheetButton(
                      label: _saving ? '保存中' : '保存设置',
                      prominent: true,
                      onPressed: _saving ? null : _save,
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
