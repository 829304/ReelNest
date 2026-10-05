import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../domain/media_source.dart';
import '../../../platform/directory_access.dart';
import '../application/source_providers.dart';

typedef SourceDraft = ({
  MediaSourceKind kind,
  String name,
  String location,
  bool recursive,
  bool ignoreHidden,
});

class AddSourceDialog extends StatefulWidget {
  const AddSourceDialog({required this.access, super.key});
  final DirectoryAccess access;

  @override
  State<AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<AddSourceDialog> {
  final _name = TextEditingController();
  MediaSourceKind _kind = MediaSourceKind.localFolder;
  String? _location;
  String? _error;
  bool _choosing = false;
  bool _recursive = true;
  bool _ignoreHidden = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() {
      _choosing = true;
      _error = null;
    });
    try {
      final location = await widget.access.choose();
      if (!mounted || location == null) return;
      setState(() {
        _location = location;
        if (_name.text.isEmpty) {
          _name.text = p.basename(location).isEmpty
              ? location
              : p.basename(location);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = sourceErrorMessage(error));
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加媒体源'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<MediaSourceKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '来源类型'),
              items: MediaSourceKind.values
                  .where((k) => k.isFileSource)
                  .map(
                    (kind) =>
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                  )
                  .toList(),
              onChanged: _choosing
                  ? null
                  : (value) => setState(() => _kind = value!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: '来源名称'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _choosing ? null : _choose,
              icon: const Icon(Icons.folder_open),
              label: Text(_choosing ? '正在选择…' : '选择目录'),
            ),
            if (_location != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_location!),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含子目录'),
              value: _recursive,
              onChanged: (value) => setState(() => _recursive = value!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('忽略点号开头的文件与目录'),
              value: _ignoreHidden,
              onChanged: (value) => setState(() => _ignoreHidden = value!),
            ),
            const Text('移动硬盘和 NAS 请先在系统中挂载，再选择对应目录。'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _choosing ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _choosing || _location == null
            ? null
            : () {
                if (_name.text.trim().isEmpty) {
                  setState(() => _error = '请输入来源名称。');
                  return;
                }
                Navigator.pop(context, (
                  kind: _kind,
                  name: _name.text.trim(),
                  location: _location!,
                  recursive: _recursive,
                  ignoreHidden: _ignoreHidden,
                ));
              },
        child: const Text('添加并扫描'),
      ),
    ],
  );
}
