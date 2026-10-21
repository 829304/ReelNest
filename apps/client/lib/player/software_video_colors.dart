import 'dart:math' as math;

import '../features/playback/domain/video_color_adjustments.dart';
import 'video_color_adjustments_engine.dart';
import 'mpv_owned_video_filters.dart';

/// Equivalent to mpv's csputils color matrix and user gamma, expressed as an
/// LGPL libavfilter graph before libmpv composites subtitles/OSD. Float RGB
/// avoids an additional 8-bit quantization during CPU processing.
class SoftwareVideoColors {
  static String graph(
    VideoColorAdjustments input,
    String matrix, {
    bool explicitInputMatrix = false,
  }) {
    final value = input.normalized;
    final coefficients = switch (matrix) {
      'bt.601' => (0.299, 0.587, 0.114),
      'bt.709' => (0.2126, 0.7152, 0.0722),
      'smpte-240m' => (0.2122, 0.7013, 0.0865),
      'bt.2020-ncl' ||
      'bt.2100-pq' ||
      'bt.2100-hlg' ||
      'dolbyvision' => (0.2627, 0.6780, 0.0593),
      // mpv's matrix routine defaults unknown/auto to BT.601.
      'auto' => (0.299, 0.587, 0.114),
      _ => null,
    };
    final contrast = 1 + value.contrast / 100;
    final brightness = value.brightness / 100;
    final gamma = math.pow(8, -value.gamma / 100).toDouble();
    // Start with RGB identity. mpv also ignores hue/saturation for RGB, XYZ,
    // YCgCo and BT.2020 constant luminance inputs.
    final rows = [
      <double>[1, 0, 0],
      <double>[0, 1, 0],
      <double>[0, 0, 1],
    ];
    if (coefficients != null && (value.hue != 0 || value.saturation != 0)) {
      final (kr, kg, kb) = coefficients;
      final y = [kr, kg, kb];
      final u = [-kr / (2 * (1 - kb)), -kg / (2 * (1 - kb)), .5];
      final v = [.5, -kg / (2 * (1 - kr)), -kb / (2 * (1 - kr))];
      final hue = value.hue / 100 * math.pi;
      final saturation = 1 + value.saturation / 100;
      final c = saturation * math.cos(hue), s = saturation * math.sin(hue);
      final chroma = [
        (0.0, 2 * (1 - kr)),
        (-2 * kb * (1 - kb) / kg, -2 * kr * (1 - kr) / kg),
        (2 * (1 - kb), 0.0),
      ];
      for (var channel = 0; channel < 3; channel++) {
        final (cu, cv) = chroma[channel];
        for (var at = 0; at < 3; at++) {
          rows[channel][at] =
              y[at] + (cu * c - cv * s) * u[at] + (cu * s + cv * c) * v[at];
        }
      }
    }
    const channels = ['r', 'g', 'b'];
    String expression(int channel) {
      final terms = [
        for (var at = 0; at < 3; at++)
          if (rows[channel][at] * contrast != 0)
            rows[channel][at] * contrast == 1
                ? '${channels[at]}(X,Y)'
                : '${rows[channel][at] * contrast}*${channels[at]}(X,Y)',
      ];
      final sum = terms.isEmpty ? '0' : terms.join('+');
      final shifted = brightness == 0 ? sum : '($sum)+$brightness';
      final clamped = 'max($shifted,0)';
      return gamma == 1 ? clamped : 'pow($clamped,$gamma)';
    }

    final conversion = explicitInputMatrix
        ? 'scale=in_color_matrix=${matrix == 'bt.709' ? 'bt709' : 'bt601'},'
        : '';
    return "${conversion}format=gbrpf32le,geq="
        "r='${expression(0)}':g='${expression(1)}':b='${expression(2)}'";
  }
}

class MpvSoftwareColorCommands {
  MpvSoftwareColorCommands({required this.command, required this.read});
  final Future<void> Function(List<String>) command;
  final Future<String> Function(String) read;
  static const label = 'reelnest-color';
  late final _filters = MpvOwnedVideoFilters(command: command, read: read);

  Future<void> apply(VideoColorAdjustments value) async {
    final native = MpvColorAdjustmentCommands(command: command, read: read);
    final before = await native.current();
    final previousFilters = await _filters.snapshot();
    String? graph;
    if (!value.isNeutral) {
      var matrix = await read('video-params/colormatrix');
      // unsharp accepts planar YUV. For RGB input its auto-conversion loses
      // the matrix tag; mpv's GPU path guesses BT.601/709 from dimensions.
      // Reproduce that conversion before applying the CPU color matrix.
      final convertedRgb =
          matrix == 'rgb' &&
          previousFilters.any((f) => f.label == 'reelnest-sharpen');
      if (convertedRgb || matrix == 'auto') {
        final width = int.parse(await read('video-params/w'));
        final height = int.parse(await read('video-params/h'));
        matrix = width >= 1280 || height > 576 ? 'bt.709' : 'bt.601';
      }
      graph = SoftwareVideoColors.graph(
        value,
        matrix,
        explicitInputMatrix: convertedRgb,
      );
    }
    try {
      await native.apply(value);
      await _filters.update({
        label: graph == null
            ? null
            : MpvVideoFilter(label, 'lavfi', {'graph': graph}),
      });
    } catch (error, stack) {
      var failed = false;
      try {
        await _filters.restore(previousFilters);
      } catch (_) {
        failed = true;
      }
      try {
        await native.apply(before);
      } catch (_) {
        failed = true;
      }
      if (failed) throw const VideoColorRollbackFailure();
      Error.throwWithStackTrace(error, stack);
    }
  }
}
