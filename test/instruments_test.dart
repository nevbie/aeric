import 'dart:math' as math;

import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/services/flight_controller.dart';
import 'package:aeric/services/settings.dart';
import 'package:aeric/ui/instruments.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flight_test.dart' show syntheticFlight;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
  });

  test('page layouts round-trip; unknown instruments are skipped; bad JSON gives defaults', () {
    final pages = [InstrumentPage('Mine', [Instrument.wind, Instrument.taskGoal])];
    final back = decodePages(encodePages(pages));
    expect(back.single.name, 'Mine');
    expect(back.single.tiles, [Instrument.wind, Instrument.taskGoal]);
    expect(decodePages('[{"name":"X","tiles":["wind","teleport"]}]').single.tiles, [Instrument.wind]);
    expect(decodePages('nonsense').length, defaultPages().length);
    expect(decodePages(null).first.tiles, contains(Instrument.neededLd));
  });

  test('every instrument has a value before and during a flight', () {
    final fc = FlightController.instance..reset();
    for (final i in Instrument.values) {
      final (v, unit, _) = instrumentValue(i, fc);
      expect(v, isNotEmpty, reason: i.name);
      expect(unit, isA<String>());
    }
    for (final f in syntheticFlight()) {
      fc.onPressure(f.time, 1013.25 * math.pow(1 - f.altM / 44330.77, 1 / 0.190263));
      fc.onPosition(f);
    }
    expect(instrumentValue(Instrument.flightTime, fc).$1, matches(r'^0:1[01]$')); // incl. a minute on the ground
    expect(instrumentValue(Instrument.maxAlt, fc).$1, isNot('–'));
    expect(instrumentValue(Instrument.wind, fc).$2, startsWith('km/h from'));
    expect(instrumentValue(Instrument.airspace, fc).$1, 'clear');
    fc.reset();
  });

  testWidgets('edit mode: add and remove a tile, saved across restarts', (tester) async {
    await Settings.instance.load();
    await Settings.instance.update((s) => s.pagesJson = null);
    FlightController.instance.reset();
    AppState.instance.setTab(3);
    await tester.binding.setSurfaceSize(const Size(320, 760));
    await tester.pumpWidget(const AericApp());
    await tester.pump();
    expect(find.text('Basic'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit pages'));
    await tester.pump();
    // Add "Flight time" to the first page.
    await tester.ensureVisible(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flight time'));
    await tester.pumpAndSettle();
    expect(decodePages(Settings.instance.pagesJson).first.tiles.last, Instrument.flightTime);

    // Replace the first tile (Altitude) with "Remove tile".
    await tester.ensureVisible(find.text('Altitude').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Altitude').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove tile'));
    await tester.pumpAndSettle();
    final saved = decodePages(Settings.instance.pagesJson).first.tiles;
    expect(saved.first, Instrument.agl);
    expect(saved.length, 9);

    await tester.tap(find.byTooltip('Done'));
    await tester.pump();
    AppState.instance.setTab(0);
    await tester.pumpWidget(const SizedBox());
  });
}
