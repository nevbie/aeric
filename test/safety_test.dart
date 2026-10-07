import 'dart:io';
import 'dart:math' as math;

import 'package:aeric/core/airspace.dart';
import 'package:aeric/core/flight/fix.dart';
import 'package:aeric/core/flight/igc.dart';
import 'package:aeric/core/flight/landing_detector.dart';
import 'package:aeric/services/crash_reporting.dart';
import 'package:aeric/services/flight_controller.dart';
import 'package:aeric/services/logbook.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flight_test.dart' show syntheticFlight;

double _hpa(double alt) => 1013.25 * math.pow(1 - alt / 44330.77, 1 / 0.190263);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'voice': false}));

  group('landing detection', () {
    final t0 = DateTime.utc(2026, 7, 1, 12);

    test('standing still on the ground counts as landed after 90 s', () {
      final d = LandingDetector();
      var landed = false;
      for (var i = 0; i <= 90 && !landed; i++) {
        landed = d.update(time: t0.add(Duration(seconds: i)), groundSpeedKmh: 0.5, varioMs: 0.05, altM: 400 + (i % 2) * 0.5, aglM: 2);
        if (i < 90) expect(landed, isFalse, reason: 'too early at $i s');
      }
      expect(landed, isTrue);
    });

    test('hovering into a strong wind never counts as landed', () {
      final d = LandingDetector();
      // 10 minutes at walking pace or slower, in ridge lift: altitude wanders by ±8 m.
      for (var i = 0; i < 600; i++) {
        final alt = 900 + 8 * math.sin(i / 20);
        final vario = 8 / 20 * math.cos(i / 20);
        expect(
          d.update(time: t0.add(Duration(seconds: i)), groundSpeedKmh: 1, varioMs: vario, altM: alt, aglM: null),
          isFalse,
          reason: 'landed at $i s',
        );
      }
    });

    test('perfectly level hovering high above the terrain never counts as landed', () {
      final d = LandingDetector();
      for (var i = 0; i < 600; i++) {
        expect(d.update(time: t0.add(Duration(seconds: i)), groundSpeedKmh: 0, varioMs: 0, altM: 900, aglM: 150), isFalse);
      }
    });

    test('a live flight that hovers keeps the instruments running', () {
      final fc = FlightController.instance..reset();
      addTearDown(() {
        fc.mode = FlightMode.idle;
        fc.reset();
      });
      fc.mode = FlightMode.live;
      // Take off: the first 400 s of the synthetic flight.
      final fixes = syntheticFlight().take(400).toList();
      for (final f in fixes) {
        fc.onPressure(f.time, _hpa(f.altM));
        fc.onPosition(f);
      }
      expect(fc.flying, isTrue);
      // Then hover over the ridge for 5 minutes: ground speed 0, small up and down.
      final last = fixes.last;
      for (var i = 1; i <= 300; i++) {
        final f = Fix(
          time: last.time.add(Duration(seconds: i)),
          lat: last.lat,
          lon: last.lon,
          gpsAltM: last.altM + 6 * math.sin(i / 15),
        );
        fc.onPressure(f.time, _hpa(f.gpsAltM));
        fc.onPosition(f, speedKmh: 0);
      }
      expect(fc.mode, FlightMode.live);
      expect(fc.flying, isTrue);
    });
  });

  group('logbook', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('aeric-safety'));
    tearDown(() => dir.delete(recursive: true));

    test('a damaged index is kept aside and rebuilt from the IGC files', () async {
      final book = Logbook(dir: () async => dir);
      final e = await book.addIgc(writeIgc(syntheticFlight()), source: 'recorded');
      expect(e, isNotNull);
      File('${dir.path}/index.json').writeAsStringSync('[{"id": "trunc');

      final again = Logbook(dir: () async => dir);
      await again.load();
      expect(again.entries.single.id, e!.id);
      expect(dir.listSync().any((f) => f.path.contains('index.corrupt-')), isTrue);
      // A new flight does not wipe the rebuilt list.
      await again.addIgc(writeIgc(syntheticFlight().map((f) => Fix(time: f.time.add(const Duration(hours: 2)), lat: f.lat, lon: f.lon, gpsAltM: f.gpsAltM, baroAltM: f.baroAltM)).toList()), source: 'imported');
      final third = Logbook(dir: () async => dir);
      await third.load();
      expect(third.entries, hasLength(2));
    });

    test('the same flight saved twice at once is stored once', () async {
      final book = Logbook(dir: () async => dir);
      final igc = writeIgc(syntheticFlight());
      await Future.wait([book.saveRecording(igc), book.saveRecording(igc)]);
      expect(book.entries, hasLength(1));
      expect(Directory('${dir.path}/unanalyzed').existsSync(), isFalse);
    });

    test('a recording left by a crash becomes a logbook entry on the next start', () async {
      final book = Logbook(dir: () async => dir);
      await book.startRecording(pilot: 'Eric');
      for (final f in syntheticFlight()) {
        book.appendFix(f);
      }
      // App killed: no finishRecording. Everything up to the last flush is on disk.
      final next = Logbook(dir: () async => dir);
      await next.load();
      expect(next.entries, hasLength(1));
      expect(next.entries.single.source, 'recorded');
      expect(File('${dir.path}/recording.igc').existsSync(), isFalse);
    });

    test('a recording without a detectable flight is kept, not thrown away', () async {
      final book = Logbook(dir: () async => dir);
      final ground = writeIgc(syntheticFlight().take(60).toList());
      expect(await book.saveRecording(ground), isNull);
      final kept = Directory('${dir.path}/unanalyzed').listSync();
      expect(kept, hasLength(1));
      expect(File(kept.single.path).readAsStringSync(), ground);
    });
  });

  group('airspace limits err on the safe side', () {
    test('an unreadable ceiling is unlimited, an unreadable floor is the ground', () {
      expect(AltitudeLimit.parse('see NOTAM', ceiling: true).ref, AltitudeRef.unlimited);
      expect(AltitudeLimit.parse('', ceiling: true).ref, AltitudeRef.unlimited);
      expect(AltitudeLimit.parse('see NOTAM').toMslM(groundM: 300), 300);
    });

    test('a ceiling above ground counts as unlimited while the terrain height is unknown', () {
      final a = parseOpenAir('AC D\nAN LOW\nAL GND\nAH 1000ft AGL\n'
              'DP 48:00:00 N 008:00:00 E\nDP 48:00:00 N 008:10:00 E\nDP 48:10:00 N 008:10:00 E\nDP 48:10:00 N 008:00:00 E\n')
          .single;
      const checker = AirspaceChecker();
      // 1500 m MSL: above 1000 ft over sea level, but the ground may be 1300 m high.
      expect(checker.check([a], lat: 48.05, lon: 8.05, altM: 1500).single.level, AirspaceLevel.inside);
      expect(checker.check([a], lat: 48.05, lon: 8.05, altM: 1500, groundM: 200), isEmpty);
    });
  });

  test('crash reports keep only the host of URLs', () {
    expect(
      scrubUrls('ClientException: Connection reset, uri=https://api.open-meteo.com/v1/forecast?latitude=48.76&longitude=8.27'),
      'ClientException: Connection reset, uri=https://api.open-meteo.com/…',
    );
    expect(scrubUrls('no url here'), 'no url here');
  });
}
