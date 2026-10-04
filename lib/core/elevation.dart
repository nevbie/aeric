import 'dart:convert';

import 'open_meteo.dart';

/// Terrain elevation (Copernicus DEM, 90 m) from the Open-Meteo elevation API, cached on a
/// ~100 m grid so a flight needs only a few requests.
class ElevationClient {
  ElevationClient(this._get);
  final HttpGet _get;
  final _cache = <(int, int), double>{};

  static (int, int) _key(double lat, double lon) => ((lat * 1000).round(), (lon * 1000).round());

  double? cached(double lat, double lon) => _cache[_key(lat, lon)];

  Future<double> elevation(double lat, double lon) async {
    final k = _key(lat, lon);
    final hit = _cache[k];
    if (hit != null) return hit;
    final body = await _get(Uri.parse(
      'https://api.open-meteo.com/v1/elevation?latitude=${(k.$1 / 1000).toStringAsFixed(3)}'
      '&longitude=${(k.$2 / 1000).toStringAsFixed(3)}',
    ));
    final v = ((jsonDecode(body) as Map<String, dynamic>)['elevation'] as List).first as num;
    return _cache[k] = v.toDouble();
  }
}
