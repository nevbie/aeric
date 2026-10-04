import 'package:aeric/core/flight/thermal_conditions.dart';
import 'package:aeric/core/leonardo.dart';
import 'package:aeric/core/sample_sites.dart';
import 'package:aeric/core/weather_hour.dart';
import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final merkur = blackForestSites.firstWhere((s) => s.id == 'merkur-west');

/// Shaped like the output of Leonardo's EXT_flight.php?op=list_flights_json, including its
/// formatted values (HTML, &nbsp;) and one object broken by an unescaped quote.
const body = '''{ "flights":[  {"flightID": "101", "date": "2024-06-15", "firstLat": "48.7650", "firstLon": "8.2790", "lastLat": "48.9", "lastLon": "8.6", "DURATION": "3:12", "START_TIME": "12:05", "END_TIME": "15:17", "MAX_ALT": "1850&nbsp;m", "MAX_VARIO": "<span class=\\"vario_style\\">4.2&nbsp;m/s</span>", "linearDistance": "35.2&nbsp;km", "olcDistance": "48.7&nbsp;km", "olcScore": "60.1", "scoreSpeed": "", "olcScoreType": "FREE_FLIGHT", "gliderBrandImg": "", "gliderCat": "", "categoryImg": "", "pilotName": "A", "takeoff": "Merkur"  } ,  {"flightID": "102", "date": "2024-06-16", "firstLat": "48.7652", "firstLon": "8.2795", "DURATION": "1:30", "START_TIME": "13:40", "olcDistance": "20.0&nbsp;km", "takeoff": "Merkur"  } ,  {"flightID": "103", "date": "2023-08-02", "firstLat": "48.7660", "firstLon": "8.2800", "DURATION": "0:45", "START_TIME": "11:10", "olcDistance": "8.5&nbsp;km", "pilotName": "Broken "quote" name", "takeoff": "Merkur"  } ,  {"flightID": "104", "date": "2023-08-03", "firstLat": "48.9000", "firstLon": "8.5000", "DURATION": "2:00", "START_TIME": "12:00", "olcDistance": "30&nbsp;km", "takeoff": "Elsewhere"  }  ] }''';

List<WeatherHour> weather(DateTime day, {double dir = 270, double speed = 12, double cloud = 20}) => [
      for (var h = 0; h < 24; h++)
        WeatherHour(time: day.add(Duration(hours: h)), windSpeed10m: speed, windDir10m: dir, gusts10m: speed, cloudCover: cloud),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
  });

  test('parses formatted values and survives a broken object', () {
    final flights = parseLeonardoFlights(body);
    expect(flights.map((f) => f.id), ['101', '102', '104']); // 103 has broken JSON
    final f = flights.first;
    expect(f.date, DateTime(2024, 6, 15));
    expect(f.startMinutes, 12 * 60 + 5);
    expect(f.startLocal, DateTime(2024, 6, 15, 12, 5));
    expect(f.duration, const Duration(hours: 3, minutes: 12));
    expect(f.distanceKm, 48.7);
    expect(f.maxAltM, 1850);
    expect(f.maxClimbMs, 4.2);
  });

  test('URL and start-radius filter', () async {
    Uri? asked;
    final client = LeonardoClient((u) async {
      asked = u;
      return body;
    });
    final flights = await client.flightsNear(merkur, from: DateTime(2020), to: DateTime(2026, 10, 4));
    expect(asked.toString(), startsWith(LeonardoClient.defaultBaseUrl));
    expect(asked!.queryParameters['op'], 'list_flights_json');
    expect(asked!.queryParameters['distance'], '2.0');
    expect(asked!.queryParameters['tm1'], '${DateTime.utc(2020).millisecondsSinceEpoch ~/ 1000}');
    expect(flights.map((f) => f.id), ['101', '102']); // 104 started 20 km away
  });

  test('weather join and statistics', () {
    final flights = parseLeonardoFlights(body).take(2).toList();
    final hours = [
      ...weather(DateTime(2024, 6, 15)),
      ...weather(DateTime(2024, 6, 16), dir: 45, speed: 15, cloud: 60),
    ];
    final stats = SiteXcStats.build(merkur, attachWeather(flights, hours));
    expect(stats.withWeather, 2);
    expect(stats.byWind['W']!.flights, 1);
    expect(stats.byWind['NE']!.flights, 1);
    expect(stats.byWind['W']!.avgKm, 48.7);
    expect(stats.byCloud['0–25 %']!.flights, 1);
    expect(stats.byCloud['50–75 %']!.flights, 1);
    expect(stats.byHour[12]!.flights, 1);
    expect(stats.byMonth[6]!.flights, 2);
    expect(stats.windRanking.length, 2);
    final like = stats.like(const WeatherCondition(windFromDeg: 260, windKmh: 14, cloudCover: 30));
    expect(like.single.flight.id, '101');
  });

  testWidgets('XC history card renders on the Thermals tab', (tester) async {
    final app = AppState.instance;
    await app.loadFavourites();
    app.thermalSiteId = merkur.id;
    final hours = [...weather(DateTime(2024, 6, 15)), ...weather(DateTime(2024, 6, 16), dir: 45)];
    app.xcStats[merkur.id] = SiteXcStats.build(merkur, attachWeather(parseLeonardoFlights(body).take(2).toList(), hours));
    app.setTab(2);
    await tester.binding.setSurfaceSize(const Size(360, 3000));
    await tester.pumpWidget(const AericApp());
    await tester.pump();
    expect(find.text('XC history (Leonardo)'), findsOneWidget);
    expect(find.text('Wind at takeoff'), findsOneWidget);
    expect(find.textContaining('2 flights · 2 with weather'), findsOneWidget);
    app.setTab(0);
    await tester.pumpWidget(const SizedBox());
  });
}
