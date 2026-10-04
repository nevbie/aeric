import 'dart:convert';

import 'package:aeric/core/day_planner.dart';
import 'package:aeric/core/flyability.dart';
import 'package:aeric/core/historical_weather.dart';
import 'package:aeric/core/live_thermal.dart';
import 'package:aeric/core/open_meteo.dart';
import 'package:aeric/core/sample_sites.dart';
import 'package:aeric/core/site.dart';
import 'package:aeric/core/solar.dart';
import 'package:aeric/core/thermal_climatology.dart';
import 'package:aeric/core/thermal_grid.dart';
import 'package:aeric/core/thermal_model.dart';
import 'package:aeric/core/weather_hour.dart';
import 'package:flutter_test/flutter_test.dart';

const site = Site(
  id: 't', name: 'Test', lat: 47.0, lon: 11.0,
  takeoffElevationM: 800, sectors: [WindSector(315, 45)],
);
final day = DateTime(2026, 7, 1);

WeatherHour hour(
  int h, {
  double speed = 10,
  double dir = 0,
  double? gust,
  double rain = 0,
  double cape = 200,
  DateTime? date,
}) =>
    WeatherHour(
      time: (date ?? day).add(Duration(hours: h)),
      windSpeed10m: speed, windDir10m: dir, gusts10m: gust ?? speed + 5,
      windSpeed700: 15, windDir700: 0, temperature2m: 22, dewPoint2m: 10,
      precipitationProbability: rain, cape: cape, modelElevationM: 600,
    );

/// A synthetic day: temperature rising from [tMin] at 6:00 to [tMax] at 15:00, with
/// radiation following the sun scaled by cloud cover.
List<WeatherHour> syntheticDay(
  DateTime date, {
  double tMin = 10,
  double tMax = 24,
  double spread = 12,
  double cloud = 10,
  double wind = 8,
  double windDir = 0,
}) {
  const model = ThermalModel();
  return [
    for (var h = 0; h < 24; h++)
      () {
        final frac = h <= 6 ? 0.0 : h >= 15 ? 1.0 - (h - 15) / 12 : (h - 6) / 9;
        final t = tMin + (tMax - tMin) * frac;
        final base = WeatherHour(
          time: date.add(Duration(hours: h)),
          windSpeed10m: wind, windDir10m: windDir, gusts10m: wind + 4,
          temperature2m: t, dewPoint2m: t - spread, cloudCover: cloud, modelElevationM: 700,
          utcOffsetSeconds: 7200,
        );
        return base.copyWith(shortwaveRadiation: model.radiation(site, base));
      }(),
  ];
}

