import 'package:flutter/material.dart';

import '../../../domain/media_source.dart';
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('媒体源别名'),
      content: SizedBox(
        width: 380,
        child: TextField(
          key: const ValueKey('source-alias-input'),
          controller: _controller,
          autofocus: true,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: '别名',
            helperText: '仅修改 ReelNest 中的显示名称，不修改服务器或文件夹名称。',
            helperMaxLines: 2,
            errorText: _error,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _saving || _controller.text.trim().isEmpty ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
  );
}
