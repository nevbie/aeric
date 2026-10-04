import 'dart:convert';
import 'flight/geo.dart';
import 'flight/thermal_conditions.dart';
import 'geo.dart';
import 'open_meteo.dart';
import 'site.dart';
import 'weather_hour.dart';

/// One flight from a Leonardo XC server listing (metadata only, no track).
class LeonardoFlight {
  const LeonardoFlight({
    required this.id,
    required this.date,
    required this.startLat,
    required this.startLon,
    this.startMinutes,
    this.duration,
    this.distanceKm,
    this.maxAltM,
    this.maxClimbMs,
    this.takeoff = '',
  });

  final String id;
  final DateTime date;
  final double startLat;
  final double startLon;

  /// Takeoff time as minutes after midnight (local time of the server's record).
  final int? startMinutes;
  final Duration? duration;
  final double? distanceKm;
  final double? maxAltM;
  final double? maxClimbMs;
  final String takeoff;

  DateTime? get startLocal => startMinutes == null ? null : date.add(Duration(minutes: startMinutes!));
}

/// First number in a formatted Leonardo value ("12.3&nbsp;km", "<span>2.1 m/s</span>").
double? _num(Object? v) {
  if (v == null) return null;
  final s = v.toString().replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').replaceAll(',', '.');
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// "h:mm" or "hh:mm" → minutes.
int? _minutes(Object? v) {
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(v?.toString() ?? '');
  return m == null ? null : int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// Parses `EXT_flight.php?op=list_flights_json`. The server builds the JSON by hand, so a
/// broken object is skipped instead of failing the whole list.
List<LeonardoFlight> parseLeonardoFlights(String body) {
  List<Map<String, dynamic>> objects;
  try {
    objects = ((jsonDecode(body) as Map<String, dynamic>)['flights'] as List).cast<Map<String, dynamic>>();
  } catch (_) {
    objects = [];
    for (final m in RegExp(r'\{[^{}]*\}').allMatches(body)) {
      try {
        objects.add(jsonDecode(m.group(0)!) as Map<String, dynamic>);
      } catch (_) {}
    }
  }
  final out = <LeonardoFlight>[];
  for (final o in objects) {
    final date = DateTime.tryParse('${o['date']}');
    final lat = _num(o['firstLat']), lon = _num(o['firstLon']);
    if (date == null || lat == null || lon == null) continue;
    final dur = _minutes(o['DURATION']);
    out.add(LeonardoFlight(
      id: '${o['flightID']}',
      date: DateTime(date.year, date.month, date.day),
      startLat: lat,
      startLon: lon,
      startMinutes: _minutes(o['START_TIME']),
      duration: dur == null ? null : Duration(minutes: dur),
      distanceKm: _num(o['olcDistance']) ?? _num(o['linearDistance']),
      maxAltM: _num(o['MAX_ALT']),
      maxClimbMs: _num(o['MAX_VARIO']),
      takeoff: '${o['takeoff'] ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), ''),
    ));
  }
  return out;
}

/// Read-only client for the public flight listing of a Leonardo XC server.
/// Only metadata is fetched (no tracklogs), a few requests per site.
class LeonardoClient {
  LeonardoClient(this._get, {this.baseUrl = defaultBaseUrl});

  /// paraglidingforum.com, the largest international Leonardo server.
  static const defaultBaseUrl = 'https://www.paraglidingforum.com/modules/leonardo/EXT_flight.php';

  final HttpGet _get;
  final String baseUrl;

  Uri buildUrl(double lat, double lon, {required DateTime from, required DateTime to, double radiusKm = 2, int count = 500}) {
    int ts(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000;
    return Uri.parse('$baseUrl?op=list_flights_json&lat=${lat.toStringAsFixed(5)}&lon=${lon.toStringAsFixed(5)}'
        '&distance=$radiusKm&tm1=${ts(from)}&tm2=${ts(to)}&count=$count');
  }

  Future<List<LeonardoFlight>> flightsNear(Site site, {required DateTime from, required DateTime to, double radiusKm = 2}) async {
    final flights = parseLeonardoFlights(await _get(buildUrl(site.lat, site.lon, from: from, to: to, radiusKm: radiusKm)));
    // Keep flights that really started at this launch (the server measures from the first fix).
    return flights.where((f) => distanceM(site.lat, site.lon, f.startLat, f.startLon) <= (radiusKm + 0.5) * 1000).toList();
  }
}

/// A Leonardo flight with the weather at its takeoff hour.
class WeatheredFlight {
  const WeatheredFlight(this.flight, this.condition);
  final LeonardoFlight flight;
  final WeatherCondition? condition;
}

class Bucket {
  Bucket(this.label);
  final String label;
  int flights = 0;
  double _km = 0;
  int _kmN = 0;

  void add(LeonardoFlight f) {
    flights++;
    if (f.distanceKm != null) {
      _km += f.distanceKm!;
      _kmN++;
    }
  }

  double? get avgKm => _kmN == 0 ? null : _km / _kmN;
}

/// What XC history says about a takeoff: in which wind, cloud and at what time pilots flew far.
class SiteXcStats {
  SiteXcStats._(this.site, this.flights, this.byWind, this.byCloud, this.byHour, this.byMonth);

  static const _sectors = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  factory SiteXcStats.build(Site site, List<WeatheredFlight> flights) {
    final byWind = {for (final s in [..._sectors, 'calm']) s: Bucket(s)};
    final byCloud = {for (final s in ['0–25 %', '25–50 %', '50–75 %', '75–100 %']) s: Bucket(s)};
    final byHour = <int, Bucket>{};
    final byMonth = {for (var m = 1; m <= 12; m++) m: Bucket(_months[m - 1])};
    for (final w in flights) {
      final f = w.flight, c = w.condition;
      byMonth[f.date.month]!.add(f);
      if (f.startMinutes != null) byHour.putIfAbsent(f.startMinutes! ~/ 60, () => Bucket('${f.startMinutes! ~/ 60}h')).add(f);
      if (c == null) continue;
      byWind[c.windKmh < 5 ? 'calm' : compass(c.windFromDeg)]!.add(f);
      final cc = c.cloudCover;
      if (cc != null) byCloud[byCloud.keys.elementAt((cc / 25).floor().clamp(0, 3))]!.add(f);
    }
    return SiteXcStats._(site, flights, byWind, byCloud, byHour, byMonth);
  }

  final Site site;
  final List<WeatheredFlight> flights;
  final Map<String, Bucket> byWind;
  final Map<String, Bucket> byCloud;
  final Map<int, Bucket> byHour;
  final Map<int, Bucket> byMonth;

  int get withWeather => flights.where((f) => f.condition != null).length;

  /// Flights whose takeoff weather was like [reference].
  List<WeatheredFlight> like(WeatherCondition reference, {ConditionMatcher matcher = const ConditionMatcher()}) =>
      flights.where((f) => f.condition != null && matcher.matches(f.condition!, reference)).toList();

  /// Wind sectors that produced flights, most first.
  List<Bucket> get windRanking => byWind.values.where((b) => b.flights > 0).toList()..sort((a, b) => b.flights.compareTo(a.flights));
}

/// Joins flights with hourly weather (local times) by date and start hour (13:00 when unknown).
List<WeatheredFlight> attachWeather(List<LeonardoFlight> flights, List<WeatherHour> hours) {
  final byHour = {for (final h in hours) DateTime(h.time.year, h.time.month, h.time.day, h.time.hour): h};
  return [
    for (final f in flights)
      () {
        final t = f.startLocal ?? f.date.add(const Duration(hours: 13));
        final h = byHour[DateTime(t.year, t.month, t.day, t.hour)];
        return WeatheredFlight(f, h == null ? null : WeatherCondition.of(h));
      }(),
  ];
}
