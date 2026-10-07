/// Decides when a live flight has landed.
///
/// Flying slower than walking pace is normal in the air: hovering into a strong wind while
/// ridge soaring gives a ground speed near zero for minutes. So "landed" needs all of these,
/// continuously for [holdSeconds]:
///  - ground speed below [maxSpeedKmh],
///  - vertical speed within ±[maxVarioMs],
///  - altitude within a band of [maxAltSpreadM] (in the air it always wanders by several metres),
///  - height above ground below [maxAglM] when the terrain height is known.
///
/// A landing only saves the flight; the instruments keep running until the pilot stops them.
class LandingDetector {
  LandingDetector({
    this.holdSeconds = 90,
    this.maxSpeedKmh = 3,
    this.maxVarioMs = 0.3,
    this.maxAltSpreadM = 6,
    this.maxAglM = 40,
  });

  final int holdSeconds;
  final double maxSpeedKmh;
  final double maxVarioMs;
  final double maxAltSpreadM;
  final double maxAglM;

  DateTime? _since;
  double _minAlt = double.infinity, _maxAlt = double.negativeInfinity;

  void reset() {
    _since = null;
    _minAlt = double.infinity;
    _maxAlt = double.negativeInfinity;
  }

  /// Feeds one fix. Returns true once the landing conditions have held for [holdSeconds].
  bool update({
    required DateTime time,
    required double groundSpeedKmh,
    required double varioMs,
    required double altM,
    double? aglM,
  }) {
    final still = groundSpeedKmh < maxSpeedKmh &&
        varioMs.abs() <= maxVarioMs &&
        (aglM == null || aglM < maxAglM);
    if (!still) {
      reset();
      return false;
    }
    if (_since == null) {
      _since = time;
      _minAlt = altM;
      _maxAlt = altM;
    } else {
      if (altM < _minAlt) _minAlt = altM;
      if (altM > _maxAlt) _maxAlt = altM;
      if (_maxAlt - _minAlt > maxAltSpreadM) {
        // Still drifting up or down: start over from this fix.
        _since = time;
        _minAlt = altM;
        _maxAlt = altM;
        return false;
      }
    }
    return time.difference(_since!).inSeconds >= holdSeconds;
  }
}
