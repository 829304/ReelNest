import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../ui/widgets/slider_overlay_scope.dart';
import '../domain/video_frame_preview.dart';
import '../domain/video_scrubber_preview_mode.dart';
import 'player_visuals.dart';

typedef ScrubberPreviewLoader = Future<Uint8List?> Function(
  Duration time, {
  required bool coarse,
  required bool prefetch,
  required VideoPreviewCancellation cancellation,
});

/// Original PlayerView timeline behavior: the pointer updates the preview
/// immediately, while decoded frames are bucketed and requested after a short
/// mode-specific delay. Seeking is committed only when a drag ends.
class PlayerTimelineScrubber extends StatefulWidget {
  const PlayerTimelineScrubber({
    required this.duration,
    required this.position,
    required this.enabled,
    required this.mode,
    required this.palette,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
    this.previewLoader,
    this.overlay,
    super.key,
  });

  final Duration duration;
  final double position;
  final bool enabled;
  final VideoScrubberPreviewMode mode;
  final PlayerPalette palette;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final ScrubberPreviewLoader? previewLoader;
  final Widget? overlay;

  @override
  State<PlayerTimelineScrubber> createState() => _PlayerTimelineScrubberState();
}

class _PlayerTimelineScrubberState extends State<PlayerTimelineScrubber> {
  Timer? _requestTimer;
  VideoPreviewCancellation? _activeRequest;
  bool _hovering = false;
  bool _dragging = false;
  bool _loading = false;
  bool _empty = false;
  double _previewX = 0;
  Duration _previewTime = Duration.zero;
  Uint8List? _previewBytes;
  int? _requestedBucket;
  int _generation = 0;
  DateTime? _lastFrameRequest;
  double? _lastFrameX;

  bool get _visible => _hovering || _dragging;
  bool get _wantsFrame =>
      widget.mode != VideoScrubberPreviewMode.off &&
      widget.previewLoader != null;
  bool get _coarse => widget.mode == VideoScrubberPreviewMode.performance;

