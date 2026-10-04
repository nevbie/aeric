import 'package:aeric/core/sample_sites.dart';
import 'package:aeric/core/thermal_climatology.dart';
import 'package:aeric/core/thermal_model.dart';
import 'package:aeric/core/weather_hour.dart';
import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sunny synthetic day for [site]: warming from 10 °C to 24 °C, light north wind.
List<WeatherHour> sunnyDay(DateTime date, {double tMax = 24}) {
  final site = AppState.instance.sites.first;
  const model = ThermalModel();
  return [
    for (var h = 0; h < 24; h++)
      () {
        final frac = h <= 6 ? 0.0 : h >= 15 ? 1.0 - (h - 15) / 12 : (h - 6) / 9;
        final t = 10 + (tMax - 10) * frac;
        final w = WeatherHour(
          time: date.add(Duration(hours: h)), windSpeed10m: 8, windDir10m: 300, gusts10m: 12,
          temperature2m: t, dewPoint2m: t - 15, cloudCover: 15, modelElevationM: 900,
          precipitationProbability: 0, cape: 100,
        );
        return w.copyWith(shortwaveRadiation: model.radiation(site, w));
      }(),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
  });

  testWidgets('Fly and Thermals screens render forecast, live estimate and climatology', (tester) async {
    final app = AppState.instance;
    await app.loadFavourites();
    final site = app.sites.first;
    final now = app.siteNow(site);
    final today = DateTime(now.year, now.month, now.day);
    app.forecasts[site.id] = [
      for (var d = 0; d < 3; d++) ...sunnyDay(today.add(Duration(days: d))),
    ];
    app.climatologies[site.id] = ThermalClimatology.build(site, [
      for (var y = 1; y <= 3; y++) ...sunnyDay(DateTime(today.year - y, today.month, today.day), tMax: 16 + 3.0 * y),
    ]);

    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(const AericApp());
    await tester.pump();

    expect(find.text(site.name), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.text('Map'));
    await tester.pump();
    expect(find.text('Hotspots'), findsOneWidget);

    await tester.tap(find.text('Thermals').last);
    await tester.pump();
    expect(find.textContaining('Now at ${site.name}'), findsOneWidget);
    expect(find.text('Today vs. history'), findsOneWidget);
    expect(find.text('Thermal climatology'), findsOneWidget);
    expect(find.textContaining('Usable thermals on'), findsOneWidget);

    // Dispose the screens so their periodic timers are cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('favourites can be toggled and are saved', (tester) async {
    final app = AppState.instance;
    await app.loadFavourites();
    final merkur = app.siteById('merkur-west');
    final tegelberg = app.siteById('tegelberg');
    expect(app.isFavourite(merkur), isTrue);
    expect(app.isFavourite(tegelberg), isFalse);
    expect(app.sitesByFavourite.first.id, 'loffenau-west');

    await app.toggleFavourite(merkur);
    await app.toggleFavourite(tegelberg);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('favourites')!;
    expect(saved, contains('tegelberg'));
    expect(saved, isNot(contains('merkur-west')));

    // A fresh start restores the saved set instead of the defaults.
    final fresh = AppState(get: (_) async => throw Exception('offline'));
    await fresh.loadFavourites();
    expect(fresh.isFavourite(merkur), isFalse);
    expect(fresh.isFavourite(tegelberg), isTrue);
  });

  testWidgets('map renders the takeoffs and the kk7 hotspot layer', (tester) async {
    final app = AppState.instance;
    await app.loadFavourites();
    final site = app.siteById('hornisgrinde');
    final now = app.siteNow(site);
    app.forecasts[site.id] = sunnyDay(DateTime(now.year, now.month, now.day));

    await tester.binding.setSurfaceSize(const Size(420, 900));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: MapScreen())));
    await tester.pump();
    expect(find.text('Hotspots'), findsOneWidget);
    expect(find.text('Skyways'), findsOneWidget);
    // The Black Forest takeoffs are in view (the Alpine ones are off-screen and culled).
    expect(find.byIcon(Icons.paragliding), findsNWidgets(blackForestSites.length));

    // The chip row scrolls sideways; the Hotspots chip is off-screen at phone width.
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Hotspots')).onSelected!(true);
    await tester.pump();
    expect(find.textContaining('thermal.kk7.ch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
