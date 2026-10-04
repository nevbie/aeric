/// A landing field (used for final glide).
class LandingField {
  const LandingField({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.elevationM,
    this.siteIds = const [],
    this.userDefined = false,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final double elevationM;

  /// Takeoffs this field belongs to.
  final List<String> siteIds;
  final bool userDefined;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'lat': lat, 'lon': lon, 'ele': elevationM, 'sites': siteIds};

  factory LandingField.fromJson(Map<String, dynamic> j) => LandingField(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        elevationM: (j['ele'] as num).toDouble(),
        siteIds: (j['sites'] as List? ?? const []).cast<String>(),
        userDefined: true,
      );
}

double _dms(int d, int m, double s) => d + m / 60 + s / 3600;

/// Official landing fields of the favourite sites (DHV database and club pages).
final landingFields = [
  LandingField(
    id: 'loffenau', name: 'Loffenau Landewiese', lat: _dms(48, 46, 21.76), lon: _dms(8, 23, 53.18),
    elevationM: 389, siteIds: const ['loffenau-west', 'loffenau-nw'],
  ),
  LandingField(
    id: 'merkur-west', name: 'Merkur Landeplatz West', lat: _dms(48, 45, 47.5), lon: _dms(8, 15, 42.8),
    elevationM: 250, siteIds: const ['merkur-west'],
  ),
  LandingField(
    id: 'merkur-grossmatte', name: 'Merkur Landeplatz Großmatte', lat: _dms(48, 45, 49.37), lon: _dms(8, 15, 40.02),
    elevationM: 240, siteIds: const ['merkur-west'],
  ),
  LandingField(
    id: 'merkur-no', name: 'Merkur Landeplatz Nordost (Staufenberg)', lat: _dms(48, 46, 0.91), lon: _dms(8, 17, 42.94),
    elevationM: 360, siteIds: const ['merkur-no'],
  ),
  LandingField(
    id: 'hornisgrinde', name: 'Hornisgrinde Landeplatz Seebach', lat: _dms(48, 35, 24.28), lon: _dms(8, 9, 47.95),
    elevationM: 463, siteIds: const ['hornisgrinde'],
  ),
  LandingField(
    id: 'oppenau-nockenbauernhof', name: 'Oppenau Nockenbauernhof', lat: _dms(48, 28, 47), lon: _dms(8, 13, 17),
    elevationM: 500, siteIds: const ['oppenau-rossbuehl', 'oppenau-sandkopf'],
  ),
  LandingField(
    id: 'oppenau-bruhansenhof', name: 'Oppenau Bruhansenhof', lat: _dms(48, 27, 4.14), lon: _dms(8, 9, 55.59),
    elevationM: 305, siteIds: const ['oppenau-schaefersfeld', 'oppenau-ibach'],
  ),
];
