import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// AlbumColorPalette / AlbumPaletteCache in MusicPlayerView.swift, with the
/// original MusicThemeConfig defaults. Only the colors used by HomeVividHero.
class HomeArtworkPalette {
  const HomeArtworkPalette(
    this.primary,
    this.secondary,
    this.accent,
    this.vibrancy,
  );
  final Color primary, secondary, accent;
  final double vibrancy;
  static const fallback = HomeArtworkPalette(
    Color.from(alpha: 1, red: .184, green: .490, blue: .882),
    Color.from(alpha: 1, red: .435, green: .722, blue: .929),
    Color.from(alpha: 1, red: .231, green: .514, blue: .902),
    .62,
  );
  Color get glowPrimary => _glow(primary);
  Color get glowAccent => _glow(accent);
  static Color _glow(Color color) {
    final hsv = HSVColor.fromColor(color);
    final saturation = hsv.saturation < .16
        ? math.min(hsv.saturation * 1.10, .17)
        : (hsv.saturation * 1.18).clamp(.30, .82);
    return hsv
        .withSaturation(saturation)
        .withValue((hsv.value * 1.09).clamp(.70, .93))
        .toColor();
  }

  Color get backdrop {
    final mixed = Color.from(
      alpha: 1,
      red: (primary.r * .54 + secondary.r * .23 + accent.r * .17 + .030).clamp(
        0,
        1,
      ),
      green: (primary.g * .54 + secondary.g * .23 + accent.g * .17 + .030)
          .clamp(0, 1),
      blue: (primary.b * .54 + secondary.b * .23 + accent.b * .17 + .030).clamp(
        0,
        1,
      ),
    );
    final hsv = HSVColor.fromColor(mixed);
    final low = vibrancy < .32;
    final saturation = low
        ? (hsv.saturation * .80).clamp(
            hsv.saturation < .028 ? hsv.saturation : .048,
            .20,
          )
        : (hsv.saturation * .82).clamp(
            hsv.saturation < .035 ? hsv.saturation : .14,
            .30,
          );
    return hsv
        .withSaturation(saturation)
        .withValue(
          low
              ? (hsv.value * 1.04).clamp(.80, .93)
              : (hsv.value * 1.03).clamp(.75, .90),
        )
        .toColor();
  }

  /// Input is a bounded RGBA thumbnail; selection still samples at most 36x36.
  static HomeArtworkPalette fromRgba(Uint8List rgba, int width, int height) {
    final samples = <_Sample>[];
    for (var y = 0; y < height; y += math.max(1, height ~/ 36)) {
      for (var x = 0; x < width; x += math.max(1, width ~/ 36)) {
        final i = (y * width + x) * 4;
        final color = Color.fromARGB(
          rgba[i + 3],
          rgba[i],
          rgba[i + 1],
          rgba[i + 2],
        );
        final hsv = HSVColor.fromColor(color);
        if (color.a <= .2 || hsv.value <= .06 || hsv.value >= .985) continue;
        final preference = 1 - math.min((hsv.value - .56).abs() / .58, 1) * .26;
        final t = ((hsv.value - .135) / .285).clamp(0.0, 1.0);
        final emitter = math.max(
          .012,
          t * t * (3 - 2 * t) * (.60 + hsv.saturation * .62),
        );
        samples.add(_Sample(color, hsv, math.max(preference * emitter, .018)));
      }
    }
    if (samples.isEmpty) return fallback;
    final total = samples.fold(0.0, (n, s) => n + s.weight);
    final colorful =
        samples
            .where(
              (s) =>
                  s.hsv.saturation >= .18 &&
                  s.hsv.value >= .10 &&
                  s.hsv.value <= .97,
            )
            .fold(0.0, (n, s) => n + s.weight) /
        total;
    final vibrancy = (colorful / .24).clamp(0.0, 1.0);
    final buckets = List.filled(48, 0.0);
    for (final s in samples.where(
      (s) =>
          s.hsv.saturation >= .18 && s.hsv.value >= .12 && s.hsv.value <= .97,
    )) {
      final index = (s.hsv.hue / 360 * 48).floor().clamp(0, 47);
      buckets[index] += s.weight * (.52 + s.hsv.saturation * .78);
    }
    final hues =
        [
          for (var n = 0; n < 48; n++)
            if (buckets[n] > 0)
              (hue: (n + .5) / 48, weight: buckets[n], index: n),
        ]..sort((a, b) {
          final value = b.weight.compareTo(a.weight);
          return value != 0 ? value : a.index.compareTo(b.index);
        });
    if (colorful < .10) {
      final avg = _average(samples, neutral: true) ?? fallback.primary;
      final hsv = HSVColor.fromColor(avg);
      final brightness = (hsv.value * 1.02).clamp(.74, .88);
      // With the default neutral threshold .10, the original color-hint
      // threshold .11 cannot be met. Preserve its neutral branch exactly.
      Color gray(double value) => HSVColor.fromAHSV(1, 0, 0, value).toColor();
      return HomeArtworkPalette(
        gray(brightness),
        gray((brightness * 1.03).clamp(.66, .86)),
        gray((brightness * .92).clamp(.58, .80)),
        math.min(vibrancy, .30),
      );
    }
    double? dominant = hues.firstOrNull?.hue;
    if (dominant == null) {
      final fallbackBuckets = List.filled(36, 0.0);
      for (final s in samples.where(
        (s) =>
            s.hsv.saturation >= .16 && s.hsv.value >= .16 && s.hsv.value <= .96,
      )) {
        fallbackBuckets[(s.hsv.hue / 360 * 36).floor().clamp(0, 35)] +=
            s.weight * math.max(s.hsv.saturation, .12);
      }
      final max = fallbackBuckets.reduce(math.max);
      if (max > 0) dominant = (fallbackBuckets.indexOf(max) + .5) / 36;
    }
    final base =
        _average(samples, hue: dominant, distance: .11, saturation: .10) ??
        _average(samples, hue: dominant, distance: .18, saturation: .08) ??
        _average(samples, saturation: .06) ??
        fallback.primary;
    final primaryHue = dominant ?? HSVColor.fromColor(base).hue / 360;
    double? distinct(List<double> used, double distance, double fraction) =>
        hues
            .where(
              (h) =>
                  h.weight >= hues.first.weight * fraction &&
                  used.every((u) => _distance(h.hue, u) >= distance),
            )
            .firstOrNull
            ?.hue;
    final secondHue = distinct([primaryHue], .06, .12);
    final accentHue = distinct([primaryHue, secondHue ?? primaryHue], .08, .10);
    final secondary = _adjust(
      (secondHue == null
              ? null
              : _average(
                  samples,
                  hue: secondHue,
                  distance: .12,
                  saturation: .12,
                  brightness: .14,
                )) ??
          _shift(base, .040, .90, 1.10, .16, .62, .42, .94),
      .94,
      1.06,
      .14,
      .66,
      .40,
      .94,
    );
    final accent = _adjust(
      (accentHue == null
              ? null
              : _average(
                  samples,
                  hue: accentHue,
                  distance: .13,
                  saturation: .14,
                  brightness: .12,
                )) ??
          _shift(base, -.042, 1.08, .94, .20, .78, .34, .90),
      1.04,
      1.02,
      .18,
      .80,
      .32,
      .94,
    );
    return HomeArtworkPalette(
      _adjust(base, 1.14, 1, .22, .76, .22, .90),
      secondary,
      accent,
      vibrancy,
    );
  }
}

