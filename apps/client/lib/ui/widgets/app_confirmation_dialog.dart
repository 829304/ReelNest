import 'package:flutter/material.dart';

import '../theme/source_sheet_palette.dart';
import 'source_sheet_button.dart';

class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.subtitle,
    this.leading,
    this.destructive = false,
    this.cancelLabel = '取消',
    super.key,
  });

  final String title;
  final String? subtitle;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Widget? leading;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SourceSheetPalette(theme.brightness == Brightness.dark);
    final tint = destructive ? theme.colorScheme.error : palette.selectedTint;
    final icon =
        leading ??
        Icon(
          destructive
              ? Icons.warning_amber_rounded
              : Icons.help_outline_rounded,
          size: 23,
          color: tint,
        );
    return Dialog(
      backgroundColor: palette.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: tint.withValues(alpha: .12)),
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Flexible(
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.staticSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: palette.secondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  SourceSheetButton(
                    label: cancelLabel,
                    outlined: true,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  if (destructive)
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 41),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Text(confirmLabel),
                    )
                  else
                    SourceSheetButton(
                      label: confirmLabel,
                      prominent: true,
                      onPressed: () => Navigator.pop(context, true),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
