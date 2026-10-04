/// One weather hour (forecast or historical reanalysis). Speeds in km/h, directions in degrees
/// (FROM), temperatures in °C, radiation in W/m² (mean of the preceding hour), cover in %.
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.windSpeed10m,
    required this.windDir10m,
    required this.gusts10m,
    this.windSpeed850,
    this.windDir850,
    this.windSpeed700,
    this.windDir700,
    this.temperature2m,
    this.dewPoint2m,
    this.precipitationProbability,
    this.cloudCover,
    this.cape,
    this.shortwaveRadiation,
    this.modelElevationM = 0,
    this.utcOffsetSeconds = 0,
  });

  /// Local wall-clock time at the site (a "naive" DateTime; do not convert time zones).
  final DateTime time;
  final double windSpeed10m;
  final double windDir10m;
  final double gusts10m;
  final double? windSpeed850;
  final double? windDir850;
  final double? windSpeed700;
  final double? windDir700;
  final double? temperature2m;
  final double? dewPoint2m;
  final double? precipitationProbability;
  final double? cloudCover;
  final double? cape;
  final double? shortwaveRadiation;

  /// Elevation of the model grid cell the surface values refer to.
  final double modelElevationM;

  /// Offset of [time] from UTC, needed for the sun position.
  final int utcOffsetSeconds;

  /// Convective cloud base MSL via the Espy approximation (125 m per °C of spread).
  double? get cloudBaseMslM => temperature2m != null && dewPoint2m != null
      ? modelElevationM + 125 * (temperature2m! - dewPoint2m!).clamp(0, double.infinity)
      : null;

  WeatherHour copyWith({
    DateTime? time,
    double? windSpeed10m,
    double? windDir10m,
    double? gusts10m,
    double? windSpeed850,
    double? windDir850,
    double? temperature2m,
    double? dewPoint2m,
    double? precipitationProbability,
    double? cloudCover,
    double? cape,
    double? shortwaveRadiation,
  }) =>
      WeatherHour(
        time: time ?? this.time,
        windSpeed10m: windSpeed10m ?? this.windSpeed10m,
        windDir10m: windDir10m ?? this.windDir10m,
        gusts10m: gusts10m ?? this.gusts10m,
        windSpeed850: windSpeed850 ?? this.windSpeed850,
        windDir850: windDir850 ?? this.windDir850,
        windSpeed700: windSpeed700,
        windDir700: windDir700,
        temperature2m: temperature2m ?? this.temperature2m,
        dewPoint2m: dewPoint2m ?? this.dewPoint2m,
        precipitationProbability: precipitationProbability ?? this.precipitationProbability,
        cloudCover: cloudCover ?? this.cloudCover,
        cape: cape ?? this.cape,
        shortwaveRadiation: shortwaveRadiation ?? this.shortwaveRadiation,
        modelElevationM: modelElevationM,
        utcOffsetSeconds: utcOffsetSeconds,
      );
}

DateTime dateOf(DateTime t) => DateTime(t.year, t.month, t.day);
