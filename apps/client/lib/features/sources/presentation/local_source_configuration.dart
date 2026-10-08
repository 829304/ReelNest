import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../domain/source_media_type.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_icons.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import 'media_type_grid_picker.dart';

/// SourcesView.localConfiguration: reusable as the local wizard connection step.
class LocalSourceConfiguration extends StatelessWidget {
  const LocalSourceConfiguration({
    required this.locations,
    required this.mediaType,
    required this.onChoose,
    required this.onMediaTypeChanged,
    super.key,
  });
  final List<String> locations;
  final SourceMediaType mediaType;
  final VoidCallback? onChoose;
  final ValueChanged<SourceMediaType>? onMediaTypeChanged;

  String _title(String path) =>
      p.basename(path).isEmpty ? path : p.basename(path);

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final summary = locations.isEmpty
        ? '尚未选择目录'
        : locations.length == 1
        ? _title(locations.single)
        : '已选择 ${locations.length} 个文件夹';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetSection(
          title: '选择文件夹',
          subtitle: '选择要接入的本地文件夹，可多选。',
          colors: palette.section,
          icon: const SourceLineIcon(SourceGlyph.folder, size: 17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SourceSheetButton(
                    label: locations.isEmpty ? '选择文件夹' : '重新选择文件夹',
                    height: 38,
                    horizontalPadding: 12,
                    prominent: locations.isEmpty,
                    icon: const SourceLineIcon(SourceGlyph.folder, size: 13),
                    onPressed: onChoose,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.secondary),
                    ),
                  ),
                ],
              ),
              if (locations.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < locations.length && i < 4; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        Row(
                          children: [
                            SourceLineIcon(
                              SourceGlyph.folder,
                              size: 11,
                              color: palette.secondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _title(locations[i]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (locations.length > 4) ...[
                        const SizedBox(height: 8),
                        Text(
                          '另有 ${locations.length - 4} 个文件夹',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppSheetSection(
          title: '分类',
          subtitle: '决定内容归入哪个媒体库分类。',
          colors: palette.section,
          icon: const SourceLineIcon(SourceGlyph.grid, size: 17),
          child: MediaTypeGridPicker(
            selection: mediaType,
            onChanged: onMediaTypeChanged,
          ),
        ),
      ],
    );
  }
}
