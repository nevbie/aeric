import 'open_meteo.dart';
import 'weather_hour.dart';

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// An inclusive range of calendar days.
class DateWindow {
  const DateWindow(this.start, this.end);
  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) => other is DateWindow && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => '${_d(start)}..${_d(end)}';
}

/// Historical hourly weather (ERA5 reanalysis) from the Open-Meteo archive API: wind speed and
/// direction, temperature, dew point, cloud cover and solar radiation. The archive lags real
/// time by about five days.
class HistoricalWeatherClient {
  HistoricalWeatherClient(
    this._get, {
    this.baseUrl = 'https://archive-api.open-meteo.com/v1/archive',
    this.archiveDelayDays = 6,
  });

  final HttpGet _get;
  final String baseUrl;
  final int archiveDelayDays;

  static const hourly = [
    'temperature_2m', 'dew_point_2m', 'cloud_cover', 'shortwave_radiation',
    'wind_speed_10m', 'wind_direction_10m', 'wind_gusts_10m',
  ];

  Uri buildUrl(double lat, double lon, DateTime start, DateTime end) => Uri.parse(
        '$baseUrl?latitude=${lat.toStringAsFixed(5)}&longitude=${lon.toStringAsFixed(5)}'
        '&start_date=${_d(start)}&end_date=${_d(end)}&hourly=${hourly.join(',')}'
        '&wind_speed_unit=kmh&timezone=auto',
      );

  Future<List<WeatherHour>> history(double lat, double lon, DateTime start, DateTime end) async =>
      parseOpenMeteo(await _get(buildUrl(lat, lon, start, end)));

  /// The same season in each of the last [years] years: [halfWindowDays] either side of
  /// [date]'s calendar day. Windows not yet in the archive are clipped or skipped.
  List<DateWindow> seasonalWindows(DateTime date, {int years = 5, int halfWindowDays = 15, required DateTime today}) {
    final latest = dateOf(today).subtract(Duration(days: archiveDelayDays));
    final out = <DateWindow>[];
    for (var back = years; back >= 1; back--) {
      // DateTime normalises Feb 29 to Mar 1 in non-leap years, which is fine for a ±15 day window.
      final center = DateTime(date.year - back, date.month, date.day);
      final start = center.subtract(Duration(days: halfWindowDays));
      var end = center.add(Duration(days: halfWindowDays));
      if (end.isAfter(latest)) end = latest;
      if (!start.isAfter(end)) out.add(DateWindow(start, end));
    }
    return out;
  }

  /// Hourly weather of one past day: ERA5 archive, or for the last weeks (not yet in the
  /// archive) the forecast API's stored model runs.
  Future<List<WeatherHour>> day(double lat, double lon, DateTime date, {required DateTime today}) async {
    final d = dateOf(date);
    if (dateOf(today).difference(d).inDays > archiveDelayDays) return history(lat, lon, d, d);
    final ds = _d(d);
    return parseOpenMeteo(await _get(Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${lat.toStringAsFixed(5)}&longitude=${lon.toStringAsFixed(5)}'
      '&start_date=$ds&end_date=$ds&hourly=${hourly.join(',')}&wind_speed_unit=kmh&timezone=auto',
    )));
  }

  Future<List<WeatherHour>> seasonalHistory(
    double lat,
    double lon,
    DateTime date, {
    int years = 5,
    int halfWindowDays = 15,
    required DateTime today,
  }) async {
    final windows = seasonalWindows(date, years: years, halfWindowDays: halfWindowDays, today: today);
    final parts = await Future.wait(windows.map((w) => history(lat, lon, w.start, w.end)));
    return [for (final p in parts) ...p];
  }
}
