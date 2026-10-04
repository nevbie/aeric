import 'dart:math' as math;

import '../geo.dart';
import '../weather_hour.dart';
import 'flight_analysis.dart';
import 'geo.dart';

/// The weather a thermal was flown in (or the weather of now), reduced to what decides where
/// thermals trigger: wind direction and strength, cloud cover, temperature.
class WeatherCondition {
  const WeatherCondition({required this.windFromDeg, required this.windKmh, this.cloudCover, this.temperatureC});

  factory WeatherCondition.of(WeatherHour h) => WeatherCondition(
        windFromDeg: h.windDir10m,
        windKmh: h.windSpeed10m,
        cloudCover: h.cloudCover,
        temperatureC: h.temperature2m,
      );

  factory WeatherCondition.fromJson(Map<String, dynamic> j) => WeatherCondition(
        windFromDeg: (j['dir'] as num).toDouble(),
        windKmh: (j['wind'] as num).toDouble(),
        cloudCover: (j['cloud'] as num?)?.toDouble(),
        temperatureC: (j['temp'] as num?)?.toDouble(),
      );

  final double windFromDeg;
  final double windKmh;
  final double? cloudCover;
  final double? temperatureC;

  Map<String, dynamic> toJson() => {'dir': windFromDeg, 'wind': windKmh, 'cloud': cloudCover, 'temp': temperatureC};
}

/// The weather hour closest to a UTC instant (weather times are local site time).
WeatherHour? weatherAt(List<WeatherHour> hours, DateTime utc) {
  WeatherHour? best;
  var bestDiff = 1 << 62;
  for (final h in hours) {
    final hUtc = DateTime.utc(h.time.year, h.time.month, h.time.day, h.time.hour, h.time.minute)
        .subtract(Duration(seconds: h.utcOffsetSeconds));
    final diff = hUtc.difference(utc).inSeconds.abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = h;
    }
  }
  return bestDiff <= 5400 ? best : null; // within 1.5 h
}

/// A thermal from a flight, tagged with the weather it was flown in.
class ConditionedThermal {
  const ConditionedThermal(this.spot, this.condition);
  final ThermalSpot spot;
  final WeatherCondition? condition;
}

/// Decides whether two weather situations are alike enough that thermals found in one are
/// likely in the other. Wind direction matters most (sun/lee side, house thermals of a
/// ridge), then wind strength (drift, torn thermals), then cloud cover.
class ConditionMatcher {
  const ConditionMatcher({
    this.windDirToleranceDeg = 45,
    this.windSpeedToleranceKmh = 10,
    this.calmKmh = 8,
    this.cloudTolerancepct = 35,
  });

  final double windDirToleranceDeg;
  final double windSpeedToleranceKmh;

  /// Below this the direction does not matter.
  final double calmKmh;
  final double cloudTolerancepct;

  bool matches(WeatherCondition a, WeatherCondition b) {
    final bothCalm = a.windKmh < calmKmh && b.windKmh < calmKmh;
    if (!bothCalm) {
      if ((a.windKmh < calmKmh) != (b.windKmh < calmKmh) &&
          (a.windKmh - b.windKmh).abs() > windSpeedToleranceKmh / 2) {
        return false;
      }
      if (a.windKmh >= calmKmh && b.windKmh >= calmKmh &&
          angleDifference(a.windFromDeg, b.windFromDeg) > windDirToleranceDeg) {
        return false;
      }
      if ((a.windKmh - b.windKmh).abs() > windSpeedToleranceKmh) return false;
    }
    final ca = a.cloudCover, cb = b.cloudCover;
    if (ca != null && cb != null && (ca - cb).abs() > cloudTolerancepct) return false;
    return true;
  }
}

/// Several thermals at about the same place, from different flights or days.
class ThermalHotspot {
  const ThermalHotspot({
    required this.lat,
    required this.lon,
    required this.thermals,
    required this.matching,
  });

