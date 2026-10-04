import 'package:aeric/core/flight/geo.dart';
import 'package:aeric/core/landing.dart';
import 'package:aeric/core/sample_sites.dart';
import 'package:aeric/core/site.dart';
import 'package:aeric/main.dart';
import 'package:aeric/services/app_state.dart';
import 'package:aeric/services/settings.dart';
import 'package:aeric/ui/map_screen.dart';
import 'package:aeric/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapScreen.tilesEnabled = false;
  });

  test('every favourite takeoff has a landing field below it, within glide', () {
    for (final s in blackForestSites) {
      final fields = landingFields.where((l) => l.siteIds.contains(s.id)).toList();
      expect(fields, isNotEmpty, reason: s.name);
      for (final l in fields) {
        final d = distanceM(s.lat, s.lon, l.lat, l.lon);
        final drop = s.takeoffElevationM - l.elevationM;
        expect(drop, greaterThan(200), reason: '${s.name} → ${l.name}');
        // Reachable at a glide ratio of 8 (school gliders reach 8–9) with 100 m margin.
        expect(d / (drop - 100), lessThan(8), reason: '${s.name} → ${l.name}: ${d.round()} m for $drop m');
      }
    }
    // Loffenau landing (DHV): N 48°46'21.76" E 8°23'53.18", 389 m.
    final loffenau = landingFields.firstWhere((l) => l.id == 'loffenau');
    expect(loffenau.lat, closeTo(48.77271, 1e-5));
    expect(loffenau.lon, closeTo(8.39811, 1e-5));
  });

  test('sites and landings round-trip through JSON', () {
    final s = Site(
      id: 'user-1', name: 'Mine', lat: 48.5, lon: 8.2, takeoffElevationM: 700,
      sectors: [WindSector.ofCompass('W')!, WindSector.ofCompass('NW')!],
    );
    final back = Site.fromJson(s.toJson());
    expect(back.userDefined, isTrue);
    expect(back.sectors, hasLength(2));
    expect(back.sectorDistance(270), 0);
    expect(back.sectorDistance(315), 0);
    expect(back.sectorDistance(90), greaterThan(90));
    const l = LandingField(id: 'user-2', name: 'Field', lat: 48.4, lon: 8.1, elevationM: 300);
    expect(LandingField.fromJson(l.toJson()).userDefined, isTrue);
  });

  test('settings persist', () async {
    final st = Settings.instance;
    await st.load();
    await st.update((s) {
      s.pilot = 'Eric';
      s.trimKmh = 40;
      s.qnhHpa = 1020.5;
    });
    final p = await SharedPreferences.getInstance();
    expect(p.getString('pilot'), 'Eric');
    expect(p.getDouble('qnh'), 1020.5);
    expect(st.polar.glideRatio, closeTo(40 / 3.6 / st.trimSinkMs, 1e-9));
    await st.update((s) => s.qnhHpa = null);
    expect(p.getDouble('qnh'), isNull);
  });

  test('own takeoffs and landings survive a restart and become favourites', () async {
    final app = AppState(get: (_) async => throw Exception('offline'));
    await app.loadFavourites();
    await app.addUserSite(Site(id: 'user-9', name: 'Hausberg', lat: 48.6, lon: 8.3, takeoffElevationM: 600, sectors: const [WindSector(200, 280)]));
    await app.addUserLanding(const LandingField(id: 'user-10', name: 'Wiese', lat: 48.61, lon: 8.29, elevationM: 250, userDefined: true));

    final restarted = AppState(get: (_) async => throw Exception('offline'));
    await restarted.loadFavourites();
    expect(restarted.siteById('user-9').name, 'Hausberg');
    expect(restarted.isFavourite(restarted.siteById('user-9')), isTrue);
    expect(restarted.landings.where((l) => l.userDefined).single.name, 'Wiese');
    expect(restarted.landings.length, landingFields.length + 1);

    await restarted.removeUserSite(restarted.siteById('user-9'));
    final again = AppState(get: (_) async => throw Exception('offline'));
    await again.loadFavourites();
    expect(again.sites.any((s) => s.id == 'user-9'), isFalse);
  });

  testWidgets('settings screen and logbook header fit a small phone', (tester) async {
    await Settings.instance.load();
    await tester.binding.setSurfaceSize(const Size(340, 1600));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    expect(find.text('Pilot name'), findsOneWidget);
    expect(find.textContaining('Glide ratio at trim'), findsOneWidget);

    AppState.instance.setTab(4);
    await tester.pumpWidget(const AericApp());
    await tester.pump();
    expect(find.text('Import IGC'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    AppState.instance.setTab(0);
    await tester.pumpWidget(const SizedBox());
  });
}
