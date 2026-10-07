import 'fix.dart';

/// A parsed IGC flight log.
class IgcFlight {
  const IgcFlight({required this.fixes, this.pilot, this.glider, this.date});

  final List<Fix> fixes;
  final String? pilot;
  final String? glider;
  final DateTime? date;
}

String _two(int v) => v.toString().padLeft(2, '0');

String _alt(double? m) {
  if (m == null) return '00000';
  final v = m.round().clamp(-9999, 99999);
  return v < 0 ? '-${(-v).toString().padLeft(4, '0')}' : v.toString().padLeft(5, '0');
}

String _coord(double v, bool isLat) {
  final hemi = isLat ? (v >= 0 ? 'N' : 'S') : (v >= 0 ? 'E' : 'W');
  final a = v.abs();
  var deg = a.floor();
  var milliMin = ((a - deg) * 60000).round();
  if (milliMin == 60000) {
    deg += 1;
    milliMin = 0;
  }
  return '${deg.toString().padLeft(isLat ? 2 : 3, '0')}${milliMin.toString().padLeft(5, '0')}$hemi';
}

/// Parses the IGC format (FAI): H-record date/pilot/glider and B-record fixes.
/// Handles both `HFDTE010726` and `HFDTEDATE:010726,01` and flights across midnight UTC.
IgcFlight parseIgc(String text) {
  DateTime? date;
  String? pilot, glider;
  final fixes = <Fix>[];
  var dayOffset = 0;
  int? lastSeconds;

  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.startsWith('HFDTE')) {
      final m = RegExp(r'(\d{2})(\d{2})(\d{2})').firstMatch(line.substring(5));
      if (m != null) {
        final yy = int.parse(m.group(3)!);
        date = DateTime.utc(yy < 80 ? 2000 + yy : 1900 + yy, int.parse(m.group(2)!), int.parse(m.group(1)!));
      }
    } else if (line.startsWith('HFPLT')) {
      pilot = _headerValue(line);
    } else if (line.startsWith('HFGTY')) {
      glider = _headerValue(line);
    } else if (line.startsWith('B') && line.length >= 35) {
      final h = int.tryParse(line.substring(1, 3));
      final mi = int.tryParse(line.substring(3, 5));
      final s = int.tryParse(line.substring(5, 7));
      final latDeg = int.tryParse(line.substring(7, 9));
      final latMin = int.tryParse(line.substring(9, 14));
      final lonDeg = int.tryParse(line.substring(15, 18));
      final lonMin = int.tryParse(line.substring(18, 23));
      final pAlt = int.tryParse(line.substring(25, 30));
      final gAlt = int.tryParse(line.substring(30, 35));
      if ([h, mi, s, latDeg, latMin, lonDeg, lonMin, gAlt].contains(null)) continue;
      final seconds = h! * 3600 + mi! * 60 + s!;
      if (lastSeconds != null && seconds < lastSeconds - 3600) dayOffset++; // crossed midnight UTC
      lastSeconds = seconds;
      var lat = latDeg! + latMin! / 60000;
      var lon = lonDeg! + lonMin! / 60000;
      if (line[14] == 'S') lat = -lat;
      if (line[23] == 'W') lon = -lon;
      final base = date ?? DateTime.utc(2000);
      fixes.add(Fix(
        time: base.add(Duration(days: dayOffset, seconds: seconds)),
        lat: lat,
        lon: lon,
        gpsAltM: gAlt!.toDouble(),
        // Loggers without a pressure sensor write 00000.
        baroAltM: pAlt == null || pAlt == 0 ? null : pAlt.toDouble(),
        valid: line[24] == 'A',
      ));
    }
  }
  return IgcFlight(fixes: fixes, pilot: pilot, glider: glider, date: date);
}

String? _headerValue(String line) {
  final i = line.indexOf(':');
  final v = (i >= 0 ? line.substring(i + 1) : line.substring(5)).trim();
  return v.isEmpty ? null : v;
}

/// Writes an (unsigned) IGC file. XContest accepts unsigned files from apps it has not validated
/// only as "unverified"; a G record needs a key registered with them.
String writeIgc(List<Fix> fixes, {String pilot = '', String glider = '', String appVersion = '0.2'}) {
  final out = StringBuffer(igcHeader(
    fixes.isEmpty ? DateTime.now().toUtc() : fixes.first.time,
    pilot: pilot,
    glider: glider,
    appVersion: appVersion,
    baro: fixes.any((f) => f.baroAltM != null),
  ));
  for (final f in fixes) {
    out.writeln(igcBRecord(f));
  }
  return out.toString();
}

/// The A and H records of an IGC file (each line ends with a newline).
String igcHeader(DateTime date,
    {String pilot = '', String glider = '', String appVersion = '0.2', bool baro = false}) {
  final d = date.toUtc();
  return 'AXAE001 aeric $appVersion\n'
      'HFDTEDATE:${_two(d.day)}${_two(d.month)}${_two(d.year % 100)},01\n'
      'HFPLTPILOTINCHARGE:$pilot\n'
      'HFGTYGLIDERTYPE:$glider\n'
      'HFDTMGPSDATUM:WGS-1984\n'
      'HFFTYFRTYPE:aeric,$appVersion\n'
      'HFGPSRECEIVER:phone\n'
      'HFPRSPRESSALTSENSOR:${baro ? 'phone barometer' : 'none'}\n';
}

/// One B record (fix) without the newline.
String igcBRecord(Fix f) {
  final t = f.time.toUtc();
  return 'B${_two(t.hour)}${_two(t.minute)}${_two(t.second)}'
      '${_coord(f.lat, true)}${_coord(f.lon, false)}${f.valid ? 'A' : 'V'}'
      '${f.baroAltM == null ? '00000' : _alt(f.baroAltM)}${_alt(f.gpsAltM)}';
}
