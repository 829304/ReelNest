import 'package:flutter/material.dart';

enum AppFeedbackKind { information, success, warning, error }

void showAppToast(
  BuildContext context,
  String message, {
  AppFeedbackKind kind = AppFeedbackKind.information,
}) {
  if (!context.mounted) return;
  final screenWidth = MediaQuery.sizeOf(context).width;
  final toastWidth = screenWidth >= 480 ? 440.0 : screenWidth - 32;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: AppInlineNotice(message: message, kind: kind, floating: true),
        behavior: SnackBarBehavior.floating,
        width: toastWidth,
        elevation: 0,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
      ),
    );
}

class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    required this.message,
    this.kind = AppFeedbackKind.information,
    this.actionLabel,
    this.onAction,
    this.floating = false,
    super.key,
  });

  final String message;
  final AppFeedbackKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = switch (kind) {
      AppFeedbackKind.information => Color(dark ? 0xFF87D0F4 : 0xFF2E90FA),
      AppFeedbackKind.success => Color(dark ? 0xFF67E19A : 0xFF1F9D57),
      AppFeedbackKind.warning => Color(dark ? 0xFFFFC66D : 0xFFD98A00),
      AppFeedbackKind.error => Color(dark ? 0xFFFF8E8E : 0xFFD92D20),
    };
    final icon = switch (kind) {
      AppFeedbackKind.information => Icons.info_outline_rounded,
      AppFeedbackKind.success => Icons.check_circle_outline_rounded,
      AppFeedbackKind.warning => Icons.warning_amber_rounded,
      AppFeedbackKind.error => Icons.error_outline_rounded,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: dark ? .14 : .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: .24)),
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? .26 : .10),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: tint),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(width: 10),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
