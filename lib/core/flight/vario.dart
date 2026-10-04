import 'dart:math' as math;

/// Standard sea-level pressure in hPa.
const standardPressureHpa = 1013.25;

/// Pressure altitude (ISA) in metres; with [qnhHpa] it becomes altitude above mean sea level.
double pressureToAltitudeM(double hPa, {double qnhHpa = standardPressureHpa}) =>
    44330.77 * (1 - math.pow(hPa / qnhHpa, 0.190263));

/// QNH that makes [hPa] read [knownAltitudeM] (e.g. set on takeoff at a known height).
double qnhFor(double hPa, double knownAltitudeM) => hPa / math.pow(1 - knownAltitudeM / 44330.77, 1 / 0.190263);

/// Two-state Kalman filter (altitude, vertical speed) for a noisy barometer.
/// Phone barometers are noisy (±0.3–1 m) and some (iPhone) deliver only ~1 Hz, so the filter
/// trades a little lag for a calm, usable vario.
class KalmanVario {
  KalmanVario({this.accelNoise = 0.6, this.altNoiseM = 0.5});

  /// Expected vertical acceleration (m/s²): higher = quicker but jumpier.
  final double accelNoise;

  /// Barometer altitude noise (m).
  final double altNoiseM;

  double? _h;
  double _v = 0;
  // Covariance matrix [[p00, p01], [p01, p11]].
  double _p00 = 10, _p01 = 0, _p11 = 10;
  DateTime? _t;

  double? get altitudeM => _h;
  double get verticalSpeedMs => _v;

  void reset() {
    _h = null;
    _v = 0;
    _p00 = 10;
    _p01 = 0;
    _p11 = 10;
    _t = null;
  }

  /// Adds a barometric altitude measurement and returns the filtered vertical speed.
  double update(DateTime t, double altitudeM) {
    if (_h == null || _t == null) {
      _h = altitudeM;
      _t = t;
      return _v;
    }
    final dt = t.difference(_t!).inMicroseconds / 1e6;
    _t = t;
    if (dt <= 0) return _v;

    // Predict.
    _h = _h! + _v * dt;
    final q = accelNoise * accelNoise;
    final dt2 = dt * dt;
    _p00 += dt * (2 * _p01 + dt * _p11) + q * dt2 * dt2 / 4;
    _p01 += dt * _p11 + q * dt2 * dt / 2;
    _p11 += q * dt2;

    // Correct.
    final r = altNoiseM * altNoiseM;
    final s = _p00 + r;
    final k0 = _p00 / s, k1 = _p01 / s;
    final y = altitudeM - _h!;
    _h = _h! + k0 * y;
    _v += k1 * y;
    final p00 = _p00, p01 = _p01;
    _p00 = (1 - k0) * p00;
    _p01 = (1 - k0) * p01;
    _p11 -= k1 * p01;
    return _v;
  }
}

/// Moving average of vertical speed over a time window (e.g. the 30 s "average climb").
class TimeAverage {
  TimeAverage(this.window);
  final Duration window;
  final _samples = <(DateTime, double)>[];

  void add(DateTime t, double v) {
    _samples.add((t, v));
    while (_samples.isNotEmpty && t.difference(_samples.first.$1) > window) {
      _samples.removeAt(0);
    }
  }

  double? get value =>
      _samples.isEmpty ? null : _samples.map((s) => s.$2).reduce((a, b) => a + b) / _samples.length;

  void clear() => _samples.clear();
}
