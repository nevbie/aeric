import 'dart:convert';

import 'weather_hour.dart';

/// Fetches a URL and returns the body; injected so the logic stays testable offline.
typedef HttpGet = Future<String> Function(Uri url);

String _f(double v) => v.toStringAsFixed(5);

/// Hourly forecast from Open-Meteo (https://open-meteo.com). Free for non-commercial use
/// without a key; a commercial release needs their paid API plan.
///
/// `pastDays` also returns the already elapsed hours (model analysis), which the thermal
/// inference uses to see how much the ground has heated up so far today.
class OpenMeteoClient {
  OpenMeteoClient(this._get, {this.baseUrl = 'https://api.open-meteo.com/v1/forecast'});

  final HttpGet _get;
  final String baseUrl;

  static const hourly = [
    'temperature_2m', 'dew_point_2m', 'precipitation_probability', 'cloud_cover', 'cape',
    'shortwave_radiation', 'wind_speed_10m', 'wind_direction_10m', 'wind_gusts_10m',
    'wind_speed_850hPa', 'wind_direction_850hPa', 'wind_speed_700hPa', 'wind_direction_700hPa',
  ];

  Uri buildUrl(double lat, double lon, {int days = 3, int pastDays = 0}) => Uri.parse(
        '$baseUrl?latitude=${_f(lat)}&longitude=${_f(lon)}&hourly=${hourly.join(',')}'
        '&wind_speed_unit=kmh&timezone=auto&forecast_days=$days'
        '${pastDays > 0 ? '&past_days=$pastDays' : ''}',
      );

  Future<List<WeatherHour>> forecast(double lat, double lon, {int days = 3, int pastDays = 0}) async =>
      parseOpenMeteo(await _get(buildUrl(lat, lon, days: days, pastDays: pastDays)));
}

/// Parses an hourly Open-Meteo response; works for both the forecast and the archive API.
List<WeatherHour> parseOpenMeteo(String body) => parseOpenMeteoJson(jsonDecode(body) as Map<String, dynamic>);

/// Parses one location object of an Open-Meteo response (multi-location responses are a list of these).
List<WeatherHour> parseOpenMeteoJson(Map<String, dynamic> root) {
  final elevation = (root['elevation'] as num?)?.toDouble() ?? 0;
  final utcOffset = (root['utc_offset_seconds'] as num?)?.toInt() ?? 0;
  final h = root['hourly'] as Map<String, dynamic>;
  final times = (h['time'] as List).map((t) => DateTime.parse(t as String)).toList();

  List<double?> series(String key) {
    final raw = h[key];
    if (raw is! List) return List.filled(times.length, null);
    return raw.map((v) => (v as num?)?.toDouble()).toList();
  }

  final t = series('temperature_2m');
  final td = series('dew_point_2m');
  final pp = series('precipitation_probability');
  final cc = series('cloud_cover');
  final cape = series('cape');
  final sw = series('shortwave_radiation');
  final ws = series('wind_speed_10m');
  final wd = series('wind_direction_10m');
  final wg = series('wind_gusts_10m');
  final ws850 = series('wind_speed_850hPa');
  final wd850 = series('wind_direction_850hPa');
  final ws700 = series('wind_speed_700hPa');
  final wd700 = series('wind_direction_700hPa');

  final out = <WeatherHour>[];
  for (var i = 0; i < times.length; i++) {
    // Hours without surface wind are useless for assessment; skip them.
    final speed = ws[i];
    final dir = wd[i];
    if (speed == null || dir == null) continue;
    out.add(WeatherHour(
      time: times[i],
      windSpeed10m: speed,
      windDir10m: dir,
      gusts10m: wg[i] ?? speed,
      windSpeed850: ws850[i],
      windDir850: wd850[i],
      windSpeed700: ws700[i],
      windDir700: wd700[i],
      temperature2m: t[i],
      dewPoint2m: td[i],
      precipitationProbability: pp[i],
      cloudCover: cc[i],
      cape: cape[i],
      shortwaveRadiation: sw[i],
      modelElevationM: elevation,
      utcOffsetSeconds: utcOffset,
    ));
  }
  return out;
}
