import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/elevation.dart';
import '../core/historical_weather.dart';
import '../core/landing.dart';
import '../core/leonardo.dart';
import '../core/open_meteo.dart';
import '../core/sample_sites.dart';
import '../core/site.dart';
import '../core/thermal_climatology.dart';
import '../core/thermal_grid.dart';
import '../core/weather_hour.dart';
import 'http.dart';

/// Holds forecasts and historical climatologies for all sites.
class AppState extends ChangeNotifier {
  AppState({HttpGet? get, Future<Directory> Function()? cacheDir}) : this._(get ?? networkGet(), cacheDir);

  AppState._(this._get, Future<Directory> Function()? cacheDir)
      : _forecast = OpenMeteoClient(_get),
        elevation = ElevationClient(_get),
        _history = HistoricalWeatherClient(
          diskCached(_get, cacheDir ?? () async => Directory('${(await getApplicationCacheDirectory()).path}/archive')),
        );

  late final LeonardoClient _leonardo = LeonardoClient(diskCached(
    _get,
    () async => Directory('${(await getApplicationCacheDirectory()).path}/leonardo'),
    maxAge: const Duration(days: 7),
  ));

  // ------------------------------------------------------------------ XC history (Leonardo)
  final Map<String, SiteXcStats> xcStats = {};
  final Map<String, String> xcErrors = {};
  final Set<String> loadingXc = {};

  /// XC flights of the last [years] years from this takeoff (paraglidingforum.com Leonardo),
  /// joined with the ERA5 weather at their takeoff hour. Started by the user only.
  Future<void> loadXcStats(Site site, {int years = 6}) async {
    if (loadingXc.contains(site.id)) return;
    loadingXc.add(site.id);
    xcErrors.remove(site.id);
    notifyListeners();
    try {
      final now = DateTime.now();
      final flights = await _leonardo.flightsNear(site, from: DateTime(now.year - years, 1, 1), to: now);
      // One archive request per year that has flights (only the span of those flights).
      final hours = <WeatherHour>[];
      final latest = now.subtract(Duration(days: _history.archiveDelayDays));
      for (final year in {for (final f in flights) f.date.year}) {
        final dates = flights.where((f) => f.date.year == year).map((f) => f.date).toList()..sort();
        final end = dates.last.isAfter(latest) ? latest : dates.last;
        if (end.isBefore(dates.first)) continue;
        hours.addAll(await _history.history(site.lat, site.lon, dates.first, end));
      }
      xcStats[site.id] = SiteXcStats.build(site, attachWeather(flights, hours));
    } catch (e) {
      xcErrors[site.id] = 'XC history: $e';
    }
    loadingXc.remove(site.id);
    notifyListeners();
  }

  /// Terrain height for height above ground.
  final ElevationClient elevation;

  /// Historical weather (cached on disk) – also used to tag logbook thermals with their conditions.
  HistoricalWeatherClient get history => _history;

  static final instance = AppState();

  /// Years of history and the ± day window around today that make up the climatology.
  static const historyYears = 5;
  static const historyHalfWindowDays = 15;

  final HttpGet _get;
  final OpenMeteoClient _forecast;
  final HistoricalWeatherClient _history;

  /// Built-in sites plus the pilot's own takeoffs.
  final List<Site> sites = [...sampleSites];

  /// Built-in landing fields plus the pilot's own.
  final List<LandingField> landings = [...landingFields];

  static const _userSitesKey = 'userSites';
  static const _userLandingsKey = 'userLandings';

  Future<void> addUserSite(Site s) async {
    sites.add(s);
    favourites.add(s.id);
    notifyListeners();
    await _saveUserPlaces();
    await _prefs?.setStringList(_favouritesKey, favourites.toList());
  }

  Future<void> addUserLanding(LandingField l) async {
    landings.add(l);
    notifyListeners();
    await _saveUserPlaces();
  }

  Future<void> removeUserSite(Site s) async {
    sites.removeWhere((x) => x.id == s.id);
    favourites.remove(s.id);
    forecasts.remove(s.id);
    if (thermalSiteId == s.id) thermalSiteId = null;
    notifyListeners();
    await _saveUserPlaces();
  }

  Future<void> removeUserLanding(LandingField l) async {
    landings.removeWhere((x) => x.id == l.id);
    notifyListeners();
    await _saveUserPlaces();
  }

  Future<void> _saveUserPlaces() async {
    await _prefs?.setString(_userSitesKey, jsonEncode([for (final s in sites.where((s) => s.userDefined)) s.toJson()]));
    await _prefs?.setString(_userLandingsKey, jsonEncode([for (final l in landings.where((l) => l.userDefined)) l.toJson()]));
  }

  Site siteById(String id) => sites.firstWhere((s) => s.id == id);

  int tab = 0;
  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// Site shown on the Thermals tab.
  String? thermalSiteId;

  void showThermals(Site site) {
    thermalSiteId = site.id;
    tab = 2;
    notifyListeners();
    loadClimatology(site);
  }

  // ------------------------------------------------------------------ favourites
  static const _favouritesKey = 'favourites';
  Set<String> favourites = {...defaultFavouriteIds};
  SharedPreferences? _prefs;

  /// Loads saved favourites; on first start the Black Forest sites are the favourites.
  Future<void> loadFavourites() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final userSites = _prefs!.getString(_userSitesKey);
      if (userSites != null) {
        sites
          ..removeWhere((s) => s.userDefined)
          ..addAll((jsonDecode(userSites) as List).cast<Map<String, dynamic>>().map(Site.fromJson));
      }
      final userLandings = _prefs!.getString(_userLandingsKey);
      if (userLandings != null) {
        landings
          ..removeWhere((l) => l.userDefined)
          ..addAll((jsonDecode(userLandings) as List).cast<Map<String, dynamic>>().map(LandingField.fromJson));
      }
      final saved = _prefs!.getStringList(_favouritesKey);
      if (saved != null) favourites = saved.where((id) => sites.any((s) => s.id == id)).toSet();
    } catch (e) {
      debugPrint('favourites: $e');
    }
    notifyListeners();
  }

  bool isFavourite(Site s) => favourites.contains(s.id);

  Future<void> toggleFavourite(Site s) async {
    if (!favourites.remove(s.id)) favourites.add(s.id);
    notifyListeners();
    await _prefs?.setStringList(_favouritesKey, favourites.toList());
  }

  /// Favourites first (in list order), then the others.
  List<Site> get sitesByFavourite => [...sites.where(isFavourite), ...sites.where((s) => !isFavourite(s))];

  // ------------------------------------------------------------------ thermal map
  /// Centre of the Northern Black Forest favourites (Merkur – Loffenau – Hornisgrinde – Oppenau).
  static const defaultMapCenter = (48.60, 8.28);

  ThermalGrid? grid;
  bool gridLoading = false;
  String? gridError;

  Future<void> loadGrid(double lat, double lon) async {
    if (gridLoading) return;
    gridLoading = true;
    gridError = null;
    notifyListeners();
    try {
      grid = await ThermalGrid.fetch(_get, lat, lon);
    } catch (e) {
      gridError = 'Thermal map: $e';
    }
    gridLoading = false;
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
