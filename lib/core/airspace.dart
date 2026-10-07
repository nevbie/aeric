import 'dart:math' as math;

import 'flight/geo.dart';

enum AltitudeRef { msl, agl, fl, unlimited }

/// A floor or ceiling of an airspace.
class AltitudeLimit {
  const AltitudeLimit(this.value, this.ref, {this.text = ''});

  static const ground = AltitudeLimit(0, AltitudeRef.agl, text: 'GND');
  static const unlimited = AltitudeLimit(0, AltitudeRef.unlimited, text: 'UNL');

  /// Metres (MSL/AGL) or the flight level number (FL).
  final double value;
  final AltitudeRef ref;
  final String text;

  /// Height above mean sea level. FL is converted with [qnhHpa] (≈ 8.3 m per hPa off standard).
  double toMslM({double groundM = 0, double qnhHpa = 1013.25}) => switch (ref) {
        AltitudeRef.msl => value,
        AltitudeRef.agl => groundM + value,
        AltitudeRef.fl => value * 100 * 0.3048 + (qnhHpa - 1013.25) * 8.3,
        AltitudeRef.unlimited => double.infinity,
      };

  /// Parses OpenAIR limits: GND, SFC, UNL, FL95, FL 95, 2500ft MSL, 2500 ft, 1500ft AGL,
  /// 1500 GND, 1000m, 1000 m AMSL, 4500 ALT.
  ///
  /// A limit that can't be read errs on the safe side: as a floor it becomes the ground, as a
  /// [ceiling] unlimited, so the airspace is never silently ignored.
  static AltitudeLimit parse(String raw, {bool ceiling = false}) {
    final s = raw.trim().toUpperCase();
    final unreadable = ceiling
        ? AltitudeLimit(0, AltitudeRef.unlimited, text: raw.trim())
        : AltitudeLimit(0, AltitudeRef.agl, text: raw.trim());
    if (s.isEmpty) return unreadable;
    if (s == 'GND' || s == 'SFC' || s == '0' || s.startsWith('GND ') || s == 'GROUND') return AltitudeLimit(0, AltitudeRef.agl, text: raw.trim());
    if (s.startsWith('UNL') || s == 'UNLIMITED') return AltitudeLimit(0, AltitudeRef.unlimited, text: raw.trim());
    final fl = RegExp(r'^FL\s*(\d+)').firstMatch(s);
    if (fl != null) return AltitudeLimit(double.parse(fl.group(1)!), AltitudeRef.fl, text: raw.trim());
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(FT|F|M)?\s*(.*)$').firstMatch(s);
    if (m == null) return unreadable;
    var v = double.parse(m.group(1)!);
    if (m.group(2) != 'M') v *= 0.3048; // feet by default
    final rest = m.group(3) ?? '';
    final agl = rest.contains('AGL') || rest.contains('GND') || rest.contains('SFC') || rest.contains('ASFC');
    return AltitudeLimit(v, agl ? AltitudeRef.agl : AltitudeRef.msl, text: raw.trim());
  }
}

class Airspace {
  Airspace({required this.cls, required this.name, required this.floor, required this.ceiling, required this.polygon});

  /// OpenAIR class: R, Q, P, A–G, CTR, TMZ, RMZ, W, GP, …
  final String cls;
  final String name;
  final AltitudeLimit floor;
  final AltitudeLimit ceiling;

  /// Outline as (lat, lon).
  final List<(double, double)> polygon;

  late final (double, double, double, double) bbox = () {
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final (la, lo) in polygon) {
      minLat = math.min(minLat, la);
      maxLat = math.max(maxLat, la);
      minLon = math.min(minLon, lo);
      maxLon = math.max(maxLon, lo);
    }
    return (minLat, minLon, maxLat, maxLon);
  }();

  String get limitsLabel => '${floor.text} – ${ceiling.text}';

  /// Point in polygon (ray casting in lat/lon; fine at airspace scale).
  bool containsPoint(double lat, double lon) {
    final (a, b, c, d) = bbox;
    if (lat < a || lat > c || lon < b || lon > d) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final (yi, xi) = polygon[i];
      final (yj, xj) = polygon[j];
      if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  /// Distance in metres from a point to the outline (0 when inside).
  double distanceM(double lat, double lon) {
    if (containsPoint(lat, lon)) return 0;
    final kx = 111320 * math.cos(lat * math.pi / 180), ky = 110540.0;
    var best = double.infinity;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final ax = (polygon[j].$2 - lon) * kx, ay = (polygon[j].$1 - lat) * ky;
      final bx = (polygon[i].$2 - lon) * kx, by = (polygon[i].$1 - lat) * ky;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      best = math.min(best, math.sqrt(px * px + py * py));
    }
    return best;
  }
}

