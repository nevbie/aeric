import 'dart:math' as math;

import 'fix.dart';
import 'geo.dart';

/// A thermal found in a flight: where, when and how strong.
class ThermalSpot {
  const ThermalSpot({
    required this.lat,
    required this.lon,
    required this.start,
    required this.end,
    required this.baseAltM,
    required this.topAltM,
  });

  final double lat;
  final double lon;
  final DateTime start;
  final DateTime end;
  final double baseAltM;
  final double topAltM;

  double get gainM => topAltM - baseAltM;
  Duration get duration => end.difference(start);
  double get avgClimbMs => duration.inSeconds == 0 ? 0 : gainM / duration.inSeconds;

  Map<String, dynamic> toJson() => {
        'lat': lat, 'lon': lon, 'start': start.toIso8601String(), 'end': end.toIso8601String(),
        'base': baseAltM, 'top': topAltM,
      };

  factory ThermalSpot.fromJson(Map<String, dynamic> j) => ThermalSpot(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        baseAltM: (j['base'] as num).toDouble(),
        topAltM: (j['top'] as num).toDouble(),
      );
}

/// Summary of a flight for the logbook.
class FlightStats {
  const FlightStats({
    required this.takeoff,
    required this.landing,
    required this.maxAltM,
    required this.minAltM,
    required this.maxClimbMs,
    required this.maxSinkMs,
    required this.trackKm,
    required this.straightKm,
    required this.maxFromTakeoffKm,
    required this.thermals,
  });

  final Fix takeoff;
  final Fix landing;
  final double maxAltM;
  final double minAltM;

  /// Strongest / weakest 20 s average vertical speed.
  final double maxClimbMs;
  final double maxSinkMs;
  final double trackKm;

  /// Takeoff to landing.
  final double straightKm;

  /// Furthest point from takeoff.
  final double maxFromTakeoffKm;
  final List<ThermalSpot> thermals;

  Duration get airtime => landing.time.difference(takeoff.time);
}

/// Flight analysis: takeoff/landing, statistics and thermal detection.
class FlightAnalyzer {
  const FlightAnalyzer({
    this.flyingSpeedKmh = 12,
    this.flyingSeconds = 15,
    this.circlingWindowS = 30,
    this.circlingTurnDeg = 300,
    this.minThermalClimbMs = 0.5,
    this.minThermalGainM = 50,
  });

  final double flyingSpeedKmh;
  final int flyingSeconds;
  final int circlingWindowS;

  /// Turn needed inside [circlingWindowS] to count as circling.
  final double circlingTurnDeg;
  final double minThermalClimbMs;
  final double minThermalGainM;

  static double speedKmh(Fix a, Fix b) {
    final dt = b.time.difference(a.time).inMilliseconds / 1000;
    return dt <= 0 ? 0 : distanceM(a.lat, a.lon, b.lat, b.lon) / dt * 3.6;
  }

  /// Indices of the first and last fix in the air, or null if the track never flew.
  (int, int)? flightRange(List<Fix> f) {
    bool movingFrom(int i, int dir) {
      // Fast for [flyingSeconds] starting at i, looking forward (dir 1) or backward (-1).
      var j = i;
      while (true) {
        final k = j + dir;
        if (k < 0 || k >= f.length) return false;
        final a = dir > 0 ? f[j] : f[k], b = dir > 0 ? f[k] : f[j];
        if (speedKmh(a, b) < flyingSpeedKmh) return false;
        if ((f[k].time.difference(f[i].time).inSeconds).abs() >= flyingSeconds) return true;
        j = k;
      }
    }

    int? start, end;
    for (var i = 0; i < f.length; i++) {
      if (movingFrom(i, 1)) {
        start = i;
        break;
      }
    }
    for (var i = f.length - 1; i >= 0; i--) {
      if (movingFrom(i, -1)) {
        end = i;
        break;
      }
    }
    if (start == null || end == null || end <= start) return null;
    return (start, end);
  }

