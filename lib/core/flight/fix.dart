/// One position fix of a flight (GPS, optionally with barometric altitude).
class Fix {
  const Fix({
    required this.time,
    required this.lat,
    required this.lon,
    required this.gpsAltM,
    this.baroAltM,
    this.valid = true,
  });

  /// UTC time.
  final DateTime time;
  final double lat;
  final double lon;
  final double gpsAltM;
  final double? baroAltM;

  /// IGC validity flag: false for 2D / invalid GPS fixes.
  final bool valid;

  /// Barometric altitude when available (smoother vertical speed), otherwise GPS.
  double get altM => baroAltM ?? gpsAltM;
}