double? _coord(String s, String hemis) {
  final m = RegExp(r'(\d+)[:\s]+(\d+(?:\.\d+)?)(?:[:\s]+(\d+(?:\.\d+)?))?\s*([' + hemis + r'])', caseSensitive: false)
      .firstMatch(s);
  if (m == null) return null;
  var v = int.parse(m.group(1)!) + double.parse(m.group(2)!) / 60;
  if (m.group(3) != null) v += double.parse(m.group(3)!) / 3600;
  final h = m.group(4)!.toUpperCase();
  return h == 'S' || h == 'W' ? -v : v;
}

/// "48:45:30 N 008:15:42 E" / "48:45.5N 8:15.7E" → (lat, lon).
(double, double)? parseOpenAirPoint(String s) {
  final lat = _coord(s, 'NS');
  if (lat == null) return null;
  final rest = s.substring(s.toUpperCase().indexOf(RegExp('[NS]')) + 1);
  final lon = _coord(rest, 'EW');
  return lon == null ? null : (lat, lon);
}

const _nm = 1852.0;

/// Parses an OpenAIR file. Unknown records are ignored; arcs and circles become polygons
/// (5° steps).
List<Airspace> parseOpenAir(String text) {
  final out = <Airspace>[];
  String? cls, name;
  var floor = AltitudeLimit.ground, ceiling = AltitudeLimit.unlimited;
  var points = <(double, double)>[];
  (double, double)? center;
  var clockwise = true;

  void flush() {
    if (cls != null && points.length >= 3) {
      out.add(Airspace(cls: cls!, name: name ?? '', floor: floor, ceiling: ceiling, polygon: points));
    }
    cls = null;
    name = null;
    floor = AltitudeLimit.ground;
    ceiling = AltitudeLimit.unlimited;
    points = [];
    center = null;
    clockwise = true;
  }

  void arc(double radiusM, double fromBearing, double toBearing) {
    final c = center;
    if (c == null) return;
    var sweep = clockwise ? (toBearing - fromBearing) % 360 : -((fromBearing - toBearing) % 360);
    if (sweep == 0) sweep = clockwise ? 360 : -360;
    final steps = math.max(2, (sweep.abs() / 5).ceil());
    for (var i = 0; i <= steps; i++) {
      points.add(destination(c.$1, c.$2, fromBearing + sweep * i / steps, radiusM));
    }
  }

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.split('*').first.trim(); // '*' starts a comment
    if (line.length < 2) continue;
    final key = line.split(RegExp(r'\s')).first.toUpperCase();
    final arg = line.substring(key.length).trim();
    switch (key) {
      case 'AC':
        flush();
        cls = arg.toUpperCase();
      case 'AN':
        name = arg;
      case 'AL':
        floor = AltitudeLimit.parse(arg);
      case 'AH':
        ceiling = AltitudeLimit.parse(arg, ceiling: true);
      case 'DP':
        final p = parseOpenAirPoint(arg);
        if (p != null) points.add(p);
      case 'V':
        final kv = arg.split('=');
        if (kv.length == 2) {
          final k = kv[0].trim().toUpperCase(), v = kv[1].trim();
          if (k == 'X') center = parseOpenAirPoint(v);
          if (k == 'D') clockwise = v != '-';
        }
      case 'DC':
        final r = double.tryParse(arg.replaceAll(',', '.'));
        if (r != null) {
          clockwise = true;
          arc(r * _nm, 0, 0);
        }
      case 'DA':
        final parts = arg.split(',').map((x) => double.tryParse(x.trim())).toList();
        if (parts.length == 3 && !parts.contains(null)) arc(parts[0]! * _nm, parts[1]!, parts[2]!);
      case 'DB':
        final c = center;
        final ends = arg.split(',');
        if (c != null && ends.length >= 2) {
          // The two coordinates may be "lat lon, lat lon" – split at the second latitude.
          final p1 = parseOpenAirPoint(ends.first);
          final p2 = parseOpenAirPoint(ends.sublist(1).join(','));
          if (p1 != null && p2 != null) {
            final r = (distanceM(c.$1, c.$2, p1.$1, p1.$2) + distanceM(c.$1, c.$2, p2.$1, p2.$2)) / 2;
            arc(r, bearingDeg(c.$1, c.$2, p1.$1, p1.$2), bearingDeg(c.$1, c.$2, p2.$1, p2.$2));
          }
        }
    }
  }
  flush();
  return out;
}

