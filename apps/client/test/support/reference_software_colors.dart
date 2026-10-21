import 'dart:math' as math;

import 'package:reelnest/features/playback/domain/video_color_adjustments.dart';

/// Equivalent to mpv's csputils color matrix and user gamma, expressed as an
/// LGPL libavfilter graph before libmpv composites subtitles/OSD. Float RGB
/// avoids an additional 8-bit quantization during CPU processing.
// Frozen pre-optimization expression used only for pixel regression.
class ReferenceSoftwareVideoColors {
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
    if (coefficients != null) {
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
          '${rows[channel][at] * contrast}*${channels[at]}(X,Y)',
      ];
      return 'pow(max((${terms.join('+')})+$brightness,0),$gamma)';
    }

    final conversion = explicitInputMatrix
        ? 'scale=in_color_matrix=${matrix == 'bt.709' ? 'bt709' : 'bt601'},'
        : '';
    return "${conversion}format=gbrpf32le,geq="
        "r='${expression(0)}':g='${expression(1)}':b='${expression(2)}'";
  }
}
