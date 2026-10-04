import 'dart:math' as math;

import 'package:aeric/core/flight/fix.dart';
import 'package:aeric/core/flight/flight_analysis.dart';
import 'package:aeric/core/flight/geo.dart';
import 'package:aeric/core/flight/glide.dart';
import 'package:aeric/core/flight/igc.dart';
import 'package:aeric/core/flight/thermal_conditions.dart';
import 'package:aeric/core/flight/vario.dart';
import 'package:aeric/core/flight/vario_tone.dart';
import 'package:aeric/core/flight/wind.dart';
import 'package:aeric/core/solar.dart';
import 'package:aeric/core/weather_hour.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 7, 1, 11);

/// Synthetic 1 Hz flight from Merkur: 60 s on launch, straight glide, a thermal circled in a
/// westerly wind, glide out, 60 s on the ground.
List<Fix> syntheticFlight({double windFromDeg = 270, double windKmh = 15, double airKmh = 36}) {
  final fixes = <Fix>[];
  var lat = 48.7647, lon = 8.2794, alt = 650.0;
  var t = t0;
  var heading = 260.0;
  final windTo = (windFromDeg + 180) * math.pi / 180;
  final wx = windKmh / 3.6 * math.sin(windTo), wy = windKmh / 3.6 * math.cos(windTo);

  void step({double turnDegPerS = 0, double vz = -1.1, bool moving = true}) {
    if (moving) {
      heading = (heading + turnDegPerS) % 360;
      final h = heading * math.pi / 180;
      final vx = airKmh / 3.6 * math.sin(h) + wx, vy = airKmh / 3.6 * math.cos(h) + wy;
      final d = math.sqrt(vx * vx + vy * vy);
      final (la, lo) = destination(lat, lon, math.atan2(vx, vy) * 180 / math.pi, d);
      lat = la;
      lon = lo;
      alt += vz;
    }
    t = t.add(const Duration(seconds: 1));
    fixes.add(Fix(time: t, lat: lat, lon: lon, gpsAltM: alt + 3, baroAltM: alt));
  }

  for (var i = 0; i < 60; i++) {
    step(moving: false);
  }
  for (var i = 0; i < 120; i++) {
    step();
  }
  for (var i = 0; i < 200; i++) {
    step(turnDegPerS: 18, vz: 2.0); // 20 s per turn, 2 m/s climb
  }
  for (var i = 0; i < 300; i++) {
    step();
  }
  for (var i = 0; i < 60; i++) {
    step(moving: false);
  }
  return fixes;
}

