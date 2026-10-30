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
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        key: const ValueKey('app-confirmation-dialog'),
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: .10),
                      shape: BoxShape.circle,
                      border: Border.all(color: tint.withValues(alpha: .18)),
                    ),
                    child: IconTheme(
                      data: IconThemeData(color: tint, size: 20),
                      child: icon,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
                              height: 1.35,
                              color: palette.secondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: palette.secondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 17),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  SourceSheetButton(
                    key: const ValueKey('app-confirmation-cancel'),
                    label: cancelLabel,
                    outlined: true,
                    autofocus: true,
                    height: 36,
                    horizontalPadding: 15,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  if (destructive)
                    FilledButton(
                      key: const ValueKey('app-confirmation-confirm'),
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: Text(confirmLabel),
                    )
                  else
                    SourceSheetButton(
                      key: const ValueKey('app-confirmation-confirm'),
                      label: confirmLabel,
                      prominent: true,
                      height: 36,
                      horizontalPadding: 15,
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
