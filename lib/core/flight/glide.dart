import 'dart:math' as math;

import 'fix.dart';
import 'geo.dart';

/// Simple glider polar: speed and sink at trim (best glide is close to trim on paragliders).
class Polar {
  const Polar({this.trimKmh = 38, this.trimSinkMs = 1.1});
  final double trimKmh;
  final double trimSinkMs;

  double get glideRatio => trimKmh / 3.6 / trimSinkMs;
}

/// Glide ratio actually achieved over the given fixes (distance / height lost);
/// null while climbing or level.
double? currentGlideRatio(List<Fix> fixes) {
  if (fixes.length < 2) return null;
  var dist = 0.0;
  for (var i = 1; i < fixes.length; i++) {
    dist += distanceM(fixes[i - 1].lat, fixes[i - 1].lon, fixes[i].lat, fixes[i].lon);
  }
  final lost = fixes.first.altM - fixes.last.altM;
  if (lost < 2) return null;
  return dist / lost;
}

class FinalGlide {
  const FinalGlide({
    required this.distanceKm,
    required this.bearingDeg,
    required this.requiredGlideRatio,
    required this.groundSpeedKmh,
    required this.arrivalHeightM,
  });

  final double distanceKm;
  final double bearingDeg;

  /// Glide ratio needed to arrive with the safety margin; null = already below the margin.
  final double? requiredGlideRatio;

  /// Expected ground speed towards the goal at trim, with the wind.
  final double groundSpeedKmh;

  /// Height above the goal on arrival, after the safety margin (negative = won't make it).
  final double arrivalHeightM;

  bool get reachable => arrivalHeightM >= 0;
}

/// Final glide to a goal (landing field) at trim speed, with wind.
FinalGlide finalGlide({
  required double lat,
  required double lon,
  required double altM,
  required double goalLat,
  required double goalLon,
  required double goalElevationM,
  double windFromDeg = 0,
  double windKmh = 0,
  Polar polar = const Polar(),
  double safetyM = 150,
}) {
  final dist = distanceM(lat, lon, goalLat, goalLon);
  final course = bearingDeg(lat, lon, goalLat, goalLon);
  // Wind component along the course (tailwind positive) and across it.
  final windTo = (windFromDeg + 180) * math.pi / 180;
  final c = course * math.pi / 180;
  final along = windKmh * math.cos(windTo - c);
  final cross = windKmh * math.sin(windTo - c);
  final tas = polar.trimKmh;
  final gs = cross.abs() >= tas ? 0.0 : math.sqrt(tas * tas - cross * cross) + along;
  final usable = altM - goalElevationM - safetyM;
  final arrival = gs <= 0 ? -double.infinity : usable - dist / (gs / 3.6) * polar.trimSinkMs;
  return FinalGlide(
    distanceKm: dist / 1000,
    bearingDeg: course,
    requiredGlideRatio: usable > 0 ? dist / usable : null,
    groundSpeedKmh: math.max(0, gs),
    arrivalHeightM: arrival,
  );
}
