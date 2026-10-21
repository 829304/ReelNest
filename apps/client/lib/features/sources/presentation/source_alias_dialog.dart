import 'package:flutter/material.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/source_providers.dart';
import '../data/source_repository.dart';

Future<bool?> showSourceAliasDialog(
  BuildContext context, {
  required MediaSource source,
  required SourceRepository repository,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _SourceAliasDialog(source: source, repository: repository),
);

/// ContentView.EmbySourceRenameSheet: one local display name shared by the
/// sidebar and source list. Keep the editor open when persistence fails.
class _SourceAliasDialog extends StatefulWidget {
  const _SourceAliasDialog({required this.source, required this.repository});
  final MediaSource source;
  final SourceRepository repository;

  @override
  State<_SourceAliasDialog> createState() => _SourceAliasDialogState();
}

class _SourceAliasDialogState extends State<_SourceAliasDialog> {
  late final _controller = TextEditingController(text: widget.source.name);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (_saving || name.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateSettings(widget.source.id, name: name);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = sourceErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SourceSheetPalette(theme.brightness == Brightness.dark);
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        key: const ValueKey('source-alias-dialog'),
        backgroundColor: palette.page,
        elevation: 0,
        insetPadding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSheetHeader(
                  title: '媒体源别名',
                  subtitle: widget.source.name,
                  icon: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.iconChip,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SourceLineIcon(
                      SourceGlyph.sliders,
                      size: 22,
                      color: palette.selectedTint,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AppSheetSection(
                  title: '显示名称',
                  subtitle: '只影响 ReelNest 内的显示。',
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  colors: palette.section,
                  child: TextField(
                    key: const ValueKey('source-alias-input'),
                    controller: _controller,
                    autofocus: true,
                    enabled: !_saving,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入媒体源别名',
                      helperText: '不会修改服务器名称或文件夹名称。',
                      helperMaxLines: 2,
                      errorText: _error,
                      errorMaxLines: 3,
                      filled: true,
                      fillColor: palette.control.withValues(alpha: .72),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(height: 18),
                AppSheetActionFooter(
                  panelBorder: palette.panelBorder,
                  solarLightTint: palette.solar,
                  actions: [
                    SourceSheetButton(
                      label: '取消',
                      outlined: true,
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                    SourceSheetButton(
                      label: _saving ? '保存中…' : '保存',
                      prominent: true,
                      onPressed: _saving || _controller.text.trim().isEmpty
                          ? null
                          : _save,
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
