import 'dart:math' as math;

import '../geo.dart';

const earthRadiusM = 6371008.8;

double _rad(double d) => d * math.pi / 180;

/// Great-circle distance in metres (haversine).
double distanceM(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Initial bearing from point 1 to point 2, degrees clockwise from north.
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _rad(lat1), p2 = _rad(lat2), dl = _rad(lon2 - lon1);
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return normalizeDegrees(math.atan2(y, x) * 180 / math.pi);
}

/// Point [distM] metres from (lat, lon) along [bearing].
(double, double) destination(double lat, double lon, double bearing, double distM) {
  final d = distM / earthRadiusM, b = _rad(bearing), p1 = _rad(lat), l1 = _rad(lon);
  final p2 = math.asin(math.sin(p1) * math.cos(d) + math.cos(p1) * math.sin(d) * math.cos(b));
  final l2 = l1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(p1), math.cos(d) - math.sin(p1) * math.sin(p2));
  return (p2 * 180 / math.pi, ((l2 * 180 / math.pi + 540) % 360) - 180);
}

/// Signed turn from heading [a] to heading [b] in (-180, 180].
double turnDeg(double a, double b) {
  final d = normalizeDegrees(b - a);
  return d > 180 ? d - 360 : d;
}
