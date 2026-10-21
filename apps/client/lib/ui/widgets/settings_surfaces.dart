import 'package:flutter/material.dart';

import '../theme/source_sheet_palette.dart';
import 'app_confirmation_dialog.dart';

class AppSettingsHeader extends StatelessWidget {
  const AppSettingsHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.iconChip,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: palette.selectedTint.withValues(alpha: .14),
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.selectedTint.withValues(alpha: .09),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: 25, color: palette.selectedTint),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppSettingsSection extends StatelessWidget {
  const AppSettingsSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = constraints.maxWidth >= 560 ? 18.0 : 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.iconChip,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: palette.selectedTint.withValues(alpha: .14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.selectedTint.withValues(alpha: .08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 24, color: palette.selectedTint),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: palette.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.only(left: inset),
              child: AppSettingsCard(child: child),
            ),
          ],
        );
      },
    );
  }
}

class AppSettingsCard extends StatelessWidget {
  const AppSettingsCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: palette.staticSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: palette.dark ? .08 : .035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppSettingsRow extends StatelessWidget {
  const AppSettingsRow({
    required this.title,
    required this.icon,
    required this.trailing,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.iconChip,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: palette.selectedTint),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: palette.secondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 530;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: trailing),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 230, child: label),
            const SizedBox(width: 16),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        );
      },
    );
  }
}

class AppSettingsSubsectionHeader extends StatelessWidget {
  const AppSettingsSubsectionHeader({
    required this.title,
    required this.icon,
    super.key,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Row(
      children: [
        Icon(icon, size: 14, color: palette.secondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.secondary,
          ),
        ),
      ],
    );
  }
}

class AppSettingsDescription extends StatelessWidget {
  const AppSettingsDescription({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(48, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.cleanPanelFill.withValues(alpha: .66),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border.withValues(alpha: .72)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: palette.secondary,
        ),
      ),
    );
  }
}

class AppSettingsPathText extends StatelessWidget {
  const AppSettingsPathText({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: palette.cleanPanelFill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      child: SelectableText(
        text,
        maxLines: 1,
        style: TextStyle(fontSize: 11.5, color: palette.secondary),
      ),
    );
  }
}

class AppSettingsDivider extends StatelessWidget {
  const AppSettingsDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Divider(
      height: 1,
      color: SourceSheetPalette(Theme.of(context).brightness == Brightness.dark)
          .border,
    ),
  );
}

class AppSettingsNotice extends StatelessWidget {
  const AppSettingsNotice({
    required this.message,
    this.error = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SourceSheetPalette(theme.brightness == Brightness.dark);
    final tint = error ? theme.colorScheme.error : palette.selectedTint;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: .065),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tint.withValues(alpha: .15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                error ? Icons.error_outline : Icons.info_outline,
                size: 15,
                color: tint,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: error ? tint : palette.secondary,
                  ),
                ),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppSettingsConfirmationDialog extends StatelessWidget {
  const AppSettingsConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) => AppConfirmationDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: destructive,
    leading: Icon(
      destructive ? Icons.delete_outline : Icons.cleaning_services_outlined,
      size: 23,
      color: destructive
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary,
    ),
  );
}
