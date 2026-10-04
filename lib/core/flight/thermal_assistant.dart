import 'dart:math' as math;

import '../geo.dart';
import 'geo.dart';

/// A climb-rate reading at a position.
class LiftSample {
  const LiftSample(this.time, this.lat, this.lon, this.climbMs);
  final DateTime time;
  final double lat;
  final double lon;
  final double climbMs;
}

/// A lift reading placed relative to the pilot (metres east/north), drift-corrected.
class LiftPoint {
  const LiftPoint(this.eastM, this.northM, this.climbMs);
  final double eastM;
  final double northM;
  final double climbMs;
}

class ThermalAssist {
  const ThermalAssist({
    required this.points,
    required this.coreEastM,
    required this.coreNorthM,
    required this.coreClimbMs,
    required this.averageClimbMs,
  });

  /// Readings of the last circles, relative to the pilot now.
  final List<LiftPoint> points;

  /// Where the strongest lift is, relative to the pilot (metres east/north).
  final double coreEastM;
  final double coreNorthM;
  final double coreClimbMs;
  final double averageClimbMs;

  double get coreDistanceM => math.sqrt(coreEastM * coreEastM + coreNorthM * coreNorthM);
  double get coreBearingDeg => normalizeDegrees(math.atan2(coreEastM, coreNorthM) * 180 / math.pi);

  /// Bearing of the core relative to the track (−180..180, positive = right).
  double relativeToTrack(double trackDeg) => turnDeg(trackDeg, coreBearingDeg);
}

/// Thermal centering aid: keeps the climb rate around recent circles and finds where it was
/// strongest. Older readings are moved with the wind (the thermal drifts with the air mass),
/// so the map stays correct while circling in wind.
class ThermalAssistant {
  ThermalAssistant({this.window = const Duration(seconds: 60)});

  final Duration window;
  final List<LiftSample> _samples = [];

  void add(LiftSample s) {
    _samples.add(s);
    while (_samples.isNotEmpty && s.time.difference(_samples.first.time) > window) {
      _samples.removeAt(0);
    }
  }

  void clear() => _samples.clear();

  /// Lift map relative to ([lat], [lon]) at [now]. Needs about one full circle of readings.
  ThermalAssist? evaluate({
    required DateTime now,
    required double lat,
    required double lon,
    double windFromDeg = 0,
    double windKmh = 0,
  }) {
    if (_samples.length < 12) return null;
    final windTo = (windFromDeg + 180) % 360;
    final kx = 111320 * math.cos(lat * math.pi / 180), ky = 110540.0;
    final pts = <LiftPoint>[];
    for (final s in _samples) {
      final age = now.difference(s.time).inMilliseconds / 1000;
      final (la, lo) = windKmh > 0 ? destination(s.lat, s.lon, windTo, windKmh / 3.6 * age) : (s.lat, s.lon);
      pts.add(LiftPoint((lo - lon) * kx, (la - lat) * ky, s.climbMs));
    }
    final avg = pts.map((p) => p.climbMs).reduce((a, b) => a + b) / pts.length;
    // Weighted centre of the readings that were better than average.
    double sw = 0, se = 0, sn = 0, best = -1e9;
    for (final p in pts) {
      best = math.max(best, p.climbMs);
      final w = p.climbMs - avg;
      if (w <= 0) continue;
      sw += w;
      se += w * p.eastM;
      sn += w * p.northM;
    }
    if (sw == 0) return null; // uniform lift: nothing to correct
    return ThermalAssist(
      points: pts,
      coreEastM: se / sw,
      coreNorthM: sn / sw,
      coreClimbMs: best,
      averageClimbMs: avg,
    );
  }
}