class _Sample {
  const _Sample(this.color, this.hsv, this.weight);
  final Color color;
  final HSVColor hsv;
  final double weight;
}

double _distance(double a, double b) =>
    math.min((a - b).abs(), 1 - (a - b).abs());
Color? _average(
  List<_Sample> samples, {
  bool neutral = false,
  double? hue,
  double distance = 1,
  double saturation = 0,
  double brightness = 0,
}) {
  var red = 0.0, green = 0.0, blue = 0.0, total = 0.0;
  for (final s in samples) {
    if (!neutral &&
        (s.hsv.value < brightness ||
            s.hsv.saturation < .12 ||
            s.hsv.saturation < saturation ||
            (hue != null && _distance(s.hsv.hue / 360, hue) > distance))) {
      continue;
    }
    final scale = neutral
        ? (1 - math.min((s.hsv.value - .72).abs() / .72, 1) * .18) *
              (s.hsv.saturation < .14 ? 1 : .28)
        : 1 - math.min((s.hsv.value - .55).abs() / .55, 1) * .45;
    final weight = s.weight * scale;
    red += s.color.r * weight;
    green += s.color.g * weight;
    blue += s.color.b * weight;
    total += weight;
  }
  if (total <= 0) return null;
  final hsv = HSVColor.fromColor(
    Color.from(
      alpha: 1,
      red: red / total,
      green: green / total,
      blue: blue / total,
    ),
  );
  if (neutral) {
    if (hsv.saturation < .055) {
      return HSVColor.fromAHSV(
        1,
        0,
        0,
        (hsv.value * 1.02).clamp(.62, .90),
      ).toColor();
    }
    return hsv
        .withSaturation(math.min(hsv.saturation * .50, .135))
        .withValue((hsv.value * 1.02).clamp(.66, .88))
        .toColor();
  }
  if (hsv.saturation < .05) {
    return HSVColor.fromAHSV(1, 0, 0, hsv.value.clamp(.22, .92)).toColor();
  }
  return hsv
      .withSaturation((hsv.saturation * 1.16).clamp(.18, .74))
      .withValue((hsv.value * 1.02).clamp(.32, .90))
      .toColor();
}

Color _adjust(
  Color color,
  double sat,
  double bri,
  double minSat,
  double maxSat,
  double minBri,
  double maxBri,
) {
  final hsv = HSVColor.fromColor(color);
  if (hsv.saturation < .12) {
    return HSVColor.fromAHSV(
      1,
      0,
      0,
      (hsv.value * bri).clamp(minBri, maxBri),
    ).toColor();
  }
  return hsv
      .withSaturation((hsv.saturation * sat).clamp(minSat, maxSat))
      .withValue((hsv.value * bri).clamp(minBri, maxBri))
      .toColor();
}

Color _shift(
  Color color,
  double hue,
  double sat,
  double bri,
  double minSat,
  double maxSat,
  double minBri,
  double maxBri,
) {
  final hsv = HSVColor.fromColor(color);
  return hsv
      .withHue((hsv.hue + hue * 360) % 360)
      .withSaturation((hsv.saturation * sat).clamp(minSat, maxSat))
      .withValue((hsv.value * bri).clamp(minBri, maxBri))
      .toColor();
}
