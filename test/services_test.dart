import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aeric/core/flight/igc.dart';
import 'package:aeric/services/flight_controller.dart';
import 'package:aeric/services/logbook.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flight_test.dart' show syntheticFlight;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('logbook imports IGC and ZIP, skips duplicates and files without a flight, survives a restart', () async {
    final dir = await Directory.systemTemp.createTemp('aeric-logbook');
    addTearDown(() => dir.delete(recursive: true));
    final book = Logbook(dir: () async => dir);

    final igc = writeIgc(syntheticFlight(), pilot: 'Eric');
    final other = writeIgc(syntheticFlight().map((f) => f).toList().sublist(0, 60)); // only ground: no flight
    final zip = ZipEncoder().encodeBytes(Archive()
      ..add(ArchiveFile.bytes('2026-07-01-merkur.igc', utf8.encode(igc)))
      ..add(ArchiveFile.bytes('readme.txt', utf8.encode('hi'))));

    await book.importFiles([
      ('ground.igc', Uint8List.fromList(utf8.encode(other))),
      ('flights.zip', Uint8List.fromList(zip)),
      ('again.igc', Uint8List.fromList(utf8.encode(igc))),
    ]);
    expect(book.entries, hasLength(1));
    expect(book.message, 'Imported 1 flight, skipped 2 (duplicate or no flight).');
    final e = book.entries.single;
    expect(e.siteName, 'Merkur West, Baden-Baden');
    expect(e.thermals, hasLength(1));
    expect(e.airtime.inSeconds, closeTo(620, 5));
    expect(await book.readIgc(e), igc);

    // Weather tagging needs the network (not available in tests): thermals stay "pending".
    expect(e.conditionsMissing, isTrue);

    final reopened = Logbook(dir: () async => dir);
    await reopened.load();
    expect(reopened.entries.single.id, e.id);
    expect(reopened.entries.single.thermals.single.spot.avgClimbMs, closeTo(e.thermals.single.spot.avgClimbMs, 1e-9));

    await reopened.delete(reopened.entries.single);
    expect(File('${dir.path}/${e.id}.igc').existsSync(), isFalse);
  });

  test('flight controller: barometer vario, thermal average, wind and final glide from a replayed flight', () {
    final fc = FlightController.instance..reset();
    for (final f in syntheticFlight(windFromDeg: 270, windKmh: 15)) {
      // Pressure from altitude, like the replay does.
      fc.onPressure(f.time, 1013.25 * math.pow(1 - f.altM / 44330.77, 1 / 0.190263));
      fc.onPosition(f);
      if (f.time.difference(syntheticFlight().first.time).inSeconds == 370) {
        // Late in the thermal.
        expect(fc.varioMs, closeTo(2.0, 0.3));
        expect(fc.thermalAvgMs, closeTo(2.0, 0.4));
        expect(fc.thermalGainM, greaterThan(250));
      }
    }
    expect(fc.hasBarometer, isTrue);
    expect(fc.flying, isTrue); // auto-landing only stops live flights
    expect(fc.wind, isNotNull);
    expect(fc.wind!.fromDeg, closeTo(270, 8));
    expect(fc.wind!.speedKmh, closeTo(15, 2));
    // Final glide target: the nearest landing field – Merkur West, 1–2 km from the synthetic thermal.
    expect(fc.landing, isNotNull);
    expect(fc.landing!.id, anyOf('merkur-west', 'merkur-grossmatte'));
    expect(fc.finalGlideToLanding!.distanceKm, lessThan(5));
    expect(fc.track.length, greaterThan(600));
  });
}
