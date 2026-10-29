import 'package:flutter/material.dart';

import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/source_icons.dart';

/// SourcesView.AddMediaSourceWizardSheet.stepIndicator.
///
/// All source flows share this component so the source/configuration/settings
/// steps keep identical geometry, colors and accessibility semantics.
class SourceWizardSteps extends StatelessWidget {
  const SourceWizardSteps({required this.current, super.key})
    : assert(current >= 0 && current <= 2);

  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Semantics(
      container: true,
      label: '添加媒体源，第 ${current + 1} 步，共 3 步',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.staticSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundDecoration: BoxDecoration(
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
              _SourceWizardStepLabel(
                index: index,
                current: current,
                label: const ['来源', '连接', '设置'][index],
                palette: palette,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceWizardStepLabel extends StatelessWidget {
  const _SourceWizardStepLabel({
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
    return Semantics(
      selected: active,
      label:
          '${index + 1}，$label${completed
              ? '，已完成'
              : active
              ? '，当前步骤'
              : ''}',
      excludeSemantics: true,
      child: SizedBox(
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
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
