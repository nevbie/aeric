import 'package:aeric/core/airspace.dart';
import 'package:aeric/core/flight/geo.dart';
import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/services/flight_controller.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sample = '''
* Test file (structure like DFS/DAeC OpenAIR exports)
AC CTR
AN CTR KARLSRUHE TEST
AL GND
AH 2500ft MSL
DP 48:50:00 N 008:00:00 E
DP 48:50:00 N 008:10:00 E
DP 48:40:00 N 008:10:00 E
DP 48:40:00 N 008:00:00 E

AC R
AN ED-R TEST
AL FL65
AH FL 100
V X=48:30:00 N 008:30:00 E
DC 2

AC D
AN TMA ARC TEST
AL 1500ft AGL
AH FL95
V X=48:00:00N 008:00:00E
V D=+
DA 5,0,90
DP 48:00:00N 008:00:00E

AC E
AN CLASS E (ignored by default)
AL 2500 ft
AH FL100
DP 48:50:00 N 008:00:00 E
DP 48:50:00 N 008:10:00 E
DP 48:40:00 N 008:10:00 E

AC Q
AN DB ARC
AL 1000m
AH 3000m
V X=47:00:00 N 008:00:00 E
V D=-
DB 47:10:00 N 008:00:00 E, 47:00:00 N 008:14:41 E
DP 47:00:00 N 008:00:00 E
''';