void main() {
  group('Flyability', () {
    const assessor = FlyabilityAssessor();

    test('north wind on a north site is GO', () {
      final a = assessor.assess(site, hour(12));
      expect(a.verdict, Verdict.go);
      expect(a.score, 100);
    });

    test('sector wraps through north', () {
      expect(const WindSector(315, 45).contains(350), isTrue);
      expect(const WindSector(315, 45).contains(10), isTrue);
      expect(const WindSector(315, 45).contains(180), isFalse);
    });

    test('tailwind is NO-GO, sector edge marginal, calm ignores direction', () {
      final tail = assessor.assess(site, hour(12, dir: 180));
      expect(tail.verdict, Verdict.noGo);
      expect(tail.reasons.any((r) => r.contains('outside launch sector')), isTrue);
      expect(assessor.assess(site, hour(12, dir: 55)).verdict, Verdict.marginal);
      expect(assessor.assess(site, hour(12, speed: 3, dir: 180)).verdict, Verdict.go);
    });

    test('strong, gusty, rainy and stormy hours are NO-GO', () {
      expect(assessor.assess(site, hour(12, speed: 30)).verdict, Verdict.noGo);
      expect(assessor.assess(site, hour(12, gust: 30)).verdict, Verdict.noGo);
      expect(assessor.assess(site, hour(12, rain: 80)).verdict, Verdict.noGo);
      expect(assessor.assess(site, hour(12, cape: 2000)).verdict, Verdict.noGo);
    });

    test('high takeoff uses pressure-level wind', () {
      const alpine = Site(id: 'a', name: 'A', lat: 47, lon: 11, takeoffElevationM: 1700, sectors: [WindSector(315, 45)]);
      final a = assessor.assess(alpine, hour(12, speed: 5).copyWith(windSpeed850: 35, windDir850: 0));
      expect(a.takeoffWindKmh, 35);
      expect(a.verdict, Verdict.noGo);
    });
  });

  group('DayPlanner', () {
    const planner = DayPlanner();

    test('best window skips NO-GO hours', () {
      final forecast = [
        for (var h = 9; h <= 19; h++)
          h <= 10
              ? hour(h, dir: 180)
              : h <= 15
                  ? hour(h)
                  : h == 16
                      ? hour(h, dir: 55)
                      : hour(h, rain: 90),
      ];
      final w = planner.planDay(site, forecast, day).bestWindow!;
      expect(w.start, day.add(const Duration(hours: 11)));
      expect(w.end, day.add(const Duration(hours: 17)));
      expect(w.hours, 6);
      expect(w.worstVerdict, Verdict.marginal);
    });

    test('no window when everything is NO-GO; ranking prefers GO', () {
      expect(planner.planDay(site, [for (var h = 9; h <= 19; h++) hour(h, rain: 90)], day).bestWindow, isNull);
      final good = planner.planDay(site, [for (var h = 9; h <= 19; h++) hour(h)], day);
      const other = Site(id: 'b', name: 'B', lat: 47, lon: 11, takeoffElevationM: 800, sectors: [WindSector(315, 45)]);
      final bad = planner.planDay(other, [for (var h = 9; h <= 19; h++) hour(h, rain: 90)], day);
      expect(planner.rankSites([bad, good]).map((p) => p.site.id), ['t', 'b']);
    });
  });

  group('Open-Meteo', () {
    test('parses forecast response incl. radiation and UTC offset', () {
      const body = '''{"latitude":47.0,"longitude":11.0,"elevation":1050.0,"utc_offset_seconds":7200,
        "hourly":{"time":["2026-07-01T10:00","2026-07-01T11:00"],
          "temperature_2m":[20.0,21.0],"dew_point_2m":[10.0,null],
          "precipitation_probability":[0,10],"cloud_cover":[20,30],"cape":[100.0,300.0],
          "shortwave_radiation":[650.0,700.0],
          "wind_speed_10m":[8.0,null],"wind_direction_10m":[350,355],"wind_gusts_10m":[15.0,18.0],
          "wind_speed_850hPa":[12.0,14.0],"wind_direction_850hPa":[340,345],
          "wind_speed_700hPa":[20.0,22.0],"wind_direction_700hPa":[300,310]}}''';
      final hours = parseOpenMeteo(body);
      expect(hours, hasLength(1)); // second hour has no surface wind
      final h = hours.single;
      expect(h.time, DateTime(2026, 7, 1, 10));
      expect(h.modelElevationM, 1050);
      expect(h.utcOffsetSeconds, 7200);
      expect(h.cloudBaseMslM, 1050 + 1250);
      expect(h.shortwaveRadiation, 650);
      expect(h.windSpeed700, 20);
    });

    test('forecast URL asks for past days', () {
      final url = OpenMeteoClient((_) async => '').buildUrl(47.5, 11.25, pastDays: 1).toString();
      expect(url, contains('past_days=1'));
      expect(url, contains('shortwave_radiation'));
    });

    test('historical windows cover the same season and skip the not-yet-archived part', () {
      final client = HistoricalWeatherClient((_) async => '');
      final today = DateTime(2026, 10, 4);
      final windows = client.seasonalWindows(today, years: 3, halfWindowDays: 10, today: today);
      expect(windows.map((w) => w.toString()), ['2023-09-24..2023-10-14', '2024-09-24..2024-10-14', '2025-09-24..2025-10-14']);
      // Looking at a date just behind today: this year's window gets clipped by the archive delay.
      final url = client.buildUrl(47, 11, windows.first.start, windows.first.end).toString();
      expect(url, contains('start_date=2023-09-24&end_date=2023-10-14'));
      expect(url, contains('wind_direction_10m'));
      expect(url, contains('cloud_cover'));
    });
  });

  group('Sun', () {
    test('noon in summer is high, midnight is below the horizon', () {
      // Solar noon at 11° E ≈ 11:20 UTC.
      expect(sunElevationDeg(47, 11, DateTime.utc(2026, 6, 21, 11, 20)), closeTo(66.4, 1));
      expect(sunElevationDeg(47, 11, DateTime.utc(2026, 12, 21, 11, 20)), closeTo(19.5, 1));
      expect(sunElevationDeg(47, 11, DateTime.utc(2026, 6, 21, 23)), lessThan(0));
    });

    test('clouds reduce radiation', () {
      final clear = clearSkyRadiation(60);
      expect(clear, closeTo(890, 30));
      expect(cloudyRadiation(clear, 100), closeTo(clear * 0.25, 1));
      expect(cloudyRadiation(clear, 0), clear);
    });
  });

  group('ThermalModel', () {
    const model = ThermalModel();

    test('sunny summer afternoon gives moderate thermals, night none', () {
      final est = model.estimateDay(site, syntheticDay(day));
      final at = {for (final e in est) e.time.hour: e};
      expect(at[3]!.climbMs, 0);
      expect(at[3]!.strength, ThermalStrength.none);
      expect(at[14]!.climbMs, inInclusiveRange(1.0, 3.5));
      expect(at[14]!.thermalTopMslM, greaterThan(1500));
      expect(at[14]!.usable, isTrue);
      // Thermals build through the morning.
      expect(at[10]!.climbMs, lessThan(at[13]!.climbMs));
    });

    test('a warmer day (stronger heating) gives deeper, stronger thermals', () {
      double at14(double tMax) =>
          model.estimateDay(site, syntheticDay(day, tMax: tMax, spread: 20)).firstWhere((e) => e.time.hour == 14).climbMs;
      expect(at14(18), lessThan(at14(24)));
      expect(at14(24), lessThan(at14(30)));
    });

    test('overcast, strong wind and moist air all weaken or cap thermals', () {
      double peak(List<WeatherHour> d) => model.estimateDay(site, d).map((e) => e.climbMs).reduce((a, b) => a > b ? a : b);
      final sunny = peak(syntheticDay(day));
      expect(peak(syntheticDay(day, cloud: 100, tMax: 14)), lessThan(sunny * 0.5));
      expect(peak(syntheticDay(day, wind: 35)), lessThan(sunny));
      final moist = model.estimateDay(site, syntheticDay(day, spread: 4));
      final e = moist.firstWhere((e) => e.time.hour == 14);
      expect(e.cumulus, isTrue);
      expect(e.thermalTopMslM, closeTo(700 + 4 * 125, 1));
    });

    test('cloud cover is used when radiation is missing', () {
      final noon = WeatherHour(
        time: DateTime(2026, 7, 1, 13), windSpeed10m: 5, windDir10m: 0, gusts10m: 8,
        cloudCover: 0, utcOffsetSeconds: 7200,
      );
      final clear = model.radiation(site, noon);
      expect(clear, greaterThan(750));
      expect(model.radiation(site, noon.copyWith(cloudCover: 100)), closeTo(clear * 0.25, 1));
    });

    test('lee side is flagged', () {
      final est = model.estimateDay(site, syntheticDay(day, wind: 15, windDir: 180));
      expect(est.firstWhere((e) => e.time.hour == 13).notes.any((n) => n.contains('lee')), isTrue);
    });
  });

  group('Climatology and live inference', () {
    // Five "historical" days: two overcast, three sunny with varying heat.
    final history = [
      ...syntheticDay(DateTime(2025, 6, 29), cloud: 100, tMax: 13),
      ...syntheticDay(DateTime(2025, 6, 30), cloud: 100, tMax: 12, windDir: 270),
      ...syntheticDay(DateTime(2025, 7, 1), tMax: 18, cloud: 40, spread: 16),
      ...syntheticDay(DateTime(2025, 7, 2), tMax: 22, cloud: 20, spread: 16),
      ...syntheticDay(DateTime(2025, 7, 3), tMax: 25, cloud: 10, spread: 16),
    ];
    final clim = ThermalClimatology.build(site, history);

    test('statistics per hour of day', () {
      expect(clim.days, 5);
      final noon = clim.at(13)!;
      expect(noon.samples, 5);
      expect(noon.usableFraction, closeTo(0.6, 1e-9));
      expect(noon.meanCloudCover, closeTo((100 + 100 + 40 + 20 + 10) / 5, 1e-9));
      expect(noon.prevailingWindDir, anyOf(closeTo(0, 25), closeTo(360, 25)));
      expect(clim.usableDayFraction, closeTo(0.6, 1e-9));
      expect(clim.typicalWindow, isNotNull);
      expect(percentileOf(5, [1, 2, 3, 4]), 100);
      expect(percentileOf(0, [1, 2, 3, 4]), 0);
      expect(quantile([1, 2, 3, 4, 5], 0.5), 3);
    });

    test('a hot, sunny day ranks high and is compared with the norm', () {
      final today = syntheticDay(DateTime(2026, 7, 1), tMax: 28, cloud: 0, spread: 20);
      final now = DateTime(2026, 7, 1, 13, 25);
      final r = LiveThermalReport.infer(site: site, hours: today, now: now, climatology: clim);
      expect(r.weatherNow!.time.hour, 13);
      expect(r.current!.usable, isTrue);
      expect(r.percentileNow, greaterThanOrEqualTo(90));
      expect(r.peakPercentile, greaterThanOrEqualTo(90));
      expect(r.comparisons.any((c) => c.startsWith('Temperature') && c.contains('+')), isTrue);
      expect(r.comparisons.any((c) => c.startsWith('Cloud cover 0 %')), isTrue);
      expect(r.trends.any((t) => t.contains('peak')), isTrue);
      expect(r.window, isNotNull);
      final morning = LiveThermalReport.infer(site: site, hours: today, now: DateTime(2026, 7, 1, 9, 10), climatology: clim);
      expect(morning.trends.any((t) => t.contains('Strengthening')), isTrue);
      expect(r.headline, contains('thermals now'));
    });

    test('an overcast morning reports no thermals and fast cloud build-up', () {
      final today = [
        for (final h in syntheticDay(DateTime(2026, 7, 1), tMax: 15))
          h.copyWith(cloudCover: h.time.hour < 9 ? 20 : 95, shortwaveRadiation: h.time.hour < 9 ? null : 60),
      ];
      final r = LiveThermalReport.infer(site: site, hours: today, now: DateTime(2026, 7, 1, 10, 5), climatology: clim);
      expect(r.current!.usable, isFalse);
      expect(r.trends.any((t) => t.contains('Clouds building')), isTrue);
      expect(r.percentileNow, lessThan(50));
    });

    test('works without climatology', () {
      final r = LiveThermalReport.infer(site: site, hours: syntheticDay(day), now: day.add(const Duration(hours: 12)));
      expect(r.comparisons, isEmpty);
      expect(r.current, isNotNull);
    });
  });

  group('Black Forest sites', () {
    test('Loffenau, Merkur, Hornisgrinde and Oppenau are the default favourites', () {
      final names = blackForestSites.map((s) => s.name).join(' | ');
      for (final place in ['Loffenau', 'Merkur', 'Hornisgrinde', 'Oppenau']) {
        expect(names, contains(place));
      }
      expect(defaultFavouriteIds, hasLength(blackForestSites.length));
      expect(sampleSites.map((s) => s.id).toSet(), hasLength(sampleSites.length)); // unique ids
    });

    test('launch sectors match the DHV directions', () {
      Site site(String id) => blackForestSites.firstWhere((s) => s.id == id);
      expect(site('merkur-west').sectorDistance(260), 0);
      expect(site('merkur-no').sectorDistance(30), 0);
      expect(site('merkur-no').sectorDistance(260), greaterThan(90));
      expect(site('hornisgrinde').sectorDistance(250), 0);
      expect(site('loffenau-nw').sectorDistance(304), 0);
      // Oppenau's four launches cover NE through W; NW–N has no launch.
      final oppenau = blackForestSites.where((s) => s.id.startsWith('oppenau'));
      double best(double dir) => oppenau.map((s) => s.sectorDistance(dir)).reduce((a, b) => a < b ? a : b);
      for (var dir = 30.0; dir <= 285; dir += 15) {
        expect(best(dir), 0, reason: 'wind $dir°');
      }
      expect(best(340), greaterThan(0));
      // Hornisgrinde allows only 10 km/h (DHV).
      const assessor = FlyabilityAssessor();
      final h = hour(12, speed: 14, dir: 250);
      expect(assessor.assess(site('hornisgrinde'), h).verdict, Verdict.noGo);
    });
  });

  group('Thermal grid', () {
    test('grid points cover the area evenly', () {
      final pts = ThermalGrid.gridPoints(48.6, 8.28, n: 4, spanKm: 40);
      expect(pts, hasLength(16));
      final lats = pts.map((p) => p.$1);
      expect(lats.reduce((a, b) => a < b ? a : b), closeTo(48.6 - 40 / 111 * 0.75, 1e-9));
      final url = ThermalGrid.buildUrl(pts).toString();
      expect(url, contains('latitude=${pts.first.$1.toStringAsFixed(4)},'));
      expect(url, contains('shortwave_radiation'));
      expect(url, contains('wind_speed_10m'));
    });

    test('parses a multi-location response and estimates thermals per cell', () {
      Map<String, dynamic> location(double elevation, double cloud) {
        final day = syntheticDay(DateTime(2026, 7, 1), cloud: cloud, spread: 16);
        String iso(DateTime t) => t.toIso8601String().substring(0, 16);
        return {
          'elevation': elevation,
          'utc_offset_seconds': 7200,
          'hourly': {
            'time': [for (final h in day) iso(h.time)],
            'temperature_2m': [for (final h in day) h.temperature2m],
            'dew_point_2m': [for (final h in day) h.dewPoint2m],
            'cloud_cover': [for (final h in day) h.cloudCover],
            'shortwave_radiation': [for (final h in day) h.shortwaveRadiation],
            'wind_speed_10m': [for (final h in day) h.windSpeed10m],
            'wind_direction_10m': [for (final h in day) h.windDir10m],
          },
        };
      }

      final pts = ThermalGrid.gridPoints(48.6, 8.28, n: 1, spanKm: 40) + [(48.7, 8.3)];
      final body = jsonEncode([location(700, 0), location(300, 100)]);
      final grid = ThermalGrid.parse(body, pts, centerLat: 48.6, centerLon: 8.28, n: 2, spanKm: 40);
      expect(grid.cells, hasLength(2));
      final sunny = grid.cells[0], overcast = grid.cells[1];
      expect(sunny.elevationM, 700);
      expect(sunny.corners, hasLength(4));
      final noon = DateTime(2026, 7, 1, 13, 40);
      expect(sunny.at(noon)!.time, DateTime(2026, 7, 1, 13));
      expect(sunny.bestOf(noon)!.climbMs, greaterThan(overcast.bestOf(noon)!.climbMs));
      expect(sunny.bestOf(noon)!.usable, isTrue);
      expect(sunny.bestOf(DateTime(2026, 7, 2)), isNull);
    });
  });
}
