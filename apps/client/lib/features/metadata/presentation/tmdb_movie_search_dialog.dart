import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/theme/source_sheet_palette.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../../ui/widgets/app_sheet.dart';
import '../../../ui/widgets/source_sheet_button.dart';
import '../application/tmdb_providers.dart';
import '../domain/tmdb_models.dart';

Future<TmdbApplyResult?> showTmdbMovieSearchDialog({
  required BuildContext context,
  required MediaIdentity identity,
  required String initialQuery,
}) => _showTmdbSearchDialog(
  context: context,
  identity: identity,
  initialQuery: initialQuery,
  kind: TmdbMediaKind.movie,
);

Future<TmdbApplyResult?> showTmdbSeriesSearchDialog({
  required BuildContext context,
  required MediaIdentity identity,
  required String initialQuery,
}) => _showTmdbSearchDialog(
  context: context,
  identity: identity,
  initialQuery: initialQuery,
  kind: TmdbMediaKind.tv,
);

Future<TmdbApplyResult?> _showTmdbSearchDialog({
  required BuildContext context,
  required MediaIdentity identity,
  required String initialQuery,
  required TmdbMediaKind kind,
}) => showDialog<TmdbApplyResult>(
  context: context,
  // Application writes cannot be cancelled once they start. Keep dismissal
  // behind the dialog's close/Escape handlers so the route cannot disappear
  // through a modal-barrier pop while an apply is in flight.
  barrierDismissible: false,
  builder: (_) => TmdbSearchDialog(
    identity: identity,
    initialQuery: initialQuery,
    kind: kind,
  ),
);

class TmdbMovieMatchButton extends ConsumerWidget {
  const TmdbMovieMatchButton({
    required this.identity,
    required this.title,
    super.key,
  });

  final MediaIdentity identity;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    key: const ValueKey('tmdb-movie-search-entry'),
    onPressed: () => unawaited(
      _openTmdbMatch(
        context: context,
        ref: ref,
        identity: identity,
        title: title,
        kind: TmdbMediaKind.movie,
      ),
    ),
    icon: const Icon(Icons.manage_search_rounded, size: 17),
    label: const Text('搜索 TMDB'),
  );
}

class TmdbSeriesMatchButton extends ConsumerWidget {
  const TmdbSeriesMatchButton({
    required this.identity,
    required this.title,
    super.key,
  });

  final MediaIdentity identity;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    key: const ValueKey('tmdb-series-search-entry'),
    onPressed: () => unawaited(
      _openTmdbMatch(
        context: context,
        ref: ref,
        identity: identity,
        title: title,
        kind: TmdbMediaKind.tv,
      ),
    ),
    icon: const Icon(Icons.manage_search_rounded, size: 17),
    label: const Text('搜索 TMDB'),
  );
}

Future<void> _openTmdbMatch({
  required BuildContext context,
  required WidgetRef ref,
  required MediaIdentity identity,
  required String title,
  required TmdbMediaKind kind,
}) async {
  final result = kind == TmdbMediaKind.movie
      ? await showTmdbMovieSearchDialog(
          context: context,
          identity: identity,
          initialQuery: title,
        )
      : await showTmdbSeriesSearchDialog(
          context: context,
          identity: identity,
          initialQuery: title,
        );
  if (result == null || !context.mounted) return;
  if (kind == TmdbMediaKind.movie) {
    ref.invalidate(tmdbMovieMetadataProvider(identity));
  } else {
    ref.invalidate(tmdbSeriesMetadataProvider(identity));
  }
  if (result.warnings.isEmpty) {
    showAppToast(
      context,
      kind == TmdbMediaKind.movie ? 'TMDB 电影资料已应用。' : 'TMDB 剧集资料已应用。',
      kind: AppFeedbackKind.success,
    );
    return;
  }
  showAppToast(
    context,
    result.warnings.join(' '),
    kind: AppFeedbackKind.warning,
  );
}

class TmdbSearchDialog extends ConsumerStatefulWidget {
  const TmdbSearchDialog({
    required this.identity,
    required this.initialQuery,
    required this.kind,
    super.key,
  });

  final MediaIdentity identity;
  final String initialQuery;
  final TmdbMediaKind kind;

  @override
  ConsumerState<TmdbSearchDialog> createState() => _TmdbSearchDialogState();
}

class _TmdbSearchDialogState extends ConsumerState<TmdbSearchDialog> {
  late final TextEditingController _query;
  final _focusNode = FocusNode();
  ScanCancellation? _searchCancellation;
  List<TmdbCandidate> _results = const [];
  String? _error;
  bool _searching = false;
  int? _applyingId;
  int _generation = 0;

