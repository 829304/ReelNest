import 'package:flutter/material.dart';

import '../../../domain/source_media_type.dart';
import '../../../ui/theme/source_sheet_palette.dart';

/// SourcesView.swift / MediaTypeGridPicker, including its original order.
/// SF Symbol assets remain a separate parity item; no Material substitutes.
class MediaTypeGridPicker extends StatelessWidget {
  const MediaTypeGridPicker({
    required this.selection,
    required this.onChanged,
    this.vaultName = '保险库',
    super.key,
  });
  final SourceMediaType selection;
  final ValueChanged<SourceMediaType>? onChanged;
  final String vaultName;
  static const mediaTypes = [
    SourceMediaType.auto,
    SourceMediaType.movie,
    SourceMediaType.tvShow,
    SourceMediaType.anime,
    SourceMediaType.documentary,
    SourceMediaType.variety,
    SourceMediaType.homeVideo,
    SourceMediaType.music,
    SourceMediaType.photo,
    SourceMediaType.other,
    SourceMediaType.privateCollection,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in mediaTypes)
            SizedBox(
              width: (constraints.maxWidth - 16) / 3,
              child: Semantics(
                selected: selection == type,
                child: Tooltip(
                  message: type == SourceMediaType.privateCollection
                      ? '$vaultName的解锁和内容隐藏功能尚未接入'
                      : type.label,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: selection == type
                          ? [
                              BoxShadow(
                                color: palette.shadow.withValues(alpha: .08),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : [],
                    ),
                    child: TextButton(
                      key: ValueKey('media-type-${type.storageValue}'),
                      // Do not let this form create a seemingly protected vault
                      // before the original privacy lock / hiding rules exist.
                      onPressed:
                          onChanged == null ||
                              type == SourceMediaType.privateCollection
                          ? null
                          : () => onChanged!(type),
                      style: ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.standard,
                        splashFactory: NoSplash.splashFactory,
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.fontFamily,
                          ),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => selection == type
                              ? palette.activePill
                              : states.contains(WidgetState.hovered)
                              ? palette.hoverPill
                              : Colors.transparent,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => selection == type
                              ? palette.activePillText
                              : states.contains(WidgetState.hovered)
                              ? palette.menuText
                              : palette.idlePillText,
                        ),
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? BorderSide(color: palette.selectedTint)
                              : BorderSide.none,
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                      child: Text(
                        type == SourceMediaType.privateCollection
                            ? vaultName
                            : type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
