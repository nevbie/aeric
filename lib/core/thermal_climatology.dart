import 'dart:math' as math;

import 'site.dart';
import 'thermal_model.dart';
import 'weather_hour.dart';

/// Rank of [value] within [samples] as a percentage (0 = lowest, 100 = highest), mid-rank for ties.
double percentileOf(double value, List<double> samples) {
  if (samples.isEmpty) return double.nan;
  var below = 0;
  var equal = 0;
  for (final s in samples) {
    if (s < value) {
      below++;
    } else if (s == value) {
      equal++;
    }
  }
  return 100 * (below + 0.5 * equal) / samples.length;
}

/// Linear-interpolated quantile, q in [0, 1].
double quantile(List<double> sorted, double q) {
  if (sorted.isEmpty) return double.nan;
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor();
  final hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

double _mean(Iterable<double> v) => v.isEmpty ? double.nan : v.reduce((a, b) => a + b) / v.length;

/// Historical statistics for one hour of the day.
class HourClimate {
  HourClimate._({
    required this.hour,
    required this.climbs,
    required this.meanTemp,
    required this.meanCloudCover,
    required this.meanWindKmh,
    required this.prevailingWindDir,
    required this.windSteadiness,
    required this.medianTopMslM,
    required this.cumulusFraction,
  });

  factory HourClimate.from(int hour, List<(WeatherHour, ThermalEstimate)> samples) {
    double u = 0, v = 0, speedSum = 0;
    for (final (h, _) in samples) {
      final rad = h.windDir10m * math.pi / 180;
      u += h.windSpeed10m * math.sin(rad);
      v += h.windSpeed10m * math.cos(rad);
      speedSum += h.windSpeed10m;
    }
    final dir = (math.atan2(u, v) * 180 / math.pi + 360) % 360;
    final tops = samples.where((s) => s.$2.thermalDepthM > 0).map((s) => s.$2.thermalTopMslM).toList()..sort();
    return HourClimate._(
      hour: hour,
      climbs: samples.map((s) => s.$2.climbMs).toList()..sort(),
      meanTemp: _mean(samples.map((s) => s.$1.temperature2m).whereType<double>()),
      meanCloudCover: _mean(samples.map((s) => s.$1.cloudCover).whereType<double>()),
      meanWindKmh: _mean(samples.map((s) => s.$1.windSpeed10m)),
      prevailingWindDir: dir,
      windSteadiness: speedSum == 0 ? 0 : math.sqrt(u * u + v * v) / speedSum,
      medianTopMslM: tops.isEmpty ? null : quantile(tops, 0.5),
      cumulusFraction: samples.isEmpty ? 0 : samples.where((s) => s.$2.cumulus).length / samples.length,
    );
  }

  final int hour;

  /// Estimated climb on every historical day at this hour, sorted ascending.
  final List<double> climbs;
  final double meanTemp;
  final double meanCloudCover;
  final double meanWindKmh;

  /// Speed-weighted vector mean of the wind direction (FROM).
  final double prevailingWindDir;

  /// 0 = direction all over the place, 1 = always from [prevailingWindDir].
  final double windSteadiness;
  final double? medianTopMslM;
  final double cumulusFraction;

  int get samples => climbs.length;
  double get medianClimb => quantile(climbs, 0.5);
  double get p25Climb => quantile(climbs, 0.25);
  double get p75Climb => quantile(climbs, 0.75);

  /// Share of historical days with usable thermals at this hour.
  double get usableFraction =>
      climbs.isEmpty ? 0 : climbs.where((c) => c >= ThermalModel.usableClimbMs).length / climbs.length;

  double percentile(double climb) => percentileOf(climb, climbs);
}

/// What thermals are typically like at a site at this time of year, built from historical
/// hourly weather of the same season in previous years.
class ThermalClimatology {
  ThermalClimatology._(this.site, this.days, this.hours, this.dailyPeakClimbs, this.firstDay, this.lastDay);

  factory ThermalClimatology.build(Site site, List<WeatherHour> history, {ThermalModel model = const ThermalModel()}) {
    final estimates = model.estimate(site, history);
    final byTime = {for (final e in estimates) e.time: e};
    final perHour = <int, List<(WeatherHour, ThermalEstimate)>>{};
    final peaks = <DateTime, double>{};
    for (final h in history) {
      final e = byTime[h.time]!;
      perHour.putIfAbsent(h.time.hour, () => []).add((h, e));
      final d = dateOf(h.time);
      peaks[d] = math.max(peaks[d] ?? 0, e.climbMs);
    }
    final days = peaks.keys.toList()..sort();
    return ThermalClimatology._(
      site,
      days.length,
      {for (final e in perHour.entries) e.key: HourClimate.from(e.key, e.value)},
      peaks.values.toList()..sort(),
      days.isEmpty ? null : days.first,
      days.isEmpty ? null : days.last,
    );
  }

  final Site site;
  final int days;
  final Map<int, HourClimate> hours;

  /// Each historical day's strongest climb, sorted ascending.
  final List<double> dailyPeakClimbs;
  final DateTime? firstDay;
  final DateTime? lastDay;

  bool get isEmpty => days == 0;
  HourClimate? at(int hour) => hours[hour];

  /// Share of historical days that had usable thermals at some point.
  double get usableDayFraction => dailyPeakClimbs.isEmpty
      ? 0
      : dailyPeakClimbs.where((c) => c >= ThermalModel.usableClimbMs).length / dailyPeakClimbs.length;

  double peakPercentile(double climb) => percentileOf(climb, dailyPeakClimbs);

  /// Typical thermal window: hours whose median climb is usable.
  (int, int)? get typicalWindow {
    final usable = hours.values.where((h) => h.medianClimb >= ThermalModel.usableClimbMs).map((h) => h.hour).toList()
      ..sort();
    return usable.isEmpty ? null : (usable.first, usable.last);
  }
}