  bool get _applying => _applyingId != null;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_search());
    });
  }

  @override
  void dispose() {
    _generation++;
    _searchCancellation?.cancel();
    _query.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _close() {
    if (_applying) return;
    _searchCancellation?.cancel();
    Navigator.of(context).pop();
  }

  Future<void> _search() async {
    if (_applying) return;
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() {
        _error = '请输入搜索关键词。';
        _results = const [];
        _searching = false;
      });
      return;
    }
    _searchCancellation?.cancel();
    final cancellation = ScanCancellation();
    _searchCancellation = cancellation;
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
      _results = const [];
    });
    try {
      final service = widget.kind == TmdbMediaKind.movie
          ? ref.read(tmdbMovieServiceProvider)
          : ref.read(tmdbSeriesServiceProvider);
      final results = await service.search(query, cancellation: cancellation);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } on ScanCancelled {
      if (!mounted || generation != _generation) return;
      setState(() => _searching = false);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _error = error is SourceFailure ? error.message : 'TMDB 搜索失败，请稍后重试。';
      });
    }
  }

  Future<void> _apply(TmdbCandidate candidate) async {
    if (_applying) return;
    _searchCancellation?.cancel();
    setState(() {
      _applyingId = candidate.id;
      _error = null;
    });
    try {
      final service = widget.kind == TmdbMediaKind.movie
          ? ref.read(tmdbMovieServiceProvider)
          : ref.read(tmdbSeriesServiceProvider);
      final result = await service.apply(widget.identity, candidate);
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _applyingId = null;
        _error = error is SourceFailure
            ? error.message
            : '影视资料保存失败，已有资料未更改，请重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SourceSheetPalette(
      Theme.of(context).brightness == Brightness.dark,
    );
    return PopScope(
      canPop: !_applying,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Dialog(
          key: ValueKey(
            widget.kind == TmdbMediaKind.movie
                ? 'tmdb-movie-search-dialog'
                : 'tmdb-series-search-dialog',
          ),
          backgroundColor: palette.page,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: palette.border),
          ),
          child: SizedBox(
            width: AppSheetMetrics.wideWidth,
            height: 460,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '搜索 TMDB 信息',
                              style: TextStyle(
                                fontSize: 22,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '使用设置中的 TMDB API 搜索电影和剧集信息。',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: const ValueKey('close-tmdb-search'),
                        tooltip: '关闭',
                        onPressed: _applying ? null : _close,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('tmdb-search-input'),
                          controller: _query,
                          focusNode: _focusNode,
                          enabled: !_applying,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => unawaited(_search()),
                          decoration: InputDecoration(
                            hintText: '搜索关键词',
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 19,
                            ),
                            filled: true,
                            fillColor: palette.control,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SourceSheetButton(
                        key: const ValueKey('submit-tmdb-search'),
                        label: _searching ? '搜索中…' : '搜索',
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.search_rounded, size: 15),
                        prominent: true,
                        onPressed: _searching || _applying
                            ? null
                            : () => unawaited(_search()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null && _results.isNotEmpty) ...[
                    AppInlineNotice(
                      key: const ValueKey('tmdb-search-error'),
                      message: _error!,
                      kind: AppFeedbackKind.error,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Expanded(child: _body(palette)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(SourceSheetPalette palette) {
    if (_searching) {
      return Center(
        key: const ValueKey('tmdb-search-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.2,
              color: palette.selectedTint,
            ),
            const SizedBox(height: 12),
            Text('正在搜索', style: TextStyle(color: palette.secondary)),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        key: const ValueKey('tmdb-search-empty'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 36,
              color: palette.secondary.withValues(alpha: .72),
            ),
            const SizedBox(height: 10),
            Text(
              '暂无可用结果',
              style: TextStyle(
                color: palette.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.secondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey('tmdb-search-results'),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final candidate = _results[index];
        return _TmdbCandidateCard(
          candidate: candidate,
          palette: palette,
          applying: _applyingId == candidate.id,
          enabled: !_applying,
          onApply: () => unawaited(_apply(candidate)),
        );
      },
    );
  }
}

class _TmdbCandidateCard extends StatelessWidget {
  const _TmdbCandidateCard({
    required this.candidate,
    required this.palette,
    required this.applying,
    required this.enabled,
    required this.onApply,
  });

  final TmdbCandidate candidate;
  final SourceSheetPalette palette;
  final bool applying;
  final bool enabled;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final subtitle = candidate.releaseDate?.trim();
    return Container(
      key: ValueKey('tmdb-candidate-${candidate.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.staticSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border, width: .8),
                ),
                child: Text(
                  candidate.provider,
                  style: TextStyle(
                    color: palette.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (candidate.overview?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              candidate.overview!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: palette.secondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (candidate.year != null)
                _CandidateFact(
                  icon: Icons.calendar_today_outlined,
                  value: '${candidate.year}',
                  palette: palette,
                ),
              if (candidate.year != null && candidate.rating != null)
                const SizedBox(width: 12),
              if (candidate.rating != null)
                _CandidateFact(
                  icon: Icons.star_rounded,
                  value: candidate.rating!.toStringAsFixed(1),
                  palette: palette,
                ),
              const Spacer(),
              _CandidateApplyButton(
                key: ValueKey('apply-tmdb-candidate-${candidate.id}'),
                label: applying ? '应用中…' : '应用',
                palette: palette,
                onPressed: enabled ? onApply : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CandidateApplyButton extends StatelessWidget {
  const _CandidateApplyButton({
    required this.label,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  final String label;
  final SourceSheetPalette palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? .5 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.menuText,
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

class _CandidateFact extends StatelessWidget {
  const _CandidateFact({
    required this.icon,
    required this.value,
    required this.palette,
  });

  final IconData icon;
  final String value;
  final SourceSheetPalette palette;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: palette.secondary),
      const SizedBox(width: 4),
      Text(value, style: TextStyle(fontSize: 11, color: palette.secondary)),
    ],
  );
}
