import 'dart:convert';

import 'package:aeric/core/flight/geo.dart';
import 'package:aeric/core/task/task.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small Black Forest task: launch Merkur, start exit 2 km, TP Hornisgrinde 1 km,
/// ESS Loffenau 1 km, goal Loffenau landing 400 m.
const xctsk = '''{
  "version": 1, "taskType": "CLASSIC", "earthModel": "WGS84",
  "turnpoints": [
    {"type": "TAKEOFF", "radius": 400, "waypoint": {"name": "MERKUR", "lat": 48.7647, "lon": 8.2794, "altSmoothed": 651}},
    {"type": "SSS", "radius": 2000, "waypoint": {"name": "START", "lat": 48.7647, "lon": 8.2794, "altSmoothed": 651}},
    {"radius": 1000, "waypoint": {"name": "HORNIS", "description": "Hornisgrinde", "lat": 48.6075, "lon": 8.2010, "altSmoothed": 1164}},
    {"type": "ESS", "radius": 1000, "waypoint": {"name": "TEUFEL", "lat": 48.7567, "lon": 8.4072, "altSmoothed": 890}},
    {"radius": 400, "waypoint": {"name": "GOAL", "lat": 48.7727, "lon": 8.3981, "altSmoothed": 389}}
  ],
  "takeoff": {"timeOpen": "10:00:00Z"},
  "sss": {"type": "RACE", "direction": "EXIT", "timeGates": ["11:00:00Z", "11:15:00Z"]},
  "goal": {"type": "CYLINDER", "deadline": "16:00:00Z"}
}''';

