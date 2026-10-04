import 'dart:math' as math;

import 'package:aeric/core/flight/geo.dart';
import 'package:aeric/core/flight/thermal_assistant.dart';
import 'package:aeric/ui/thermal_assistant_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Circles of 60 m radius around (lat0, lon0) offset from a thermal core that lies
/// [coreBearing]/[coreDist] from the circle centre; climb falls off with distance to the core.
/// The air (and the core) drifts with the wind.
List<LiftSample> circling({
  required double coreBearing,
  required double coreDist,
  double windFrom = 0,
  double windKmh = 0,
  int seconds = 60,
}) {
  const lat0 = 48.6, lon0 = 8.2;
  final t0 = DateTime.utc(2026, 7, 1, 12);
  final (cLat, cLon) = destination(lat0, lon0, coreBearing, coreDist);
  final out = <LiftSample>[];
  for (var i = 0; i < seconds; i++) {
    final drift = windKmh / 3.6 * i;
    final windTo = (windFrom + 180) % 360;
    // Pilot circle centre and core both drift with the wind.
    final (pcLat, pcLon) = destination(lat0, lon0, windTo, drift);
    final (coreLat, coreLon) = destination(cLat, cLon, windTo, drift);
    final (pLat, pLon) = destination(pcLat, pcLon, i * 18.0, 60); // 20 s per circle
    final d = distanceM(pLat, pLon, coreLat, coreLon);
    out.add(LiftSample(t0.add(Duration(seconds: i)), pLat, pLon, 3.0 * math.exp(-d * d / (2 * 70 * 70))));
  }
  return out;
}

void main() {
  test('needs a circle of data, uniform lift gives no advice', () {
    final a = ThermalAssistant();
    final t0 = DateTime.utc(2026);
    for (var i = 0; i < 5; i++) {
      a.add(LiftSample(t0.add(Duration(seconds: i)), 48, 8, 1));
    }
    expect(a.evaluate(now: t0.add(const Duration(seconds: 5)), lat: 48, lon: 8), isNull);
    for (var i = 5; i < 30; i++) {
      a.add(LiftSample(t0.add(Duration(seconds: i)), 48 + i * 1e-5, 8, 1));
    }
    expect(a.evaluate(now: t0.add(const Duration(seconds: 30)), lat: 48, lon: 8), isNull);
  });

  for (final (windFrom, windKmh) in [(0.0, 0.0), (270.0, 20.0)]) {
    test('points towards the core (wind $windKmh km/h from $windFrom°)', () {
      for (final coreBearing in [0.0, 90.0, 225.0]) {
        final samples = circling(coreBearing: coreBearing, coreDist: 50, windFrom: windFrom, windKmh: windKmh);
        final a = ThermalAssistant();
        samples.forEach(a.add);
        final last = samples.last;
        final r = a.evaluate(now: last.time, lat: last.lat, lon: last.lon, windFromDeg: windFrom, windKmh: windKmh)!;
        // The core relative to the circle centre, as seen from the pilot's last position.
        final windTo = (windFrom + 180) % 360;
        final drift = windKmh / 3.6 * 59;
        final (cLat, cLon) = destination(48.6, 8.2, coreBearing, 50);
        final (coreLat, coreLon) = destination(cLat, cLon, windTo, drift);
        final expected = bearingDeg(last.lat, last.lon, coreLat, coreLon);
        expect(angleBetween(r.coreBearingDeg, expected), lessThan(25), reason: 'core at $coreBearing°');
        expect(r.coreClimbMs, greaterThan(r.averageClimbMs));
      }
    });
  }

  test('relative bearing to the track', () {
    const r = ThermalAssist(points: [], coreEastM: 50, coreNorthM: 0, coreClimbMs: 3, averageClimbMs: 1);
    expect(r.coreBearingDeg, closeTo(90, 1e-9));
    expect(r.relativeToTrack(0), closeTo(90, 1e-9)); // core to the right
    expect(r.relativeToTrack(180), closeTo(-90, 1e-9)); // core to the left
    expect(r.coreDistanceM, closeTo(50, 1e-9));
  });

  testWidgets('assistant view renders on a small phone', (tester) async {
    final samples = circling(coreBearing: 90, coreDist: 50);
    final a = ThermalAssistant();
    samples.forEach(a.add);
    final r = a.evaluate(now: samples.last.time, lat: samples.last.lat, lon: samples.last.lon)!;
    await tester.binding.setSurfaceSize(const Size(320, 400));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ThermalAssistantView(r, trackDeg: 0))));
    expect(find.textContaining('Core'), findsOneWidget);
  });
}

double angleBetween(double a, double b) {
  final d = ((a - b) % 360 + 360) % 360;
  return d > 180 ? 360 - d : d;
}