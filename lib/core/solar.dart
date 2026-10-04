import 'dart:math' as math;

/// Sun elevation in degrees for a UTC instant (NOAA general solar position, ±0.5°).
double sunElevationDeg(double lat, double lon, DateTime utc) {
  final start = DateTime.utc(utc.year);
  final dayOfYear = utc.difference(start).inDays + 1;
  final hour = utc.hour + utc.minute / 60 + utc.second / 3600;
  final g = 2 * math.pi / 365 * (dayOfYear - 1 + (hour - 12) / 24);
  final eqTime = 229.18 *
      (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g));
  final decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g);
  final trueSolarMinutes = hour * 60 + eqTime + 4 * lon;
  final hourAngle = (trueSolarMinutes / 4 - 180) * math.pi / 180;
  final phi = lat * math.pi / 180;
  final cosZenith = math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * math.cos(hourAngle);
  return 90 - math.acos(cosZenith.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Clear-sky global horizontal irradiance in W/m² (Haurwitz model).
double clearSkyRadiation(double sunElevationDeg) {
  if (sunElevationDeg <= 0) return 0;
  final cosZ = math.sin(sunElevationDeg * math.pi / 180);
  return 1098 * cosZ * math.exp(-0.057 / cosZ);
}

/// Global radiation under [cloudCoverPct] cloud (Kasten & Czeplak 1980).
double cloudyRadiation(double clearSky, double cloudCoverPct) {
  final n = (cloudCoverPct / 100).clamp(0.0, 1.0);
  return clearSky * (1 - 0.75 * math.pow(n, 3.4));
}
