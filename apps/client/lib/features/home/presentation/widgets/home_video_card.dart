import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../sources/presentation/local_media_artwork.dart';
import '../../../playback/application/marker_analysis_providers.dart';
import '../../../../domain/media.dart';
import '../../../../domain/media_source.dart';
import '../../domain/home_snapshot.dart';
import '../../application/home_actions.dart';

/// HomeVividPosterCard: 158x236 posters / 236x138 progress cards, radius 18.
class HomeVideoCard extends ConsumerStatefulWidget {
  const HomeVideoCard({required this.video, this.progress = false, super.key});
  final HomeVideo video;
  final bool progress;
  @override
  ConsumerState<HomeVideoCard> createState() => _HomeVideoCardState();
}

class _HomeVideoCardState extends ConsumerState<HomeVideoCard> {
  bool _hover = false, _busy = false;
  var _menuRequest = 0;

  @override
  void didUpdateWidget(covariant HomeVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.item.identity != widget.video.item.identity) {
      _menuRequest++;
    }
  }

  @override
  void dispose() {
    _menuRequest++;
    super.dispose();
  }

  Future<void> _action(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await homeVideoAction(context, ref, widget.video, action);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final item = video.item;
    final width = widget.progress ? 236.0 : 158.0;
    final height = widget.progress ? 138.0 : 236.0;
    final active = _hover && !MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      transform: Matrix4.translationValues(0, active ? -5 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: active
            ? [
                const BoxShadow(
                  color: Color(0x2E000000),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ]
            : const [],
      ),
      width: width,
      height: height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapDown: (details) async {
            if (_busy) return;
            final request = ++_menuRequest;
            final identity = video.item.identity;
            var canAnalyze = false;
            final eligibility = markerAnalysisEligibilityProvider(identity);
            final hold = ref.listenManual(eligibility, (_, _) {});
            try {
              canAnalyze = await ref.read(eligibility.future);
            } catch (error) {
              if (context.mounted &&
                  request == _menuRequest &&
                  identity == widget.video.item.identity) {
                final message = error is SourceFailure
                    ? error.message
                    : '无法检查当前条目，请重试。';
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message)));
              }
            } finally {
              hold.close();
            }
            if (!context.mounted ||
                request != _menuRequest ||
                identity != widget.video.item.identity) {
              return;
            }
            final action = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              items: [
                const PopupMenuItem(value: 'play', child: Text('播放')),
                PopupMenuItem(
                  value: 'watchlist',
                  child: Text(video.entry.watchlist ? '移出想看' : '加入想看'),
                ),
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(video.favorite ? '取消喜欢' : '喜欢'),
                ),
                if (video.entry.hasTrace || video.entry.record.watched)
                  const PopupMenuItem(value: 'clear', child: Text('清除播放记录')),
                if (canAnalyze)
                  const PopupMenuItem(
                    value: 'markerAnalysis',
                    child: Text('检测片头片尾'),
                  ),
              ],
            );
            if (action != null &&
                mounted &&
                request == _menuRequest &&
                identity == widget.video.item.identity) {
              await _action(action);
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                LocalMediaArtwork(
                  source: video.source,
                  item: item,
                  backdrop: widget.progress,
                  placeholder: _GlyphPlaceholder(
                    video: video,
                    landscape: widget.progress,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x1F000000),
                        Color(0xC7000000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.cardTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: widget.progress ? 15 : 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          item.type == 'episode'
                              ? item.episodeLabel
                              : (mediaTypes[item.displayType] ?? '媒体'),
                          if (item.year != null) '${item.year}',
                          if (video.entry.progress > 0 &&
                              video.entry.progress < .98)
                            '已看 ${(video.entry.progress * 100).round()}%',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                      if (widget.progress &&
                          video.entry.progress > 0 &&
                          video.entry.progress < .98) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: video.entry.progress,
                            minHeight: 4,
                            backgroundColor: const Color(0x4DFFFFFF),
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('home-open-${item.identity}'),
                    onTap: () => context.push(homeDetailLocation(video)),
                    child: Semantics(
                      button: true,
                      label: item.cardTitle,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (item.remote?.rating case final rating? when rating > 0)
                  Positioned(
                    right: 9,
                    top: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0x6B000000),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '★ ${rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFCE4A),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphPlaceholder extends StatelessWidget {
  const _GlyphPlaceholder({required this.video, required this.landscape});
  final HomeVideo video;
  final bool landscape;
  static const _pairs = [
    [Color(0xFF2E90FA), Color(0xFF36BFFA)],
    [Color(0xFF36BFFA), Color(0xFF22D3A8)],
    [Color(0xFFFF9F45), Color(0xFFFFB86B)],
    [Color(0xFFFF5C8A), Color(0xFFFF8FB0)],
    [Color(0xFF5B6CFF), Color(0xFF2E90FA)],
    [Color(0xFFFF5C8A), Color(0xFFD946EF)],
    [Color(0xFF22D3A8), Color(0xFF36BFFA)],
  ];
  @override
  Widget build(BuildContext context) {
    // Swift's hash is process-randomized; a stable seed keeps Flutter redraws
    // consistent while preserving HomeVividTokens' seven accent pairs.
    final seed =
        '${video.item.identity.sourceId}/${video.item.identity.localId}'.runes
            .fold(0, (hash, value) => (hash * 31 + value) & 0x7fffffff);
    final pair = _pairs[seed % _pairs.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            pair[0].withValues(alpha: .92),
            pair[1].withValues(alpha: .76),
          ],
        ),
      ),
      child: Center(
        child: Text(
          video.item.title.characters.firstOrNull ?? '',
          style: TextStyle(
            fontSize: landscape ? 72 : 96,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: .24),
          ),
        ),
      ),
    );
  }
}
