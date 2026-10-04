import 'package:aeric/core/devices/vario_protocols.dart';
import 'package:flutter_test/flutter_test.dart';

String withChecksum(String body) {
  var cs = 0;
  for (final c in body.codeUnits) {
    cs ^= c;
  }
  return '\$$body*${cs.toRadixString(16).toUpperCase().padLeft(2, '0')}';
}

void main() {
  test('checksum', () {
    expect(nmeaChecksumOk(withChecksum('LK8EX1,101325,99999,150,23,1085,')), isTrue);
    expect(nmeaChecksumOk(r'$LK8EX1,101325,99999,150,23,1085,*00'), isFalse);
    expect(parseVarioLine(r'$LK8EX1,101325,99999,150,23,1085,*00'), isNull);
  });

  test('LK8EX1 (BlueFly, Skytraxx, many others)', () {
    final s = parseVarioLine(withChecksum('LK8EX1,95123,99999,-85,21,1077,'))!;
    expect(s.pressureHpa, closeTo(951.23, 1e-9));
    expect(s.baroAltM, isNull);
    expect(s.varioMs, closeTo(-0.85, 1e-9));
    expect(s.temperatureC, 21);
    expect(s.batteryPct, 77);
    final altOnly = parseVarioLine(withChecksum('LK8EX1,999999,1234,9999,99,3.9,'))!;
    expect(altOnly.pressureHpa, isNull);
    expect(altOnly.baroAltM, 1234);
    expect(altOnly.varioMs, isNull);
    expect(altOnly.batteryV, 3.9);
  });

  test('LXWP0', () {
    final s = parseVarioLine(withChecksum('LXWP0,Y,,1234.5,1.85,,,,,,,,'))!;
    expect(s.baroAltM, 1234.5);
    expect(s.varioMs, 1.85);
  });

  test('XC Tracer (fields of the documented example; its printed checksum *67 is wrong, real XOR is 79)', () {
    expect(parseVarioLine(r'$XCTRC,2015,1,5,16,34,33,36,46.947508,7.453117,540.32,12.35,270.4,2.78,,,,964.93,98*67'), isNull);
    final s = parseVarioLine(r'$XCTRC,2015,1,5,16,34,33,36,46.947508,7.453117,540.32,12.35,270.4,2.78,,,,964.93,98*79')!;
    expect(s.source, 'XCTRC');
    expect(s.lat, 46.947508);
    expect(s.lon, 7.453117);
    expect(s.gpsAltM, 540.32);
    expect(s.courseDeg, 270.4);
    expect(s.varioMs, 2.78);
    expect(s.pressureHpa, 964.93);
    expect(s.batteryPct, 98);
  });

  test('OpenVario POV, BlueFly PRS, GPS RMC/GGA', () {
    final pov = parseVarioLine(withChecksum('POV,P,1018.35,E,1.23,T,23.4'))!;
    expect(pov.pressureHpa, 1018.35);
    expect(pov.varioMs, 1.23);
    expect(pov.temperatureC, 23.4);
    expect(parseVarioLine('PRS 17CBA')!.pressureHpa, closeTo(0x17CBA / 100, 1e-9));
    final rmc = parseVarioLine(withChecksum('GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W'))!;
    expect(rmc.lat, closeTo(48.1173, 1e-4));
    expect(rmc.lon, closeTo(11.5167, 1e-4));
    expect(rmc.groundSpeedKmh, closeTo(41.48, 0.01));
    expect(rmc.courseDeg, 84.4);
    expect(parseVarioLine(withChecksum('GPRMC,123519,V,,,,,,,230394,,')), isNull);
    final gga = parseVarioLine(withChecksum('GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,'))!;
    expect(gga.gpsAltM, 545.4);
    expect(parseVarioLine('hello'), isNull);
  });

  test('line assembler joins BLE chunks', () {
    final a = LineAssembler();
    expect(a.add('\$LK8EX1,9512'.codeUnits), isEmpty);
    expect(a.add('3,99999,-85,21,1077,*'.codeUnits), isEmpty);
    final lines = a.add('3A\r\nPRS 17CBA\nPR'.codeUnits);
    expect(lines, [r'$LK8EX1,95123,99999,-85,21,1077,*3A', 'PRS 17CBA']);
    expect(a.add('S 17CBB\n'.codeUnits), ['PRS 17CBB']);
  });
}
