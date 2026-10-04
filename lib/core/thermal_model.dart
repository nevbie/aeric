import 'dart:math' as math;

import 'site.dart';
import 'solar.dart';
import 'weather_hour.dart';

enum ThermalStrength {
  none('No usable thermals'),
  weak('Weak'),
  moderate('Moderate'),
  strong('Strong'),
  veryStrong('Very strong');

  const ThermalStrength(this.label);
  final String label;

  static ThermalStrength fromClimb(double climbMs) => climbMs < 0.3
      ? none
      : climbMs < 1.0
          ? weak
          : climbMs < 2.0
              ? moderate
              : climbMs < 3.0
                  ? strong
                  : veryStrong;
}

class ThermalEstimate {
  const ThermalEstimate({
    required this.time,
    required this.radiationWm2,
    required this.heatFluxWm2,
    required this.thermalDepthM,
    required this.thermalTopMslM,
    required this.cumulus,
    required this.wStarMs,
    required this.windFactor,
    required this.climbMs,
    required this.notes,
  });

  final DateTime time;

  /// Global radiation reaching the ground (measured/modelled, or derived from cloud cover).
  final double radiationWm2;

  /// Estimated sensible heat flux that drives the thermals.
  final double heatFluxWm2;

  /// Depth of the convective layer above the (model) ground.
  final double thermalDepthM;
  final double thermalTopMslM;

  /// True when thermals reach the condensation level, i.e. cumulus mark them.
  final bool cumulus;

  /// Deardorff convective velocity scale – the typical updraft speed.
  final double wStarMs;

  /// 1 = calm; lower when wind tears the thermals apart.
  final double windFactor;

  /// Estimated average paraglider climb while circling (updraft minus glider sink).
  final double climbMs;
  final List<String> notes;

  ThermalStrength get strength => ThermalStrength.fromClimb(climbMs);
  bool get usable => climbMs >= ThermalModel.usableClimbMs;
}

/// Estimates dry thermals from surface weather – wind, wind direction, temperature, dew point
/// and cloud cover (or radiation) – using simple boundary-layer physics:
///
/// 1. Sun on the ground: radiation from the model, or clear-sky radiation reduced by cloud cover.
/// 2. Sensible heat flux H ≈ [sensibleFraction] × radiation.
/// 3. Thermal depth zi: how far the morning stable layer (potential-temperature gradient
///    [stableLapseKPerM]) has been eroded, as the geometric mean of two estimates – from the
///    accumulated heat since sunrise (encroachment, zi = √(2∫H dt / ρcₚ / γ)) and from the
///    observed 2 m temperature rise since the morning minimum (zi = ΔT / γ). The second one
///    lets the actual temperature history correct the radiation-only estimate.
///    Capped by the convective cloud base (T − Td) × 125 m, where cumulus form.
/// 4. Updraft w* = (g/T · H/ρcₚ · zi)^⅓, reduced in strong wind; climb ≈ 1.5 w* − glider sink.
///
/// Identical inputs are available for historical days, so today can be compared fairly with
/// the climatology. This is a planning aid with an uncertainty of easily ±50 %.
class ThermalModel {
  const ThermalModel({
    this.sensibleFraction = 0.3,
    this.heatFluxOffsetWm2 = 10,
    this.stableLapseKPerM = 0.0035,
    this.superadiabaticK = 1.0,
    this.maxDepthM = 3500,
    this.windCalmKmh = 15,
    this.windTornKmh = 40,
    this.minWindFactor = 0.4,
    this.gliderSinkMs = 1.1,
  });

  static const usableClimbMs = 0.5;
  static const _rhoCp = 1200.0; // J/(m³·K)

  final double sensibleFraction;
  final double heatFluxOffsetWm2;
  final double stableLapseKPerM;

  /// The 2 m air is warmer than the mixed layer above it; this much of the rise is not usable.
  final double superadiabaticK;
  final double maxDepthM;
  final double windCalmKmh;
  final double windTornKmh;
  final double minWindFactor;
  final double gliderSinkMs;

  /// Radiation for an hour: model value if present, otherwise derived from cloud cover.
  double radiation(Site site, WeatherHour h) {
    final sw = h.shortwaveRadiation;
    if (sw != null) return sw;
    // Values are the mean over the preceding hour, so use the sun position half an hour earlier.
    final utc = DateTime.utc(h.time.year, h.time.month, h.time.day, h.time.hour, h.time.minute)
        .subtract(Duration(seconds: h.utcOffsetSeconds, minutes: 30));
    return cloudyRadiation(clearSkyRadiation(sunElevationDeg(site.lat, site.lon, utc)), h.cloudCover ?? 50);
  }

