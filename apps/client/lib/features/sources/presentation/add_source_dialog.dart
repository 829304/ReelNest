import 'package:flutter/material.dart';

import '../../../domain/source_media_type.dart';
import '../../../platform/directory_access.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/source_providers.dart';
import 'local_source_configuration.dart';

typedef SourceDraft = ({List<String> locations, SourceMediaType mediaType});

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
            maxHeight: 680,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSheetHeader(
                  title: '添加媒体源',
                  subtitle: '选择文件夹并指定分类。',
                  icon: OverflowBox(
                    maxWidth: 56,
                    maxHeight: 56,
                    child: SourceTitleIcon(),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 460),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        child: LocalSourceConfiguration(
                          locations: _locations,
                          mediaType: _mediaType,
                          onChoose: _choosing || !widget.access.supported
                              ? null
                              : _choose,
                          onMediaTypeChanged: _choosing
                              ? null
                              : (type) => setState(() => _mediaType = type),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
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
                      label: '添加并扫描',
                      prominent: true,
                      horizontalPadding: 20,
                      icon: const SourceLineIcon(SourceGlyph.folder, size: 13),
                      onPressed: _choosing || _locations.isEmpty
                          ? null
                          : () => Navigator.pop(context, (
                              locations: List<String>.unmodifiable(_locations),
                              mediaType: _mediaType,
                            )),
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
