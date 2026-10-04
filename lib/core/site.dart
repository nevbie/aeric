import 'geo.dart';

/// A clockwise sector of wind directions (FROM), e.g. 270→360 = W to N.
/// A sector with from > to wraps through north, e.g. 315→45.
class WindSector {
  const WindSector(this.fromDeg, this.toDeg);

  final double fromDeg;
  final double toDeg;

  bool contains(double dirDeg) {
    final d = normalizeDegrees(dirDeg);
    final f = normalizeDegrees(fromDeg);
    final t = normalizeDegrees(toDeg);
    return f <= t ? d >= f && d <= t : d >= f || d <= t;
  }

  /// Degrees outside the sector (0 when inside).
  double distanceFrom(double dirDeg) => contains(dirDeg)
      ? 0
      : [angleDifference(dirDeg, fromDeg), angleDifference(dirDeg, toDeg)].reduce((a, b) => a < b ? a : b);
}

class Site {
  const Site({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.takeoffElevationM,
    this.landingElevationM,
    required this.sectors,
    this.minWindKmh = 0,
    this.maxWindKmh = 25,
    this.notes = '',
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double takeoffElevationM;
  final double? landingElevationM;
  final List<WindSector> sectors;

  /// Below this the site is still launchable, but not soarable.
  final double minWindKmh;
  final double maxWindKmh;
  final String notes;

  double sectorDistance(double dirDeg) => sectors.isEmpty
      ? 180
      : sectors.map((s) => s.distanceFrom(dirDeg)).reduce((a, b) => a < b ? a : b);
}
