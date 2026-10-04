import 'geo.dart';
import 'site.dart';
import 'thermal_climatology.dart';
import 'thermal_model.dart';
import 'weather_hour.dart';

String _hh(int h) => '${h.toString().padLeft(2, '0')}:00';
String _signed(double v, [int digits = 1]) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(digits)}';

/// The live thermal picture at a site: today's estimate for the current hour, set against
/// how today has developed so far and against the same season in previous years.
class LiveThermalReport {
  const LiveThermalReport({
    required this.site,
    required this.now,
    required this.weatherNow,
    required this.current,
    required this.today,
    required this.weatherToday,
    required this.climate,
    required this.climatology,
    required this.percentileNow,
    required this.peak,
    required this.peakPercentile,
    required this.window,
    required this.comparisons,
    required this.trends,
  });

  final Site site;
  final DateTime now;
  final WeatherHour? weatherNow;
  final ThermalEstimate? current;
  final List<ThermalEstimate> today;
  final List<WeatherHour> weatherToday;

  /// Historical statistics for the current hour of day.
  final HourClimate? climate;
  final ThermalClimatology? climatology;

  /// How the current estimate ranks against the same hour on historical days (0–100).
  final double? percentileNow;

  /// Strongest hour today and its rank among historical daily peaks.
  final ThermalEstimate? peak;
  final double? peakPercentile;

  /// First and last hour with usable thermals today.
  final (DateTime, DateTime)? window;

  /// Today vs. the historical norm (temperature, cloud cover, wind).
  final List<String> comparisons;

  /// How conditions have changed over the last hours and will change next.
  final List<String> trends;

  String get headline {
    final c = current;
    if (c == null) return 'No data for the current hour';
    if (!c.usable) {
      final p = peak;
      if (p != null && p.usable && p.time.isAfter(now)) {
        return 'No usable thermals yet – expected from ${_hh(window!.$1.hour)}';
      }
      return 'No usable thermals right now';
    }
    return '${c.strength.label} thermals now: ≈ ${c.climbMs.toStringAsFixed(1)} m/s, '
        '${c.cumulus ? 'cloud base' : 'top'} ≈ ${(c.thermalTopMslM / 100).round() * 100} m';
  }

  static LiveThermalReport infer({
    required Site site,
    required List<WeatherHour> hours,
    required DateTime now,
    ThermalClimatology? climatology,
    ThermalModel model = const ThermalModel(),
  }) {
    final day = dateOf(now);
    final weatherToday = hours.where((h) => dateOf(h.time) == day).toList()..sort((a, b) => a.time.compareTo(b.time));
    final today = model.estimateDay(site, weatherToday);

    final idx = weatherToday.lastIndexWhere((h) => !h.time.isAfter(now));
    final weatherNow = idx >= 0 ? weatherToday[idx] : null;
    final current = idx >= 0 ? today[idx] : null;
    final climate = weatherNow == null ? null : climatology?.at(weatherNow.time.hour);

    final usable = today.where((e) => e.usable).toList();
    final window = usable.isEmpty ? null : (usable.first.time, usable.last.time);
    final daylight = today.where((e) => e.radiationWm2 > 0).toList();
    final peak = daylight.isEmpty ? null : daylight.reduce((a, b) => b.climbMs > a.climbMs ? b : a);

    final comparisons = <String>[];
    double? pctNow;
    if (weatherNow != null && current != null && climate != null && climate.samples > 0) {
      final at = _hh(weatherNow.time.hour);
      final t = weatherNow.temperature2m;
      if (t != null && !climate.meanTemp.isNaN) {
        final d = t - climate.meanTemp;
        comparisons.add('Temperature ${t.toStringAsFixed(1)} °C – ${_signed(d)} °C vs. the usual ${climate.meanTemp.toStringAsFixed(1)} °C at $at');
      }
      final cc = weatherNow.cloudCover;
      if (cc != null && !climate.meanCloudCover.isNaN) {
        comparisons.add('Cloud cover ${cc.round()} % – usually ${climate.meanCloudCover.round()} %');
      }
      final steady = climate.windSteadiness >= 0.4;
      comparisons.add(
        'Wind ${weatherNow.windSpeed10m.round()} km/h ${compass(weatherNow.windDir10m)} – usually '
        '${climate.meanWindKmh.round()} km/h${steady ? ' ${compass(climate.prevailingWindDir)}' : ', variable'}',
      );
      if (steady && weatherNow.windSpeed10m >= 8 && angleDifference(weatherNow.windDir10m, climate.prevailingWindDir) >= 90) {
        comparisons.add('Unusual wind direction for this site and season – local thermal patterns may not apply');
      }
      pctNow = climate.percentile(current.climbMs);
      comparisons.add(
        'Thermals stronger than ${pctNow.round()} % of historical days at $at '
        '(typical ${climate.medianClimb.toStringAsFixed(1)} m/s, usable on ${(climate.usableFraction * 100).round()} % of days)',
      );
    }
    double? peakPct;
    if (peak != null && climatology != null && !climatology.isEmpty) {
      peakPct = climatology.peakPercentile(peak.climbMs);
    }

    final trends = <String>[];
    if (idx >= 0) {
      final prev = idx >= 2 ? weatherToday[idx - 2] : null;
      final w = weatherToday[idx];
      if (prev != null) {
        final t0 = prev.temperature2m, t1 = w.temperature2m;
        if (t0 != null && t1 != null) {
          final rate = (t1 - t0) / 2;
          if (rate >= 1) {
            trends.add('Ground heating fast (${_signed(rate)} °C/h)');
          } else if (rate <= -0.5) {
            trends.add('Cooling (${_signed(rate)} °C/h) – thermals dying off');
          }
        }
        final c0 = prev.cloudCover, c1 = w.cloudCover;
        if (c0 != null && c1 != null) {
          if (c1 - c0 >= 25) {
            trends.add('Clouds building fast (${_signed(c1 - c0, 0)} % in 2 h) – shading or over-development');
          } else if (c0 - c1 >= 25) {
            trends.add('Clearing up (${_signed(c1 - c0, 0)} % cloud in 2 h)');
          }
        }
        if (w.windSpeed10m - prev.windSpeed10m >= 8) {
          trends.add('Wind picking up (${_signed(w.windSpeed10m - prev.windSpeed10m, 0)} km/h in 2 h)');
        }
      }
      if (peak != null && current != null) {
        if (peak.time.isAfter(w.time) && peak.climbMs - current.climbMs >= 0.3) {
          trends.add('Strengthening until ≈ ${_hh(peak.time.hour)} (≈ ${peak.climbMs.toStringAsFixed(1)} m/s)');
        } else if (peak.time.isBefore(w.time) && current.usable) {
          trends.add('Past today\'s peak at ${_hh(peak.time.hour)} – weakening');
        } else if (current.usable) {
          trends.add('Near today\'s peak (≈ ${_hh(peak.time.hour)})');
        }
      }
      if (window != null && current != null && current.usable && window.$2.isAfter(w.time)) {
        trends.add('Usable until ≈ ${_hh(window.$2.hour + 1)}');
      }
    }

    return LiveThermalReport(
      site: site,
      now: now,
      weatherNow: weatherNow,
      current: current,
      today: today,
      weatherToday: weatherToday,
      climate: climate,
      climatology: climatology,
      percentileNow: pctNow,
      peak: peak,
      peakPercentile: peakPct,
      window: window,
      comparisons: comparisons,
      trends: trends,
    );
  }
}