void main() {
  group('IGC', () {
    test('write and parse round trip', () {
      final fixes = syntheticFlight();
      final text = writeIgc(fixes, pilot: 'Eric', glider: 'Advance Iota');
      expect(text, startsWith('AXAE001 aeric'));
      expect(text, contains('HFDTEDATE:010726,01'));
      final igc = parseIgc(text);
      expect(igc.pilot, 'Eric');
      expect(igc.glider, 'Advance Iota');
      expect(igc.date, DateTime.utc(2026, 7, 1));
      expect(igc.fixes, hasLength(fixes.length));
      for (final i in [0, 300, fixes.length - 1]) {
        expect(igc.fixes[i].time, fixes[i].time);
        expect(igc.fixes[i].lat, closeTo(fixes[i].lat, 1e-5));
        expect(igc.fixes[i].lon, closeTo(fixes[i].lon, 1e-5));
        expect(igc.fixes[i].baroAltM, closeTo(fixes[i].baroAltM!, 0.5));
      }
    });

    test('parses real-world B records: south/west, no baro, midnight rollover, old date header', () {
      const text = 'AXCTxyz\r\nHFDTE311225\r\nHFPLTPILOT:Jane Doe\r\n'
          'B2359583343123S07012345WA0000001234\r\n'
          'B0000023343125S07012340WA0000001240\r\n'
          'B0000033343125S07012340WV0000001240\r\n';
      final igc = parseIgc(text);
      expect(igc.pilot, 'Jane Doe');
      expect(igc.fixes, hasLength(3));
      final a = igc.fixes[0], b = igc.fixes[1];
      expect(a.time, DateTime.utc(2025, 12, 31, 23, 59, 58));
      expect(b.time, DateTime.utc(2026, 1, 1, 0, 0, 2));
      expect(a.lat, closeTo(-(33 + 43.123 / 60), 1e-9));
      expect(a.lon, closeTo(-(70 + 12.345 / 60), 1e-9));
      expect(a.baroAltM, isNull);
      expect(a.altM, 1234);
      expect(igc.fixes[2].valid, isFalse);
    });
  });

  group('Flight analysis', () {
    const analyzer = FlightAnalyzer();

    test('finds takeoff, landing, stats and the thermal', () {
      final stats = analyzer.analyze(syntheticFlight())!;
      expect(stats.takeoff.time.difference(t0).inSeconds, closeTo(61, 2));
      expect(stats.airtime.inSeconds, closeTo(620, 5));
      expect(stats.maxAltM, closeTo(650 - 132 + 400, 5));
      expect(stats.maxClimbMs, closeTo(2.0, 0.1));
      expect(stats.maxSinkMs, closeTo(-1.1, 0.1));
      expect(stats.trackKm, closeTo(4.6, 0.3)); // into a 15 km/h headwind
      expect(stats.thermals, hasLength(1));
      final th = stats.thermals.single;
      expect(th.avgClimbMs, closeTo(2.0, 0.15));
      expect(th.gainM, greaterThan(350));
      expect(th.duration.inSeconds, closeTo(200, 25));
      // Thermal position is near the launch (drifting east with the wind).
      expect(distanceM(48.7647, 8.2794, th.lat, th.lon), lessThan(3000));
      final back = ThermalSpot.fromJson(th.toJson());
      expect(back.start, th.start);
      expect(back.topAltM, th.topAltM);
    });

    test('a track that never flies has no flight', () {
      final ground = [
        for (var i = 0; i < 100; i++) Fix(time: t0.add(Duration(seconds: i)), lat: 48.0, lon: 8.0, gpsAltM: 500),
      ];
      expect(analyzer.analyze(ground), isNull);
    });

    test('circling without climbing is not a thermal', () {
      final fixes = syntheticFlight();
      final sinking = [
        for (final f in fixes) Fix(time: f.time, lat: f.lat, lon: f.lon, gpsAltM: 800, baroAltM: 800 - f.time.difference(t0).inSeconds * 0.5),
      ];
      expect(analyzer.thermals(sinking), isEmpty);
    });
  });

  group('Vario', () {
    test('pressure ↔ altitude', () {
      expect(pressureToAltitudeM(1013.25), closeTo(0, 0.01));
      expect(pressureToAltitudeM(898.76), closeTo(1000, 2));
      final qnh = qnhFor(940, 650);
      expect(pressureToAltitudeM(940, qnhHpa: qnh), closeTo(650, 0.01));
    });

    test('Kalman filter finds a 2 m/s climb in noisy 1 Hz barometer data', () {
      final kf = KalmanVario();
      final rnd = math.Random(1);
      double v = 0;
      for (var i = 0; i <= 40; i++) {
        final noise = (rnd.nextDouble() - 0.5) * 1.0; // ±0.5 m
        v = kf.update(t0.add(Duration(seconds: i)), 1000 + 2.0 * i + noise);
      }
      expect(v, closeTo(2.0, 0.3));
      expect(kf.altitudeM, closeTo(1080, 1.5));
    });

    test('Kalman filter stays calm when level', () {
      final kf = KalmanVario();
      final rnd = math.Random(2);
      var maxAbs = 0.0;
      for (var i = 0; i <= 200; i++) {
        final v = kf.update(t0.add(Duration(milliseconds: 100 * i)), 1000 + (rnd.nextDouble() - 0.5) * 1.0);
        if (i > 50) maxAbs = math.max(maxAbs, v.abs());
      }
      expect(maxAbs, lessThan(0.35));
    });

    test('30 s average', () {
      final avg = TimeAverage(const Duration(seconds: 30));
      for (var i = 0; i < 60; i++) {
        avg.add(t0.add(Duration(seconds: i)), i < 30 ? 0 : 2);
      }
      expect(avg.value, closeTo(2, 0.1));
    });
  });

  group('Tones', () {
    const mapper = VarioToneMapper();

    test('beeps get higher and faster with lift, silent in normal sink, low tone in strong sink', () {
      final weak = mapper.toneFor(0.5), strong = mapper.toneFor(3);
      expect(weak.isSilent, isFalse);
      expect(strong.frequencyHz, greaterThan(weak.frequencyHz));
      expect(strong.periodS, lessThan(weak.periodS));
      expect(mapper.toneFor(-1).isSilent, isTrue);
      final sink = mapper.toneFor(-4);
      expect(sink.duty, 1);
      expect(sink.frequencyHz, lessThan(400));
    });

    test('synth produces beeps of the right length without clicks between chunks', () {
      final synth = ToneSynth(sampleRate: 8000);
      final tone = mapper.toneFor(2);
      final a = synth.render(tone, 4000), b = synth.render(tone, 4000);
      final all = [...a, ...b];
      final sounding = all.where((s) => s != 0).length / all.length;
      expect(sounding, closeTo(tone.duty, 0.08));
      // Continuity at the chunk boundary: no jump bigger than one sine step at full volume.
      final maxStep = 32767 * 2 * math.pi * tone.frequencyHz / 8000 * 1.1;
      expect((b.first - a.last).abs(), lessThan(maxStep));
      expect(synth.render(Tone.silent, 100).every((s) => s == 0), isTrue);
    });
  });

  group('Wind from circling', () {
    test('recovers wind direction and speed from drift', () {
      for (final (dir, speed) in [(270.0, 15.0), (45.0, 22.0), (180.0, 8.0)]) {
        final fixes = syntheticFlight(windFromDeg: dir, windKmh: speed).sublist(180, 380); // the thermal
        final w = windFromCircling(fixes)!;
        expect(w.speedKmh, closeTo(speed, 1.5), reason: 'speed for $dir°');
        expect(w.fromDeg, closeTo(dir, 6), reason: 'direction for $dir°');
        expect(w.airspeedKmh, closeTo(36, 1.5));
        expect(w.quality, greaterThan(0.9));
      }
    });

    test('needs a full turn', () {
      expect(windFromCircling(syntheticFlight().sublist(60, 180)), isNull); // straight glide
    });
  });

  group('Glide', () {
    test('current glide ratio from the straight part', () {
      final glide = syntheticFlight(windKmh: 0).sublist(62, 180);
      expect(currentGlideRatio(glide), closeTo(36 / 3.6 / 1.1, 0.3));
      expect(currentGlideRatio(syntheticFlight().sublist(200, 380)), isNull); // climbing
    });

    test('final glide with head- and tailwind', () {
      // Hornisgrinde launch to the Seebach landing (≈2.5 km, 660 m lower).
      FinalGlide fg(double windFrom) => finalGlide(
            lat: 48.5969, lon: 8.1962, altM: 1123,
            goalLat: 48.5901, goalLon: 8.1633, goalElevationM: 463,
            windFromDeg: windFrom, windKmh: 20,
          );
      final calm = finalGlide(lat: 48.5969, lon: 8.1962, altM: 1123, goalLat: 48.5901, goalLon: 8.1633, goalElevationM: 463);
      expect(calm.distanceKm, closeTo(2.55, 0.1));
      expect(calm.bearingDeg, closeTo(253, 3));
      expect(calm.requiredGlideRatio, closeTo(2550 / (660 - 150), 0.2));
      expect(calm.reachable, isTrue);
      final head = fg(250), tail = fg(70);
      expect(head.groundSpeedKmh, lessThan(calm.groundSpeedKmh));
      expect(tail.groundSpeedKmh, greaterThan(calm.groundSpeedKmh));
      expect(head.arrivalHeightM, lessThan(calm.arrivalHeightM));
      expect(tail.arrivalHeightM, greaterThan(calm.arrivalHeightM));
      final tooLow = finalGlide(lat: 48.5969, lon: 8.1962, altM: 600, goalLat: 48.5901, goalLon: 8.1633, goalElevationM: 463);
      expect(tooLow.requiredGlideRatio, isNull);
      expect(tooLow.reachable, isFalse);
    });
  });

  group('Thermals by condition', () {
    ThermalSpot spot(double lat, double lon, {double climb = 2}) => ThermalSpot(
          lat: lat, lon: lon, start: t0, end: t0.add(const Duration(seconds: 100)),
          baseAltM: 800, topAltM: 800 + climb * 100,
        );
    const west = WeatherCondition(windFromDeg: 270, windKmh: 15, cloudCover: 30);
    const east = WeatherCondition(windFromDeg: 80, windKmh: 15, cloudCover: 30);
    const calm = WeatherCondition(windFromDeg: 0, windKmh: 3, cloudCover: 20);

    test('matcher compares wind direction, strength and cloud', () {
      const m = ConditionMatcher();
      expect(m.matches(west, const WeatherCondition(windFromDeg: 300, windKmh: 12, cloudCover: 50)), isTrue);
      expect(m.matches(west, east), isFalse);
      expect(m.matches(west, const WeatherCondition(windFromDeg: 270, windKmh: 35)), isFalse);
      expect(m.matches(west, const WeatherCondition(windFromDeg: 270, windKmh: 15, cloudCover: 90)), isFalse);
      expect(m.matches(calm, const WeatherCondition(windFromDeg: 180, windKmh: 5)), isTrue);
      expect(m.matches(calm, west), isFalse);
    });

    test('hotspots cluster thermals and rank the ones flown in today\'s conditions', () {
      final thermals = [
        // Spot A (Merkur ridge): 3 thermals, all in westerly wind.
        ConditionedThermal(spot(48.7650, 8.2800), west),
        ConditionedThermal(spot(48.7655, 8.2805), west),
        ConditionedThermal(spot(48.7648, 8.2810, climb: 1), west),
        // Spot B (5 km east): 4 thermals, all in easterly wind.
        for (var i = 0; i < 4; i++) ConditionedThermal(spot(48.7650 + i * 0.0005, 8.3500), east),
      ];
      final all = conditionalHotspots(thermals);
      expect(all, hasLength(2));
      expect(all.first.count, 4); // no reference: biggest first

      final today = conditionalHotspots(thermals, reference: const WeatherCondition(windFromDeg: 280, windKmh: 12, cloudCover: 40));
      expect(today.first.count, 3);
      expect(today.first.matching, hasLength(3));
      expect(today.first.prevailingWindFromDeg, closeTo(270, 0.5));
      expect(today.last.matching, isEmpty);
      expect(today.first.avgClimbMs, closeTo(5 / 3, 0.01));
    });

    test('weather at a UTC instant uses the site offset', () {
      final hours = [
        for (var h = 0; h < 24; h++)
          WeatherHour(time: DateTime(2026, 7, 1, h), windSpeed10m: h.toDouble(), windDir10m: 0, gusts10m: 0, utcOffsetSeconds: 7200),
      ];
      // 11:20 UTC = 13:20 local → 13:00.
      expect(weatherAt(hours, DateTime.utc(2026, 7, 1, 11, 20))!.windSpeed10m, 13);
      expect(weatherAt(hours, DateTime.utc(2026, 7, 3, 12)), isNull);
    });

    test('kk7 layer follows season and time of day', () {
      // Sunrise at Merkur: ≈5:20 CEST in July, ≈8:15 CET in December.
      final july = sunriseHourLocal(48.76, 8.28, DateTime(2026, 7, 1), 7200)!;
      final december = sunriseHourLocal(48.76, 8.28, DateTime(2026, 12, 20), 3600)!;
      expect(july, closeTo(5.33, 0.15));
      expect(december, closeTo(8.25, 0.15));
      expect(kk7Layer('thermals', DateTime(2026, 7, 1, 10), sunriseHour: july), 'thermals_jul_04');
      expect(kk7Layer('thermals', DateTime(2026, 7, 1, 13, 30), sunriseHour: july), 'thermals_jul_07');
      expect(kk7Layer('thermals', DateTime(2026, 7, 1, 16), sunriseHour: july), 'thermals_jul_10');
      expect(kk7Layer('thermals', DateTime(2026, 10, 4, 10)), 'thermals_oct_04');
      expect(kk7Layer('skyways', DateTime(2026, 11, 20, 17)), 'skyways_oct_10');
      expect(kk7Layer('thermals', DateTime(2026, 12, 20, 12), sunriseHour: december), 'thermals_jan_04');
      expect(kk7Layer('thermals', DateTime(2026, 5, 31, 15)), 'thermals_apr_07');
    });
  });
}