enum AirspaceLevel { inside, warning, info }

class AirspaceWarning {
  const AirspaceWarning({
    required this.airspace,
    required this.level,
    required this.horizontalM,
    required this.verticalM,
    required this.predicted,
  });

  final Airspace airspace;
  final AirspaceLevel level;

  /// Horizontal distance to the outline (0 when inside).
  final double horizontalM;

  /// Vertical distance to the band floor/ceiling (0 when within it).
  final double verticalM;

  /// True when only the predicted position (in [AirspaceChecker.lookahead]) is inside.
  final bool predicted;

  String get text {
    final a = airspace;
    if (level == AirspaceLevel.inside && !predicted) return 'INSIDE ${a.cls} ${a.name} (${a.limitsLabel})';
    if (predicted) return '${a.cls} ${a.name} ahead – ${horizontalM.round()} m (${a.limitsLabel})';
    return '${a.cls} ${a.name}: ${horizontalM.round()} m away, ${verticalM.round()} m vertically (${a.limitsLabel})';
  }
}

/// Checks a position (and where it will be soon) against airspaces.
class AirspaceChecker {
  const AirspaceChecker({
    this.horizontalWarnM = 1000,
    this.verticalWarnM = 150,
    this.lookahead = const Duration(seconds: 60),
    this.ignoredClasses = const {'E', 'F', 'G', 'W', 'GP', 'GSEC'},
  });

  final double horizontalWarnM;
  final double verticalWarnM;
  final Duration lookahead;
  final Set<String> ignoredClasses;

  List<AirspaceWarning> check(
    List<Airspace> airspaces, {
    required double lat,
    required double lon,
    required double altM,
    double? groundM,
    double qnhHpa = 1013.25,
    double? trackDeg,
    double groundSpeedKmh = 0,
  }) {
    final ahead = trackDeg == null || groundSpeedKmh < 5
        ? null
        : destination(lat, lon, trackDeg, groundSpeedKmh / 3.6 * lookahead.inSeconds);
    final out = <AirspaceWarning>[];
    for (final a in airspaces) {
      if (ignoredClasses.contains(a.cls)) continue;
      // Terrain height unknown: assume sea level for floors (lower) and no limit for ceilings
      // given above ground, so warnings err on the safe side.
      final lo = a.floor.toMslM(groundM: groundM ?? 0, qnhHpa: qnhHpa);
      final hi = groundM == null && a.ceiling.ref == AltitudeRef.agl
          ? double.infinity
          : a.ceiling.toMslM(groundM: groundM ?? 0, qnhHpa: qnhHpa);
      final vertical = altM < lo ? lo - altM : (altM > hi ? altM - hi : 0.0);
      if (vertical > verticalWarnM) continue;
      // Quick reject far away airspaces.
      final (minLat, minLon, maxLat, maxLon) = a.bbox;
      const pad = 0.05;
      if (lat < minLat - pad || lat > maxLat + pad || lon < minLon - pad || lon > maxLon + pad) continue;
      final h = a.distanceM(lat, lon);
      final inBand = vertical == 0;
      if (h == 0 && inBand) {
        out.add(AirspaceWarning(airspace: a, level: AirspaceLevel.inside, horizontalM: 0, verticalM: 0, predicted: false));
      } else if (ahead != null && inBand && a.containsPoint(ahead.$1, ahead.$2)) {
        out.add(AirspaceWarning(airspace: a, level: AirspaceLevel.inside, horizontalM: h, verticalM: 0, predicted: true));
      } else if (h <= horizontalWarnM) {
        out.add(AirspaceWarning(
          airspace: a,
          level: inBand ? AirspaceLevel.warning : AirspaceLevel.info,
          horizontalM: h,
          verticalM: vertical,
          predicted: false,
        ));
      }
    }
    out.sort((x, y) {
      final c = x.level.index.compareTo(y.level.index);
      return c != 0 ? c : x.horizontalM.compareTo(y.horizontalM);
    });
    return out;
  }
}
