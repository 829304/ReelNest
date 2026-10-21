import 'package:flutter/material.dart';

import '../../../ui/widgets/app_confirmation_dialog.dart';
import '../../../ui/widgets/source_icons.dart';

/// SourcesView confirmation chrome. The caller keeps ownership of the action
/// and only receives the user's decision.
class SourceConfirmationDialog extends StatelessWidget {
  const SourceConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.subtitle,
    this.destructive = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String message;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return AppConfirmationDialog(
      title: title,
      subtitle: subtitle,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      leading: SourceLineIcon(
        destructive ? SourceGlyph.warning : SourceGlyph.folder,
        size: 22,
        color: destructive ? palette.error : palette.primary,
      ),
    );
  }
}
