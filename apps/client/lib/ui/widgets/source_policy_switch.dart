import 'package:flutter/material.dart';

import '../theme/source_sheet_palette.dart';

/// AppColors.AppSwitchToggleStyle: 44x26 track, 20px thumb, 3px inset.
class SourcePolicySwitch extends StatelessWidget {
  const SourcePolicySwitch({
    required this.label,
    required this.value,
    this.onChanged,
    this.unavailableReason,
    super.key,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? unavailableReason;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final enabled = onChanged != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final control = Semantics(
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .48,
        child: TextButton(
          onPressed: onChanged == null ? null : () => onChanged!(!value),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 26),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: palette.text,
            disabledForegroundColor: palette.text,
            textStyle: TextStyle(
              fontSize: 13,
              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label)),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 26,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: value
                        ? const [Color(0xFF2E90FA), Color(0xFF36BFFA)]
                        : [
                            palette.cleanPanelFill.withValues(
                              alpha:
                                  palette.cleanPanelFill.a *
                                  (palette.dark ? .40 : .86),
                            ),
                            palette.solar.withValues(
                              alpha: palette.dark ? .14 : .22,
                            ),
                          ],
                  ),
                  boxShadow: value
                      ? [
                          BoxShadow(
                            color: const Color(0xFF2E90FA)
                                .withValues(alpha: .16),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    width: value ? .75 : .65,
                    color: value
                        ? Colors.white.withValues(alpha: .42)
                        : palette.panelBorder.withValues(
                            alpha:
                                palette.panelBorder.a *
                                (palette.dark ? .50 : .38),
                          ),
                  ),
                ),
                child: AnimatedAlign(
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  duration: duration,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(
                        alpha: palette.dark ? .94 : .98,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .76),
                        width: .7,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: palette.dark ? .30 : .15,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return unavailableReason == null
        ? control
        : Tooltip(message: unavailableReason!, child: control);
  }
}