  final double lat;
  final double lon;
  final List<ConditionedThermal> thermals;

  /// Thermals at this spot whose weather matched the reference condition.
  final List<ConditionedThermal> matching;

  int get count => thermals.length;
  double get avgClimbMs => thermals.map((t) => t.spot.avgClimbMs).reduce((a, b) => a + b) / count;
  double get maxTopM => thermals.map((t) => t.spot.topAltM).reduce(math.max);
  double get matchShare => count == 0 ? 0 : matching.length / count;

  /// Speed-weighted prevailing wind of the thermals at this spot (null if unknown or calm).
  double? get prevailingWindFromDeg {
    double u = 0, v = 0;
    for (final t in thermals) {
      final c = t.condition;
      if (c == null) continue;
      u += c.windKmh * math.sin(c.windFromDeg * math.pi / 180);
      v += c.windKmh * math.cos(c.windFromDeg * math.pi / 180);
    }
    if (u == 0 && v == 0) return null;
    return normalizeDegrees(math.atan2(u, v) * 180 / math.pi);
  }
}

/// Groups thermals within [radiusM] (greedy, strongest first) and marks which ones were flown in
/// conditions like [reference]. With [reference] null every thermal counts as matching.
List<ThermalHotspot> conditionalHotspots(
  Iterable<ConditionedThermal> thermals, {
  WeatherCondition? reference,
  ConditionMatcher matcher = const ConditionMatcher(),
  double radiusM = 400,
}) {
  final sorted = thermals.toList()..sort((a, b) => b.spot.avgClimbMs.compareTo(a.spot.avgClimbMs));
  final groups = <List<ConditionedThermal>>[];
  final centres = <(double, double)>[];
  for (final t in sorted) {
    var idx = -1;
    for (var g = 0; g < centres.length; g++) {
      if (distanceM(centres[g].$1, centres[g].$2, t.spot.lat, t.spot.lon) <= radiusM) {
        idx = g;
        break;
      }
    }
    if (idx < 0) {
      groups.add([t]);
      centres.add((t.spot.lat, t.spot.lon));
    } else {
      final g = groups[idx]..add(t);
      centres[idx] = (
        g.map((x) => x.spot.lat).reduce((a, b) => a + b) / g.length,
        g.map((x) => x.spot.lon).reduce((a, b) => a + b) / g.length,
      );
    }
  }
  bool match(ConditionedThermal t) =>
      reference == null || (t.condition != null && matcher.matches(t.condition!, reference));
  final out = [
    for (var g = 0; g < groups.length; g++)
      ThermalHotspot(lat: centres[g].$1, lon: centres[g].$2, thermals: groups[g], matching: groups[g].where(match).toList()),
  ];
  // Most reliable for the reference conditions first.
  out.sort((a, b) {
    final c = b.matching.length.compareTo(a.matching.length);
    return c != 0 ? c : b.avgClimbMs.compareTo(a.avgClimbMs);
  });
  return out;
}

/// kk7 thermal-map layer for a date and local hour: season (Jan/Apr/Jul/Oct ±1.5 months) and
/// time of day (morning/midday/evening after sunrise: `04`/`07`/`10`), e.g. `thermals_jul_07`.
String kk7Layer(String type, DateTime localTime, {double sunriseHour = 6.5}) {
  const seasons = ['jan', 'apr', 'jul', 'oct'];
  // Centre months 1, 4, 7, 10: Dec–Feb → jan, Mar–May → apr, Jun–Aug → jul, Sep–Nov → oct.
  final season = seasons[(localTime.month % 12) ~/ 3];
  final sinceSunrise = localTime.hour + localTime.minute / 60 - sunriseHour;
  // kk7: morning = 0–6 h, midday = 6–10 h, evening = later than 10 h after sunrise.
  final time = sinceSunrise < 6 ? '04' : sinceSunrise < 10 ? '07' : '10';
  return '${type}_${season}_$time';
}
