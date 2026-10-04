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

  Map<String, dynamic> toJson() => {'from': fromDeg, 'to': toDeg};
  factory WindSector.fromJson(Map<String, dynamic> j) =>
      WindSector((j['from'] as num).toDouble(), (j['to'] as num).toDouble());

  /// 45° sector centred on a compass point, e.g. "NW" → 292.5..337.5.
  static WindSector? ofCompass(String point) {
    const points = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final i = points.indexOf(point.trim().toUpperCase());
    if (i < 0) return null;
    final c = i * 45.0;
    return WindSector(normalizeDegrees(c - 22.5), normalizeDegrees(c + 22.5));
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
    this.landingLat,
    this.landingLon,
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

  /// Official landing field, when known (used for final glide).
  final double? landingLat;
  final double? landingLon;
  final List<WindSector> sectors;

  /// Below this the site is still launchable, but not soarable.
  final double minWindKmh;
  final double maxWindKmh;
  final String notes;

  bool get userDefined => id.startsWith('user-');

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'lat': lat, 'lon': lon, 'ele': takeoffElevationM,
        'landingEle': landingElevationM, 'sectors': [for (final s in sectors) s.toJson()],
        'maxWind': maxWindKmh, 'notes': notes,
      };

  factory Site.fromJson(Map<String, dynamic> j) => Site(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        takeoffElevationM: (j['ele'] as num).toDouble(),
        landingElevationM: (j['landingEle'] as num?)?.toDouble(),
        sectors: [for (final s in (j['sectors'] as List).cast<Map<String, dynamic>>()) WindSector.fromJson(s)],
        maxWindKmh: (j['maxWind'] as num?)?.toDouble() ?? 25,
        notes: j['notes'] as String? ?? '',
      );

  /// Degrees the wind is outside the launch sectors. A site without sectors (e.g. a point
  /// on the thermal map) accepts every direction.
  double sectorDistance(double dirDeg) =>
      sectors.isEmpty ? 0 : sectors.map((s) => s.distanceFrom(dirDeg)).reduce((a, b) => a < b ? a : b);
}
