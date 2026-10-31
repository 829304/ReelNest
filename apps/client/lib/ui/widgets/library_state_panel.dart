import 'package:flutter/material.dart';

import '../theme/source_sheet_palette.dart';

/// Stable-size loading surface used by desktop library pages.
///
/// MediaLib keeps the page header and controls in place while the body changes
/// between loading, empty and error states. Giving those states the same
/// minimum height avoids a vertical jump when a scan or retry completes.
class LibraryLoadingPanel extends StatelessWidget {
  const LibraryLoadingPanel({
    required this.palette,
    required this.title,
    this.subtitle = '正在准备当前页面',
    this.icon = Icons.video_library_outlined,
    super.key,
  });

  final SourceSheetPalette palette;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, shimmer, _) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 420),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: palette.border, width: .8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 38,
                  child: Icon(icon, size: 27, color: palette.selectedTint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.secondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < 4; index++) ...[
              _SkeletonRow(
                palette: palette,
                shimmer: shimmer,
                widthFactor: .58 + index * .06,
              ),
              if (index != 3) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class LibraryStatusPanel extends StatelessWidget {
  const LibraryStatusPanel({
    required this.palette,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final SourceSheetPalette palette;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(minHeight: 420),
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: palette.border, width: .8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: palette.selectedTint.withValues(alpha: .10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 26, color: palette.selectedTint),
        ),
        const SizedBox(height: 15),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.secondary,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class LibraryPosterPlaceholder extends StatelessWidget {
  const LibraryPosterPlaceholder({this.retry, this.loading = true, super.key});

  final VoidCallback? retry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border, width: .8),
      ),
      child: retry != null
          ? Center(
              child: OutlinedButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试'),
              ),
            )
          : loading
          ? Center(
              child: SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.selectedTint,
                ),
              ),
            )
          : const SizedBox.expand(),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.palette,
    required this.shimmer,
    required this.widthFactor,
  });

  final SourceSheetPalette palette;
  final double shimmer;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: palette.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: palette.border, width: .8),
    ),
    child: Row(
      children: [
        _block(width: 52, height: 52, radius: 8),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: widthFactor.clamp(.4, .84),
                child: _block(height: 10, radius: 4),
              ),
              const SizedBox(height: 7),
              FractionallySizedBox(
                widthFactor: (widthFactor - .18).clamp(.28, .66),
                child: _block(height: 8, radius: 4),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _block({
    double? width,
    required double height,
    required double radius,
  }) {
    final position = -2 + shimmer * 4;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(position - .65, 0),
          end: Alignment(position + .65, 0),
          colors: [
            palette.control,
            Colors.white.withValues(alpha: palette.dark ? .10 : .58),
            palette.control,
          ],
        ),
      ),
    );
  }
}
