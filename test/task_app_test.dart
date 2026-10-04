import 'dart:math' as math;

import 'package:aeric/core/flight/fix.dart';
import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/services/flight_controller.dart';
import 'package:aeric/services/task_store.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flight_test.dart' show syntheticFlight;
import 'task_test.dart' show xctsk;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
  });

  test('task store imports, rejects garbage and persists', () async {
    final store = TaskStore.instance;
    expect(await store.import('not a task'), isFalse);
    expect(store.error, startsWith('Not an XCTrack task'));
    expect(await store.import(xctsk), isTrue);
    expect(store.progress!.nextTurnpoint!.name, 'START');
    store.task = null;
    await store.load();
    expect(store.task!.turnpoints, hasLength(5));
    await store.clear();
    expect(store.task, isNull);
  });

  test('flight controller follows the task', () async {
    final store = TaskStore.instance;
    // A start cylinder of 300 m around the Merkur launch, no time gate; then a far turnpoint.
    await store.import('XCTSK:{"taskType":"CLASSIC","version":2,"t":['
        '{"z":"${_z(8.2794, 48.7647, 651, 300)}","n":"START","t":2},'
        '{"z":"${_z(8.4072, 48.7567, 890, 1000)}","n":"TEUFEL","t":3}],'
        '"s":{"g":[],"d":2,"t":2},"g":{"t":2},"e":0}');
    addTearDown(store.clear);
    final fc = FlightController.instance..reset();
    for (final f in syntheticFlight().take(260)) {
      fc.onPressure(f.time, 1013.25 * math.pow(1 - f.altM / 44330.77, 1 / 0.190263));
      fc.onPosition(Fix(time: f.time, lat: f.lat, lon: f.lon, gpsAltM: f.gpsAltM, baroAltM: f.baroAltM));
    }
    // Glided out of the 300 m start cylinder: started, now heading for TEUFEL.
    expect(store.progress!.nextTurnpoint!.name, 'TEUFEL');
    expect(fc.taskRoute, isNotNull);
    expect(fc.taskRoute!.totalM, greaterThan(5000));
  });

  testWidgets('task card and the button row fit a small phone', (tester) async {
    await TaskStore.instance.import(xctsk);
    addTearDown(TaskStore.instance.clear);
    FlightController.instance.reset();
    AppState.instance.setTab(3);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(const AericApp());
    await tester.pump();
    expect(find.textContaining('Next: START'), findsOneWidget);
    expect(find.byTooltip('Competition task'), findsOneWidget);
    AppState.instance.setTab(0);
    await tester.pumpWidget(const SizedBox());
  });
}

String _z(double lon, double lat, int alt, int radius) {
  // Same encoding as XCTrack QR codes.
  final sb = StringBuffer();
  for (final v in [(lon * 1e5).round(), (lat * 1e5).round(), alt, radius]) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      sb.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    sb.writeCharCode(x + 63);
  }
  return sb.toString();
}