void main() {
  final spaces = parseOpenAir(sample);

  test('parses classes, names, limits and outlines', () {
    expect(spaces.map((a) => a.cls), ['CTR', 'R', 'D', 'E', 'Q']);
    final ctr = spaces[0];
    expect(ctr.name, 'CTR KARLSRUHE TEST');
    expect(ctr.floor.ref, AltitudeRef.agl);
    expect(ctr.ceiling.toMslM(), closeTo(762, 1));
    expect(ctr.polygon, hasLength(4));
    expect(ctr.polygon.first.$1, closeTo(48 + 50 / 60, 1e-9));
    expect(spaces[1].floor.ref, AltitudeRef.fl);
    expect(spaces[1].ceiling.value, 100);
    expect(spaces[4].floor.toMslM(), 1000);
  });

  test('altitude limits', () {
    expect(AltitudeLimit.parse('GND').toMslM(groundM: 300), 300);
    expect(AltitudeLimit.parse('1500ft AGL').toMslM(groundM: 300), closeTo(300 + 457.2, 0.1));
    expect(AltitudeLimit.parse('1500 GND').ref, AltitudeRef.agl);
    expect(AltitudeLimit.parse('4500 ALT').toMslM(), closeTo(1371.6, 0.1));
    expect(AltitudeLimit.parse('FL 65').toMslM(), closeTo(1981.2, 0.1));
    expect(AltitudeLimit.parse('FL65').toMslM(qnhHpa: 1023.25), closeTo(1981.2 + 83, 0.1));
    expect(AltitudeLimit.parse('UNL').toMslM(), double.infinity);
    expect(AltitudeLimit.parse('1000m AMSL').toMslM(), 1000);
  });

  test('coordinates in several notations', () {
    final a = parseOpenAirPoint('48:45:30 N 008:15:42 E')!;
    expect(a.$1, closeTo(48.758333, 1e-6));
    expect(a.$2, closeTo(8.261667, 1e-6));
    final b = parseOpenAirPoint('48:45.5N 8:15.7E')!;
    expect(b.$1, closeTo(48.758333, 1e-6));
    expect(b.$2, closeTo(8.261667, 1e-6));
    final c = parseOpenAirPoint('33:43:07 S 070:12:20 W')!;
    expect(c.$1, lessThan(0));
    expect(c.$2, lessThan(0));
  });

  test('circle and arcs become correct polygons', () {
    final circle = spaces[1];
    for (final (la, lo) in circle.polygon) {
      expect(distanceM(48.5, 8.5, la, lo), closeTo(2 * 1852, 5));
    }
    expect(circle.containsPoint(48.5, 8.5), isTrue);
    expect(circle.containsPoint(48.56, 8.5), isFalse); // 6.7 km north

    // Clockwise quarter from north to east, 5 NM, closed at the centre: a pie slice NE of it.
    final pie = spaces[2];
    final ne = destination(48, 8, 45, 5000);
    final sw = destination(48, 8, 225, 5000);
    expect(pie.containsPoint(ne.$1, ne.$2), isTrue);
    expect(pie.containsPoint(sw.$1, sw.$2), isFalse);

    // Counter-clockwise DB from north to east = the long way round (three quarters).
    final db = spaces[4];
    final w = destination(47, 8, 270, 10000);
    final neq = destination(47, 8, 45, 10000);
    expect(db.containsPoint(w.$1, w.$2), isTrue);
    expect(db.containsPoint(neq.$1, neq.$2), isFalse);
  });

  test('distance to the outline', () {
    final ctr = spaces[0];
    expect(ctr.distanceM(48.75, 8.05), 0);
    // 0.01° east of the eastern edge (8:10 E) at 48.75 N ≈ 734 m.
    expect(ctr.distanceM(48.75, 8 + 10 / 60 + 0.01), closeTo(734, 10));
  });

  group('checker', () {
    const checker = AirspaceChecker();

    test('inside the CTR below its ceiling', () {
      final w = checker.check(spaces, lat: 48.75, lon: 8.05, altM: 600, groundM: 120);
      expect(w.first.level, AirspaceLevel.inside);
      expect(w.first.airspace.cls, 'CTR');
      expect(w.first.text, startsWith('INSIDE CTR'));
      // Class E is ignored by default.
      expect(w.any((x) => x.airspace.cls == 'E'), isFalse);
    });

    test('above the CTR ceiling: nothing; just below the margin: info', () {
      expect(checker.check(spaces, lat: 48.75, lon: 8.05, altM: 1000), isEmpty);
      final w = checker.check(spaces, lat: 48.75, lon: 8.05, altM: 850);
      expect(w.single.level, AirspaceLevel.info);
      expect(w.single.verticalM, closeTo(88, 1));
    });

    test('approaching: predicted entry and horizontal warning', () {
      // 1.5 km east of the CTR, flying west at 40 km/h → inside within 60 s? 667 m – no.
      final east = destination(48.75, 8 + 10 / 60, 90, 1500);
      final none = checker.check(spaces, lat: east.$1, lon: east.$2, altM: 600, trackDeg: 270, groundSpeedKmh: 40);
      expect(none, isEmpty);
      // 600 m east, flying west at 50 km/h → 833 m in 60 s: predicted inside.
      final near = destination(48.75, 8 + 10 / 60, 90, 600);
      final w = checker.check(spaces, lat: near.$1, lon: near.$2, altM: 600, trackDeg: 270, groundSpeedKmh: 50);
      expect(w.first.predicted, isTrue);
      expect(w.first.text, contains('ahead'));
      // Same place flying away: horizontal warning only.
      final away = checker.check(spaces, lat: near.$1, lon: near.$2, altM: 600, trackDeg: 90, groundSpeedKmh: 50);
      expect(away.first.level, AirspaceLevel.warning);
      expect(away.first.horizontalM, closeTo(600, 15));
    });

    test('restricted area by flight level', () {
      // FL65–FL100 above 48.5/8.5: at 1500 m nothing, at 2100 m inside.
      expect(checker.check(spaces, lat: 48.5, lon: 8.5, altM: 1500), isEmpty);
      expect(checker.check(spaces, lat: 48.5, lon: 8.5, altM: 2100).first.level, AirspaceLevel.inside);
    });
  });

  testWidgets('airspace banner fits on a small phone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
    final fc = FlightController.instance..reset();
    fc.airspaceWarnings = const AirspaceChecker().check(spaces, lat: 48.75, lon: 8.05, altM: 600, groundM: 120);
    AppState.instance.setTab(3);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(const AericApp());
    await tester.pump();
    expect(find.textContaining('INSIDE CTR'), findsOneWidget);
    AppState.instance.setTab(0);
    fc.reset();
    await tester.pumpWidget(const SizedBox());
  });
}
