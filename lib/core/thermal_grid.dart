import 'dart:convert';
import 'dart:math' as math;

import 'open_meteo.dart';
import 'site.dart';
import 'thermal_model.dart';
import 'weather_hour.dart';

/// One cell of the thermal map with an estimate per hour.
class ThermalCell {
  ThermalCell({
    required this.lat,
    required this.lon,
    required this.halfLat,
    required this.halfLon,
    required this.elevationM,
    required this.hours,
  });

  final double lat;
  final double lon;
  final double halfLat;
  final double halfLon;

  /// Model terrain height of the cell.
  final double elevationM;
  final Map<DateTime, ThermalEstimate> hours;

  /// Corners as (lat, lon), counter-clockwise from south-west.
  List<(double, double)> get corners => [
        (lat - halfLat, lon - halfLon),
        (lat - halfLat, lon + halfLon),
        (lat + halfLat, lon + halfLon),
        (lat + halfLat, lon - halfLon),
      ];

  ThermalEstimate? at(DateTime t) => hours[DateTime(t.year, t.month, t.day, t.hour)];

  /// Strongest hour of [day].
  ThermalEstimate? bestOf(DateTime day) {
    ThermalEstimate? best;
    hours.forEach((t, e) {
      if (dateOf(t) == dateOf(day) && (best == null || e.climbMs > best!.climbMs)) best = e;
    });
    return best;
  }
}

/// Thermal forecast on a regular grid ("Thermik-Karte"): one Open-Meteo request for all grid
/// points, each point run through the same [ThermalModel] as the sites.
class ThermalGrid {
  ThermalGrid(this.cells, {required this.centerLat, required this.centerLon});

  final List<ThermalCell> cells;
  final double centerLat;
  final double centerLon;

  static const hourly = [
    'temperature_2m', 'dew_point_2m', 'cloud_cover', 'shortwave_radiation',
    'wind_speed_10m', 'wind_direction_10m',
  ];

  static double _cosDeg(double d) => math.cos(d * math.pi / 180);

  /// Centres of an [n]×[n] grid covering ±[spanKm] around the centre.
  static List<(double, double)> gridPoints(double lat, double lon, {int n = 10, double spanKm = 45}) {
    final dLat = spanKm / 111.0;
    final dLon = spanKm / (111.0 * _cosDeg(lat));
    return [
      for (var i = 0; i < n; i++)
        for (var j = 0; j < n; j++)
          (lat - dLat + 2 * dLat * (i + 0.5) / n, lon - dLon + 2 * dLon * (j + 0.5) / n),
    ];
  }

  static Uri buildUrl(List<(double, double)> points, {int days = 3}) => Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${points.map((p) => p.$1.toStringAsFixed(4)).join(',')}'
        '&longitude=${points.map((p) => p.$2.toStringAsFixed(4)).join(',')}'
        '&hourly=${hourly.join(',')}&wind_speed_unit=kmh&timezone=auto&forecast_days=$days',
      );

  static Future<ThermalGrid> fetch(
    HttpGet get,
    double lat,
    double lon, {
    int n = 10,
    double spanKm = 45,
    ThermalModel model = const ThermalModel(),
  }) async {
    final points = gridPoints(lat, lon, n: n, spanKm: spanKm);
    return parse(await get(buildUrl(points)), points, centerLat: lat, centerLon: lon, n: n, spanKm: spanKm, model: model);
  }

  static ThermalGrid parse(
    String body,
    List<(double, double)> points, {
    required double centerLat,
    required double centerLon,
    required int n,
    required double spanKm,
    ThermalModel model = const ThermalModel(),
  }) {
    final root = jsonDecode(body);
    final list = root is List ? root : [root];
    final halfLat = spanKm / 111.0 / n;
    final halfLon = spanKm / (111.0 * _cosDeg(centerLat)) / n;
    final cells = <ThermalCell>[];
    for (var k = 0; k < list.length && k < points.length; k++) {
      final o = list[k] as Map<String, dynamic>;
      final (lat, lon) = points[k];
      final elevation = (o['elevation'] as num?)?.toDouble() ?? 0;
      final weather = parseOpenMeteoJson(o);
      // A pseudo-site without launch sectors: thermals only, no flyability rules.
      final point = Site(id: 'grid-$k', name: 'Grid', lat: lat, lon: lon, takeoffElevationM: elevation, sectors: const []);
      cells.add(ThermalCell(
        lat: lat,
        lon: lon,
        halfLat: halfLat,
        halfLon: halfLon,
        elevationM: elevation,
        hours: {for (final e in model.estimate(point, weather)) e.time: e},
      ));
    }
    return ThermalGrid(cells, centerLat: centerLat, centerLon: centerLon);
  }
}
