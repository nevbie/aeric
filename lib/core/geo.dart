/// Angle helpers. Directions are degrees clockwise from north (wind: direction it blows FROM).
library;

double normalizeDegrees(double deg) => ((deg % 360) + 360) % 360;

/// Smallest absolute difference between two headings, in [0, 180].
double angleDifference(double a, double b) {
  final d = normalizeDegrees(a - b);
  return d > 180 ? 360 - d : d;
}

const _compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

String compass(double deg) => _compass[((normalizeDegrees(deg) + 22.5) ~/ 45) % 8];