  double windFactor(double windKmh) {
    if (windKmh <= windCalmKmh) return 1;
    final f = 1 - (1 - minWindFactor) * (windKmh - windCalmKmh) / (windTornKmh - windCalmKmh);
    return f.clamp(minWindFactor, 1.0);
  }

  /// Estimates every hour of [hours], which may span several days.
  List<ThermalEstimate> estimate(Site site, List<WeatherHour> hours) {
    final byDay = <DateTime, List<WeatherHour>>{};
    for (final h in hours) {
      byDay.putIfAbsent(dateOf(h.time), () => []).add(h);
    }
    final days = byDay.keys.toList()..sort();
    return [for (final d in days) ...estimateDay(site, byDay[d]!)];
  }

  /// Estimates one calendar day; the hours must belong to the same day.
  List<ThermalEstimate> estimateDay(Site site, List<WeatherHour> dayHours) {
    final hours = [...dayHours]..sort((a, b) => a.time.compareTo(b.time));
    final out = <ThermalEstimate>[];
    var heatSum = 0.0; // ∫H dt / ρcₚ in K·m
    double? minTemp;

    for (final h in hours) {
      final rad = radiation(site, h);
      final flux = math.max(0.0, sensibleFraction * rad - heatFluxOffsetWm2);
      heatSum += flux * 3600 / _rhoCp;

      final t = h.temperature2m;
      if (t != null && (minTemp == null || t < minTemp)) minTemp = t;

      var depth = math.sqrt(2 * heatSum / stableLapseKPerM);
      if (t != null && minTemp != null) {
        final rise = math.max(0.0, t - minTemp - superadiabaticK);
        depth = math.sqrt(depth * rise / stableLapseKPerM);
      }
      if (flux <= 0) depth = 0;

      final base = h.cloudBaseMslM;
      final baseAgl = base == null ? null : base - h.modelElevationM;
      var cumulus = false;
      if (baseAgl != null && depth > 0 && depth >= baseAgl) {
        cumulus = true;
        depth = baseAgl;
      }
      depth = depth.clamp(0.0, maxDepthM);

      final tempK = (t ?? 15) + 273.15;
      final wStar = flux > 0 && depth > 0 ? math.pow(9.81 / tempK * flux / _rhoCp * depth, 1 / 3).toDouble() : 0.0;
      final wf = windFactor(h.windSpeed10m);
      final climb = math.max(0.0, 1.5 * wStar * wf - gliderSinkMs);
      final top = h.modelElevationM + depth;

      out.add(ThermalEstimate(
        time: h.time,
        radiationWm2: rad,
        heatFluxWm2: flux,
        thermalDepthM: depth,
        thermalTopMslM: top,
        cumulus: cumulus,
        wStarMs: wStar,
        windFactor: wf,
        climbMs: climb,
        notes: _notes(site, h, rad, depth, top, cumulus, wf, climb),
      ));
    }
    return out;
  }

  List<String> _notes(Site site, WeatherHour h, double rad, double depth, double top, bool cumulus, double wf, double climb) {
    final notes = <String>[];
    final cc = h.cloudCover;
    if (rad < 30) {
      notes.add('No sun on the ground');
    } else if (cc != null && cc >= 85) {
      notes.add('Overcast (${cc.round()}%) – ground barely heats');
    } else if (cc != null && cc >= 60) {
      notes.add('Mostly cloudy (${cc.round()}%) – intermittent thermals');
    }
    if (wf < 0.8) notes.add('Wind ${h.windSpeed10m.round()} km/h tears thermals apart');
    if (h.windSpeed10m >= 10 && site.sectorDistance(h.windDir10m) >= 90) {
      notes.add('Takeoff in the lee (wind from ${h.windDir10m.round()}°) – rough thermals');
    }
    if (depth > 200) {
      notes.add(cumulus ? 'Cumulus, base ≈ ${_r100(top)} m' : 'Blue thermals up to ≈ ${_r100(top)} m');
      if (top < site.takeoffElevationM + 200) notes.add('Thermals top out below or just at takeoff height');
    }
    final cape = h.cape;
    if (cape != null && cape >= 800 && climb > 0) notes.add('CAPE ${cape.round()} J/kg – over-development possible');
    return notes;
  }
}

int _r100(double v) => (v / 100).round() * 100;
