import 'package:flutter/material.dart';

import '../../../domain/source_media_type.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/source_policy_switch.dart';

/// SourcesView.SourceBehaviorSettingsPanel, local branch. Null callbacks keep
/// unfinished execution services visibly unavailable, not silently effective.
class SourceBehaviorSettingsPanel extends StatelessWidget {
  const SourceBehaviorSettingsPanel({
    required this.mediaType,
    required this.includeInMetadataFetch,
    required this.includeInHealthCheck,
    required this.preferMetadataWriteToSource,
    this.onMetadataChanged,
    this.onHealthChanged,
    this.onWriteChanged,
    super.key,
  });
  final SourceMediaType mediaType;
  final bool includeInMetadataFetch;
  final bool includeInHealthCheck;
  final bool preferMetadataWriteToSource;
  final ValueChanged<bool>? onMetadataChanged;
  final ValueChanged<bool>? onHealthChanged;
  final ValueChanged<bool>? onWriteChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final showsMetadata =
        mediaType != SourceMediaType.photo &&
        mediaType != SourceMediaType.homeVideo;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.staticSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showsMetadata) ...[
            SourcePolicySwitch(
              label: '参与元数据拉取',
              value: includeInMetadataFetch,
              unavailableReason: onMetadataChanged == null ? '元数据拉取暂不可用' : null,
              onChanged: onMetadataChanged == null
                  ? null
                  : (value) {
                      onMetadataChanged!(value);
                      if (!value) onWriteChanged?.call(false);
                    },
            ),
            const SizedBox(height: 10),
          ],
          SourcePolicySwitch(
            label: '参与健康检查',
            value: includeInHealthCheck,
            unavailableReason: onHealthChanged == null ? '健康检查暂不可用' : null,
            onChanged: onHealthChanged,
          ),
          if (showsMetadata) ...[
            const SizedBox(height: 10),
            SourcePolicySwitch(
              label: '元数据优先写入源目录',
              value: preferMetadataWriteToSource,
              unavailableReason: onWriteChanged == null ? '元数据写回暂不可用' : null,
              onChanged: includeInMetadataFetch ? onWriteChanged : null,
            ),
          ],
        ],
      ),
    );
  }
}
