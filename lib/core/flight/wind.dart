import 'dart:math' as math;

import '../geo.dart';
import 'fix.dart';
import 'geo.dart';

class WindEstimate {
  const WindEstimate({required this.fromDeg, required this.speedKmh, required this.airspeedKmh, required this.quality});

  /// Direction the wind blows FROM.
  final double fromDeg;
  final double speedKmh;

  /// Average airspeed while circling.
  final double airspeedKmh;

  /// 0..1: how well the ground-speed vectors lie on a circle.
  final double quality;
}

/// Wind from drift while circling: at constant airspeed the ground-velocity vectors lie on a
/// circle whose centre is the wind vector (method used by XCTrack, LK8000 and others).
/// Least-squares circle fit (Kåsa) over one or more full turns.
WindEstimate? windFromCircling(List<Fix> fixes, {double minTurnDeg = 330}) {
  if (fixes.length < 6) return null;
  final vx = <double>[], vy = <double>[];
  double? prevHeading;
  var turned = 0.0;
  for (var i = 1; i < fixes.length; i++) {
    final a = fixes[i - 1], b = fixes[i];
    final dt = b.time.difference(a.time).inMilliseconds / 1000;
    final d = distanceM(a.lat, a.lon, b.lat, b.lon);
    if (dt <= 0 || d < 1) continue;
    final h = bearingDeg(a.lat, a.lon, b.lat, b.lon);
    final s = d / dt * 3.6;
    vx.add(s * math.sin(h * math.pi / 180)); // east
    vy.add(s * math.cos(h * math.pi / 180)); // north
    if (prevHeading != null) turned += turnDeg(prevHeading, h);
    prevHeading = h;
  }
  if (turned.abs() < minTurnDeg || vx.length < 6) return null;

  // Solve x² + y² + D x + E y + F = 0 in the least-squares sense.
  final n = vx.length.toDouble();
  double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0, sz = 0, sxz = 0, syz = 0;
  for (var i = 0; i < vx.length; i++) {
    final x = vx[i], y = vy[i], z = x * x + y * y;
    sx += x;
    sy += y;
    sxx += x * x;
    syy += y * y;
    sxy += x * y;
    sz += z;
    sxz += x * z;
    syz += y * z;
  }
  // Normal equations: [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]] · [D, E, F] = -[sxz, syz, sz]
  final m = [
    [sxx, sxy, sx, -sxz],
    [sxy, syy, sy, -syz],
    [sx, sy, n, -sz],
  ];
  final sol = _solve3(m);
  if (sol == null) return null;
  final cx = -sol[0] / 2, cy = -sol[1] / 2;
  final r2 = cx * cx + cy * cy - sol[2];
  if (r2 <= 0) return null;
  final r = math.sqrt(r2);

  var err = 0.0;
  for (var i = 0; i < vx.length; i++) {
    final d = math.sqrt(math.pow(vx[i] - cx, 2) + math.pow(vy[i] - cy, 2)) - r;
    err += d * d;
  }
  final rms = math.sqrt(err / vx.length);
  final speed = math.sqrt(cx * cx + cy * cy);
  return WindEstimate(
    // The centre points where the wind blows TO.
    fromDeg: normalizeDegrees(math.atan2(-cx, -cy) * 180 / math.pi),
    speedKmh: speed,
    airspeedKmh: r,
    quality: (1 - rms / r).clamp(0.0, 1.0),
  );
}

List<double>? _solve3(List<List<double>> m) {
  for (var c = 0; c < 3; c++) {
    var p = c;
    for (var r = c + 1; r < 3; r++) {
      if (m[r][c].abs() > m[p][c].abs()) p = r;
    }
    if (m[p][c].abs() < 1e-9) return null;
    final t = m[c];
    m[c] = m[p];
    m[p] = t;
    for (var r = 0; r < 3; r++) {
      if (r == c) continue;
      final f = m[r][c] / m[c][c];
      for (var k = c; k < 4; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  return [for (var i = 0; i < 3; i++) m[i][3] / m[i][i]];
}