  @override
  void didUpdateWidget(covariant PlayerTimelineScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.duration != widget.duration) {
      _cancelRequest(clearFrame: true);
      if (_visible && _wantsFrame) _scheduleFrame(force: true);
    }
  }

  @override
  void dispose() {
    _requestTimer?.cancel();
    _activeRequest?.cancel();
    _generation++;
    super.dispose();
  }

  void _cancelRequest({required bool clearFrame}) {
    _requestTimer?.cancel();
    _activeRequest?.cancel();
    _activeRequest = null;
    _requestTimer = null;
    _generation++;
    _requestedBucket = null;
    _lastFrameRequest = null;
    _lastFrameX = null;
    if (clearFrame) {
      _previewBytes = null;
      _loading = false;
      _empty = false;
    }
  }

  Duration _timeAt(double x, double width) {
    if (widget.duration <= Duration.zero) return Duration.zero;
    final usable = (width - 20).clamp(1.0, width).toDouble();
    final fraction = ((x - 10) / usable).clamp(0.0, 1.0);
    return Duration(
      microseconds: (widget.duration.inMicroseconds * fraction).round(),
    );
  }

  double _xAt(double value, double width) {
    final duration = widget.duration.inMilliseconds;
    if (duration <= 0) return 10;
    final fraction = (value / duration).clamp(0.0, 1.0);
    return 10 + (width - 20).clamp(1.0, width).toDouble() * fraction;
  }

  void _updatePointer(double x, double width, {bool forceFrame = false}) {
    final clampedX = x.clamp(0.0, width).toDouble();
    final time = _timeAt(clampedX, width);
    if (mounted) {
      setState(() {
        _previewX = clampedX;
        _previewTime = time;
      });
    }
    _scheduleFrame(force: forceFrame);
  }

  Duration get _bucketDuration {
    final seconds = widget.duration.inMilliseconds / 1000;
    final target = _coarse ? 84 : 96;
    final minimum = _coarse ? 12.0 : 8.0;
    final maximum = _coarse ? 120.0 : 90.0;
    final bucket = (seconds / target).clamp(minimum, maximum);
    return Duration(milliseconds: (bucket * 1000).round());
  }

  void _scheduleFrame({bool force = false}) {
    if (!_wantsFrame || !_visible) {
      _requestTimer?.cancel();
      return;
    }
    final bucketMicros = _bucketDuration.inMicroseconds;
    final bucket = bucketMicros <= 0
        ? 0
        : (_previewTime.inMicroseconds / bucketMicros).floor();
    if (!force && bucket == _requestedBucket) return;

    final now = DateTime.now();
    final minimumInterval = Duration(milliseconds: _coarse ? 110 : 42);
    final minimumDistance = _coarse ? 16.0 : 9.0;
    if (!force &&
        _lastFrameRequest != null &&
        now.difference(_lastFrameRequest!) < minimumInterval &&
        _lastFrameX != null &&
        (_previewX - _lastFrameX!).abs() < minimumDistance) {
      return;
    }

    _requestTimer?.cancel();
    _activeRequest?.cancel();
    final generation = ++_generation;
    final target = _previewTime;
    final targetBucket = bucket;
    _requestTimer = Timer(Duration(milliseconds: _coarse ? 120 : 45), () async {
      if (!mounted || generation != _generation || !_visible) return;
      setState(() {
        _loading = true;
        _empty = false;
      });
      _lastFrameRequest = DateTime.now();
      _lastFrameX = _previewX;
      final cancellation = VideoPreviewCancellation();
      _activeRequest = cancellation;
      Uint8List? bytes;
      try {
        bytes = await widget.previewLoader!(
          target,
          coarse: _coarse,
          prefetch: widget.mode == VideoScrubberPreviewMode.balanced,
          cancellation: cancellation,
        );
      } catch (_) {
        bytes = null;
      }
      if (!mounted || generation != _generation || !_visible) return;
      setState(() {
        _requestedBucket = targetBucket;
        _previewBytes = bytes;
        _loading = false;
        _empty = bytes == null || bytes.isEmpty;
      });
      if (identical(_activeRequest, cancellation)) _activeRequest = null;
    });
  }

  void _hidePreview() {
    setState(() => _hovering = false);
    if (!_dragging) {
      _requestTimer?.cancel();
      _activeRequest?.cancel();
      _generation++;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final hasFrame = widget.mode != VideoScrubberPreviewMode.off;
      final bubbleWidth = hasFrame ? 164.0 : 96.0;
      final left = (_previewX - bubbleWidth / 2)
          .clamp(0.0, (width - bubbleWidth).clamp(0.0, width))
          .toDouble();
      return MouseRegion(
        key: const ValueKey('player-timeline-hover-region'),
        cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (event) {
          setState(() => _hovering = true);
          if (widget.enabled) {
            _updatePointer(event.localPosition.dx, width, forceFrame: true);
          }
        },
        onHover: widget.enabled
            ? (event) => _updatePointer(event.localPosition.dx, width)
            : null,
        onExit: (_) => _hidePreview(),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            SliderOverlayScope(
              child: Slider(
                key: const ValueKey('video-timeline'),
                min: 0,
                max: widget.duration > Duration.zero
                    ? widget.duration.inMilliseconds.toDouble()
                    : 1,
                value: widget.position,
                onChangeStart: widget.enabled
                    ? (value) {
                        setState(() {
                          _dragging = true;
                          _hovering = true;
                          _previewTime = Duration(milliseconds: value.round());
                          _previewX = _xAt(value, width);
                        });
                        _scheduleFrame(force: true);
                        widget.onChangeStart(value);
                      }
                    : null,
                onChanged: widget.enabled
                    ? (value) {
                        setState(() {
                          _previewTime = Duration(milliseconds: value.round());
                          _previewX = _xAt(value, width);
                        });
                        _scheduleFrame();
                        widget.onChanged(value);
                      }
                    : null,
                onChangeEnd: widget.enabled
                    ? (value) {
                        setState(() => _dragging = false);
                        if (!_hovering) {
                          _requestTimer?.cancel();
                          _activeRequest?.cancel();
                          _generation++;
                        }
                        widget.onChangeEnd(value);
                      }
                    : null,
              ),
            ),
            if (widget.overlay != null) Positioned.fill(child: widget.overlay!),
            Positioned(
              left: left,
              top: hasFrame ? -106 : -44,
              width: bubbleWidth,
              child: SizedBox(
                key: const ValueKey('player-timeline-preview-position'),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    key: const ValueKey('player-timeline-preview'),
                    opacity: _visible && widget.enabled ? 1 : 0,
                    duration: const Duration(milliseconds: 110),
                    curve: Curves.easeOut,
                    child: AnimatedScale(
                      scale: _visible && widget.enabled ? 1 : .97,
                      duration: const Duration(milliseconds: 110),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomCenter,
                      child: hasFrame
                          ? _FramePreview(
                              bytes: _previewBytes,
                              loading: _loading,
                              empty: _empty || widget.previewLoader == null,
                              time: _previewTime,
                              palette: widget.palette,
                            )
                          : _TimePreview(
                              time: _previewTime,
                              palette: widget.palette,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _FramePreview extends StatelessWidget {
  const _FramePreview({
    required this.bytes,
    required this.loading,
    required this.empty,
    required this.time,
    required this.palette,
  });

  final Uint8List? bytes;
  final bool loading;
  final bool empty;
  final Duration time;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) => PlayerPanelSurface(
    palette: palette,
    radius: 13,
    liveMaterial: true,
    shadowRadius: 10,
    shadowOffset: const Offset(0, 4),
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 148,
          height: 83,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.black.withValues(alpha: .72)),
              if (bytes != null && bytes!.isNotEmpty)
                Image.memory(
                  bytes!,
                  key: const ValueKey('player-timeline-preview-image'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                )
              else
                Center(
                  child: Text(
                    loading ? '提取预览' : (empty ? '暂无预览' : '提取预览'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .74),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Positioned(right: 6, bottom: 5, child: _TimeCapsule(time: time)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TimePreview extends StatelessWidget {
  const _TimePreview({required this.time, required this.palette});

  final Duration time;
  final PlayerPalette palette;

  @override
  Widget build(BuildContext context) => PlayerPanelSurface(
    palette: palette,
    radius: 11,
    liveMaterial: true,
    shadowRadius: 8,
    shadowOffset: const Offset(0, 3),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: palette.secondary),
          const SizedBox(width: 5),
          Text(
            _formatTime(time),
            style: TextStyle(
              color: palette.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimeCapsule extends StatelessWidget {
  const _TimeCapsule({required this.time});

  final Duration time;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .66),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        _formatTime(time),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

String _formatTime(Duration value) {
  final total = value.inSeconds.clamp(0, 359999);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int number) => number.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}