  FlightStats? analyze(List<Fix> all) {
    final fixes = all.where((f) => f.valid).toList();
    final range = flightRange(fixes);
    if (range == null) return null;
    final f = fixes.sublist(range.$1, range.$2 + 1);

    var track = 0.0, maxFrom = 0.0;
    var maxAlt = -1e9, minAlt = 1e9;
    for (var i = 0; i < f.length; i++) {
      if (i > 0) track += distanceM(f[i - 1].lat, f[i - 1].lon, f[i].lat, f[i].lon);
      maxFrom = math.max(maxFrom, distanceM(f.first.lat, f.first.lon, f[i].lat, f[i].lon));
      maxAlt = math.max(maxAlt, f[i].altM);
      minAlt = math.min(minAlt, f[i].altM);
    }
    var maxClimb = 0.0, maxSink = 0.0;
    var j = 0;
    for (var i = 0; i < f.length; i++) {
      while (j < i && f[i].time.difference(f[j].time).inSeconds > 20) {
        j++;
      }
      final dt = f[i].time.difference(f[j].time).inSeconds;
      if (dt >= 15) {
        final v = (f[i].altM - f[j].altM) / dt;
        maxClimb = math.max(maxClimb, v);
        maxSink = math.min(maxSink, v);
      }
    }
    return FlightStats(
      takeoff: f.first,
      landing: f.last,
      maxAltM: maxAlt,
      minAltM: minAlt,
      maxClimbMs: maxClimb,
      maxSinkMs: maxSink,
      trackKm: track / 1000,
      straightKm: distanceM(f.first.lat, f.first.lon, f.last.lat, f.last.lon) / 1000,
      maxFromTakeoffKm: maxFrom / 1000,
      thermals: thermals(f),
    );
  }

  /// Thermals: periods of circling (≥ [circlingTurnDeg] within [circlingWindowS]) while
  /// climbing, trimmed to the climbing part (lowest to highest point).
  List<ThermalSpot> thermals(List<Fix> f) {
    if (f.length < 3) return const [];
    // Track heading between consecutive fixes and the turn at each fix.
    final turn = List<double>.filled(f.length, 0);
    double? prevHeading;
    for (var i = 1; i < f.length; i++) {
      if (distanceM(f[i - 1].lat, f[i - 1].lon, f[i].lat, f[i].lon) < 2) continue;
      final h = bearingDeg(f[i - 1].lat, f[i - 1].lon, f[i].lat, f[i].lon);
      if (prevHeading != null) turn[i] = turnDeg(prevHeading, h);
      prevHeading = h;
    }
    // A fix is "circling" when the summed turn in the window around it is large enough.
    final circling = List<bool>.filled(f.length, false);
    var lo = 0;
    var sum = 0.0;
    for (var hi = 0; hi < f.length; hi++) {
      sum += turn[hi];
      while (f[hi].time.difference(f[lo].time).inSeconds > circlingWindowS) {
        sum -= turn[lo];
        lo++;
      }
      if (sum.abs() >= circlingTurnDeg) {
        for (var k = lo; k <= hi; k++) {
          circling[k] = true;
        }
      }
    }
    final out = <ThermalSpot>[];
    var i = 0;
    while (i < f.length) {
      if (!circling[i]) {
        i++;
        continue;
      }
      var e = i;
      while (e + 1 < f.length && circling[e + 1]) {
        e++;
      }
      final seg = f.sublist(i, e + 1);
      var minI = 0, maxI = 0;
      for (var k = 0; k < seg.length; k++) {
        if (seg[k].altM < seg[minI].altM) minI = k;
      }
      for (var k = minI; k < seg.length; k++) {
        if (seg[k].altM >= seg[maxI < minI ? minI : maxI].altM) maxI = k;
      }
      if (maxI > minI) {
        final climb = seg.sublist(minI, maxI + 1);
        final spot = ThermalSpot(
          lat: climb.map((x) => x.lat).reduce((a, b) => a + b) / climb.length,
          lon: climb.map((x) => x.lon).reduce((a, b) => a + b) / climb.length,
          start: climb.first.time,
          end: climb.last.time,
          baseAltM: climb.first.altM,
          topAltM: climb.last.altM,
        );
        if (spot.gainM >= minThermalGainM && spot.avgClimbMs >= minThermalClimbMs) out.add(spot);
      }
      i = e + 1;
    }
    return out;
  }
}
