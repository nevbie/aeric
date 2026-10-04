import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/historical_weather.dart';
import '../core/open_meteo.dart';
import '../core/sample_sites.dart';
import '../core/site.dart';
import '../core/thermal_climatology.dart';
import '../core/weather_hour.dart';
import 'http.dart';

/// Holds forecasts and historical climatologies for all sites.
class AppState extends ChangeNotifier {
  AppState({HttpGet? get, Future<Directory> Function()? cacheDir})
      : _forecast = OpenMeteoClient(get ?? networkGet()),
        _history = HistoricalWeatherClient(
          diskCached(get ?? networkGet(), cacheDir ?? () async => Directory('${(await getApplicationCacheDirectory()).path}/archive')),
        );

  static final instance = AppState();

  /// Years of history and the ± day window around today that make up the climatology.
  static const historyYears = 5;
  static const historyHalfWindowDays = 15;

  final OpenMeteoClient _forecast;
  final HistoricalWeatherClient _history;

  final List<Site> sites = sampleSites;

  int tab = 0;
  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  // ------------------------------------------------------------------ forecasts
  final Map<String, List<WeatherHour>> forecasts = {};
  final Map<String, String> forecastErrors = {};
  bool loadingForecasts = false;
  DateTime? forecastsLoadedAt;

  Future<void> refreshForecasts() async {
    if (loadingForecasts) return;
    loadingForecasts = true;
    notifyListeners();
    await Future.wait(sites.map((s) async {
      try {
        // One past day so the thermal model sees the whole of today, incl. the morning minimum.
        forecasts[s.id] = await _forecast.forecast(s.lat, s.lon, days: 3, pastDays: 1);
        forecastErrors.remove(s.id);
      } catch (e) {
        forecastErrors[s.id] = '$e';
      }
    }));
    loadingForecasts = false;
    forecastsLoadedAt = DateTime.now();
    notifyListeners();
  }

  /// Current wall-clock time at the site (the user may be in another time zone).
  DateTime siteNow(Site site) {
    final hours = forecasts[site.id];
    final offset = hours == null || hours.isEmpty ? DateTime.now().timeZoneOffset.inSeconds : hours.first.utcOffsetSeconds;
    final t = DateTime.now().toUtc().add(Duration(seconds: offset));
    return DateTime(t.year, t.month, t.day, t.hour, t.minute);
  }

  // ------------------------------------------------------------------ climatology
  final Map<String, ThermalClimatology> climatologies = {};
  final Map<String, String> climatologyErrors = {};
  final Set<String> loadingClimatology = {};

  Future<void> loadClimatology(Site site, {bool force = false}) async {
    if (loadingClimatology.contains(site.id) || (!force && climatologies.containsKey(site.id))) return;
    loadingClimatology.add(site.id);
    climatologyErrors.remove(site.id);
    notifyListeners();
    try {
      final today = siteNow(site);
      final history = await _history.seasonalHistory(
        site.lat,
        site.lon,
        today,
        years: historyYears,
        halfWindowDays: historyHalfWindowDays,
        today: today,
      );
      climatologies[site.id] = await compute(_buildClimatology, (site, history));
    } catch (e) {
      climatologyErrors[site.id] = '$e';
    }
    loadingClimatology.remove(site.id);
    notifyListeners();
  }
}

ThermalClimatology _buildClimatology((Site, List<WeatherHour>) args) => ThermalClimatology.build(args.$1, args.$2);
