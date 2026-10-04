import 'dart:convert';

/// One reading from an external (Bluetooth) vario. Any field may be missing.
class VarioSample {
  const VarioSample({
    this.pressureHpa,
    this.baroAltM,
    this.varioMs,
    this.lat,
    this.lon,
    this.gpsAltM,
    this.groundSpeedKmh,
    this.courseDeg,
    this.temperatureC,
    this.batteryPct,
    this.batteryV,
    required this.source,
  });

  final double? pressureHpa;

  /// Pressure altitude (QNE 1013.25) when the device sends altitude instead of pressure.
  final double? baroAltM;
  final double? varioMs;
  final double? lat;
  final double? lon;
  final double? gpsAltM;
  final double? groundSpeedKmh;
  final double? courseDeg;
  final double? temperatureC;
  final double? batteryPct;
  final double? batteryV;

  /// Sentence type, e.g. LK8EX1, LXWP0, XCTRC, POV, PRS, GPRMC.
  final String source;

  bool get hasPosition => lat != null && lon != null;
}

/// NMEA checksum: XOR of all characters between `$` and `*`.
bool nmeaChecksumOk(String line) {
  final star = line.lastIndexOf('*');
  if (!line.startsWith(r'$') || star < 0) return true; // no checksum given
  final given = int.tryParse(line.substring(star + 1).trim(), radix: 16);
  if (given == null) return false;
  var cs = 0;
  for (final c in line.substring(1, star).codeUnits) {
    cs ^= c;
  }
  return cs == given;
}

double? _d(List<String> f, int i) => i < f.length ? double.tryParse(f[i].trim()) : null;

/// "4807.038,N" → 48.1173
double? _nmeaCoord(String? v, String? hemi) {
  if (v == null || v.isEmpty) return null;
  final x = double.tryParse(v);
  if (x == null) return null;
  final deg = (x / 100).floorToDouble();
  final r = deg + (x - deg * 100) / 60;
  return hemi == 'S' || hemi == 'W' ? -r : r;
}

/// Parses one line from a vario. Supports LK8EX1, LXWP0, XCTRC (XC Tracer), POV (OpenVario),
/// PRS (BlueFly raw pressure), GPRMC/GNRMC and GPGGA/GNGGA. Returns null for anything else.
VarioSample? parseVarioLine(String raw) {
  final line = raw.trim();
  if (line.startsWith('PRS ')) {
    final pa = int.tryParse(line.substring(4).trim(), radix: 16);
    return pa == null ? null : VarioSample(pressureHpa: pa / 100, source: 'PRS');
  }
  if (!line.startsWith(r'$') || !nmeaChecksumOk(line)) return null;
  final body = line.contains('*') ? line.substring(1, line.lastIndexOf('*')) : line.substring(1);
  final f = body.split(',');
  switch (f.first) {
    case 'LK8EX1':
      final p = _d(f, 1), alt = _d(f, 2), v = _d(f, 3), t = _d(f, 4), b = _d(f, 5);
      return VarioSample(
        pressureHpa: p == null || p >= 999999 ? null : p / 100,
        baroAltM: alt == null || alt >= 99999 ? null : alt,
        varioMs: v == null || v >= 9999 ? null : v / 100,
        temperatureC: t == null || t >= 99 ? null : t,
        batteryPct: b != null && b >= 1000 && b <= 1100 ? b - 1000 : null,
        batteryV: b != null && b < 999 && b < 1000 ? b : null,
        source: 'LK8EX1',
      );
    case 'LXWP0':
      return VarioSample(baroAltM: _d(f, 3), varioMs: _d(f, 4), source: 'LXWP0');
    case 'XCTRC':
      // $XCTRC,year,month,day,hour,minute,second,centisecond,lat,lon,altitude,speed,course,climb,,,,pressure,battery
      return VarioSample(
        lat: _d(f, 8),
        lon: _d(f, 9),
        gpsAltM: _d(f, 10),
        groundSpeedKmh: _d(f, 11),
        courseDeg: _d(f, 12),
        varioMs: _d(f, 13),
        pressureHpa: _d(f, 17),
        batteryPct: _d(f, 18),
        source: 'XCTRC',
      );
    case 'POV':
      // $POV,P,1018.35,E,1.23,T,23.4,V,3.9  (pairs of type,value)
      double? p, e, t, volt;
      for (var i = 1; i + 1 < f.length; i += 2) {
        final v = double.tryParse(f[i + 1]);
        switch (f[i]) {
          case 'P':
            p = v;
          case 'E':
            e = v;
          case 'T':
            t = v;
          case 'V':
            volt = v;
        }
      }
      return VarioSample(pressureHpa: p, varioMs: e, temperatureC: t, batteryV: volt, source: 'POV');
    case 'GPRMC' || 'GNRMC':
      if (f.length < 9 || f[2] != 'A') return null;
      final kn = _d(f, 7);
      return VarioSample(
        lat: _nmeaCoord(f[3], f[4]),
        lon: _nmeaCoord(f[5], f[6]),
        groundSpeedKmh: kn == null ? null : kn * 1.852,
        courseDeg: _d(f, 8),
        source: f.first,
      );
    case 'GPGGA' || 'GNGGA':
      if (f.length < 10 || f[6] == '0') return null;
      return VarioSample(lat: _nmeaCoord(f[2], f[3]), lon: _nmeaCoord(f[4], f[5]), gpsAltM: _d(f, 9), source: f.first);
  }
  return null;
}

/// Turns BLE notification chunks (lines split anywhere) into complete lines.
class LineAssembler {
  final _buf = StringBuffer();

  List<String> add(List<int> bytes) {
    _buf.write(latin1.decode(bytes, allowInvalid: true));
    final text = _buf.toString();
    final parts = text.split(RegExp(r'\r?\n'));
    _buf
      ..clear()
      ..write(parts.removeLast()); // incomplete tail
    if (_buf.length > 512) _buf.clear(); // garbage without newlines
    return parts.where((l) => l.trim().isNotEmpty).toList();
  }
}