void main() {
  test('polyline ints match go-xctrack (lon 2, lat 1, alt 3, radius 1 = "_seK_ibEEA")', () {
    expect(encodePolylineInts([200000, 100000, 3, 1]), '_seK_ibEEA');
    expect(decodePolylineInts('_seK_ibEEA'), [200000, 100000, 3, 1]);
    expect(decodePolylineInts(encodePolylineInts([-814612, 4743210, -12, 25000])), [-814612, 4743210, -12, 25000]);
  });

  test('QR code (v2) from the go-xctrack test suite', () {
    final t = parseTask('XCTSK:{"taskType":"CLASSIC","version":2,"t":[{"z":"_seK_ibEEA","n":"D01"}],'
        '"to":"04:05:06Z","tc":"07:08:09Z","s":{"g":["01:02:03Z"],"d":1,"t":1},"g":{"t":1},"e":0}');
    final tp = t.turnpoints.single;
    expect(tp.name, 'D01');
    expect(tp.lat, 1);
    expect(tp.lon, 2);
    expect(tp.altM, 3);
    expect(tp.radiusM, 1);
    expect(t.sssDirection, SssDirection.enter);
    expect(t.raceStart, isTrue);
    expect(t.timeGates.single, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(t.goalType, GoalType.line);
    expect(t.takeoffOpen, const Duration(hours: 4, minutes: 5, seconds: 6));
  });

  test('compressed QR (XCTSKZ) and v1 file round trip', () {
    final v1 = parseTask(xctsk);
    expect(v1.turnpoints.map((t) => t.type), [
      TurnpointType.takeoff, TurnpointType.sss, TurnpointType.none, TurnpointType.ess, TurnpointType.none,
    ]);
    expect(v1.timeGates, hasLength(2));
    expect(v1.deadline, const Duration(hours: 16));
    expect(v1.sssDirection, SssDirection.exit);
    final again = parseTask(jsonEncode(v1.toJson()));
    expect(again.turnpoints[2].name, 'HORNIS');
    expect(again.turnpoints[2].radiusM, 1000);
    expect(again.timeGates, v1.timeGates);

    final v2 = '{"taskType":"CLASSIC","version":2,"t":[{"z":"${encodePolylineInts([827940, 4876470, 651, 2000])}","n":"START","t":2}],"s":{"g":["11:00:00Z"],"d":2,"t":1},"g":{"t":2},"e":0}';
    final z = 'XCTSKZ:${base64.encode(const ZLibEncoder().encode(utf8.encode(v2)))}';
    final t = parseTask(z);
    expect(t.turnpoints.single.type, TurnpointType.sss);
    expect(t.turnpoints.single.lat, closeTo(48.7647, 1e-9));
    expect(t.sssDirection, SssDirection.exit);
  });

  test('optimised route touches each cylinder and is shorter than centre to centre', () {
    final task = parseTask(xctsk);
    final tps = task.turnpoints.sublist(2); // after the start
    final start = task.turnpoints[1];
    final route = optimiseRoute(start.lat, start.lon, tps);
    var centre = 0.0;
    var prev = (start.lat, start.lon);
    for (final t in tps) {
      centre += distanceM(prev.$1, prev.$2, t.lat, t.lon);
      prev = (t.lat, t.lon);
    }
    expect(route.points, hasLength(tps.length));
    for (var i = 0; i < tps.length; i++) {
      final d = distanceM(route.points[i].$1, route.points[i].$2, tps[i].lat, tps[i].lon);
      expect(d, lessThanOrEqualTo(tps[i].radiusM + 15), reason: tps[i].name);
    }
    // Each cylinder saves about up to twice its radius.
    expect(route.totalM, lessThan(centre - 1500));
    expect(route.totalM, greaterThan(centre - 2 * (1000 + 1000 + 400) - 50));
    expect(route.legsM, hasLength(3));
  });

  test('a cylinder on the straight line costs nothing extra', () {
    final mid = Turnpoint(name: 'MID', lat: 48.5, lon: 8.5, radiusM: 2000);
    final end = Turnpoint(name: 'END', lat: 48.5, lon: 8.7, radiusM: 0);
    final r = optimiseRoute(48.5, 8.3, [mid, end]);
    expect(r.totalM, closeTo(distanceM(48.5, 8.3, 48.5, 8.7), 5));
  });

  test('progress: no start before the gate, exit start, turnpoint, ESS, goal', () {
    final task = parseTask(xctsk);
    final p = TaskProgress(task);
    final day = DateTime.utc(2026, 7, 1);
    expect(p.nextTurnpoint!.name, 'START');
    // Inside the start cylinder before the gate, then leaving it at 10:55 – too early.
    expect(p.update(day.add(const Duration(hours: 10, minutes: 50)), 48.7647, 8.2794), isNull);
    final out = destination(48.7647, 8.2794, 200, 2500);
    expect(p.update(day.add(const Duration(hours: 10, minutes: 55)), out.$1, out.$2), isNull);
    expect(p.stage, TaskStage.beforeStart);
    expect(p.nextGate(day.add(const Duration(hours: 10, minutes: 55))), const Duration(minutes: 5));
    // Back in and out again after the 11:00 gate → started with gate time.
    p.update(day.add(const Duration(hours: 11, minutes: 2)), 48.7647, 8.2794);
    expect(p.update(day.add(const Duration(hours: 11, minutes: 4)), out.$1, out.$2)!.name, 'START');
    expect(p.stage, TaskStage.racing);
    expect(p.startTime, day.add(const Duration(hours: 11)));
    expect(p.nextTurnpoint!.name, 'HORNIS');
    // Remaining route from here is about the optimised task distance.
    expect(p.remainingRoute(out.$1, out.$2).totalM, greaterThan(20000));
    // Tag Hornisgrinde, Teufelsmühle (ESS) and goal.
    expect(p.update(day.add(const Duration(hours: 12)), 48.6075, 8.2050)!.name, 'HORNIS');
    expect(p.update(day.add(const Duration(hours: 13)), 48.7567, 8.4072)!.name, 'TEUFEL');
    expect(p.stage, TaskStage.essReached);
    expect(p.speedSectionTime, const Duration(hours: 2));
    expect(p.update(day.add(const Duration(hours: 13, minutes: 10)), 48.7727, 8.3981)!.name, 'GOAL');
    expect(p.stage, TaskStage.goal);
    expect(p.nextTurnpoint, isNull);
  });
}
