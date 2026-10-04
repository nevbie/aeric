import 'site.dart';
import 'weather_hour.dart';

enum Verdict { go, marginal, noGo }

class Assessment {
  const Assessment({
    required this.hour,
    required this.verdict,
    required this.score,
    required this.takeoffWindKmh,
    required this.takeoffWindDir,
    required this.reasons,
  });

  final WeatherHour hour;
  final Verdict verdict;

  /// 0 (unflyable) to 100 (ideal).
  final int score;
  final double takeoffWindKmh;
  final double takeoffWindDir;
  final List<String> reasons;
}

/// Rule-based flyability check for a takeoff. Thresholds default to conservative
/// intermediate-pilot values and are deliberately configurable – this is a planning aid,
/// never a substitute for on-site judgement.
class FlyabilityAssessor {
  const FlyabilityAssessor({
    this.gustSpreadMarginalKmh = 10,
    this.gustSpreadNoGoKmh = 15,
    this.upperWindMarginalKmh = 30,
    this.upperWindNoGoKmh = 40,
    this.sectorToleranceDeg = 20,
    this.calmWindKmh = 5,
    this.capeMarginal = 800,
    this.capeNoGo = 1500,
    this.rainMarginalPct = 30,
    this.rainNoGoPct = 60,
    this.cloudBaseMarginalM = 800,
    this.cloudBaseNoGoM = 300,
  });

  final double gustSpreadMarginalKmh;
  final double gustSpreadNoGoKmh;
  final double upperWindMarginalKmh;
  final double upperWindNoGoKmh;
  final double sectorToleranceDeg;
  final double calmWindKmh;
  final double capeMarginal;
  final double capeNoGo;
  final double rainMarginalPct;
  final double rainNoGoPct;
  final double cloudBaseMarginalM;
  final double cloudBaseNoGoM;

  Assessment assess(Site site, WeatherHour h) {
    var verdict = Verdict.go;
    var score = 100;
    final reasons = <String>[];

    void flag(Verdict v, int penalty, String reason) {
      if (v.index > verdict.index) verdict = v;
      score -= penalty;
      reasons.add(reason);
    }

    final (speed, dir) = takeoffWind(site, h);

    // Wind direction vs. launch orientation
    if (speed >= calmWindKmh) {
      final off = site.sectorDistance(dir);
      if (off > sectorToleranceDeg) {
        flag(Verdict.noGo, 50, 'Wind ${dir.round()}° is ${off.round()}° outside launch sector');
      } else if (off > 0) {
        flag(Verdict.marginal, 15, 'Wind ${dir.round()}° at edge of launch sector');
      }
    }

    // Wind strength
    if (speed > site.maxWindKmh) {
      flag(Verdict.noGo, 50, 'Takeoff wind ${speed.round()} km/h above site max ${site.maxWindKmh.round()}');
    } else if (speed > site.maxWindKmh * 0.8) {
      flag(Verdict.marginal, 15, 'Takeoff wind ${speed.round()} km/h close to site max');
    } else if (speed < site.minWindKmh) {
      flag(Verdict.marginal, 10, 'Wind ${speed.round()} km/h below soaring minimum ${site.minWindKmh.round()}');
    }

    // Gustiness
    final spread = h.gusts10m - h.windSpeed10m;
    if (spread > gustSpreadNoGoKmh) {
      flag(Verdict.noGo, 40, 'Gusty: gusts ${spread.round()} km/h above mean');
    } else if (spread > gustSpreadMarginalKmh) {
      flag(Verdict.marginal, 15, 'Gusts ${spread.round()} km/h above mean');
    }

    // Upper wind (≈3000 m), relevant for XC and lee turbulence
    final up = h.windSpeed700;
    if (up != null) {
      if (up > upperWindNoGoKmh) {
        flag(Verdict.noGo, 30, 'Strong wind aloft: ${up.round()} km/h at 700 hPa');
      } else if (up > upperWindMarginalKmh) {
        flag(Verdict.marginal, 10, 'Wind aloft ${up.round()} km/h at 700 hPa');
      }
    }

    // Rain
    final rain = h.precipitationProbability;
    if (rain != null) {
      if (rain >= rainNoGoPct) {
        flag(Verdict.noGo, 50, 'Rain likely (${rain.round()}%)');
      } else if (rain >= rainMarginalPct) {
        flag(Verdict.marginal, 15, 'Possible showers (${rain.round()}%)');
      }
    }

    // Thunderstorm / over-development risk
    final cape = h.cape;
    if (cape != null) {
      if (cape >= capeNoGo) {
        flag(Verdict.noGo, 40, 'High CAPE ${cape.round()} J/kg – thunderstorm risk');
      } else if (cape >= capeMarginal) {
        flag(Verdict.marginal, 10, 'Moderate CAPE ${cape.round()} J/kg – watch for over-development');
      }
    }

    // Cloud base relative to takeoff
    final base = h.cloudBaseMslM;
    if (base != null) {
      final above = base - site.takeoffElevationM;
      if (above < cloudBaseNoGoM) {
        flag(Verdict.noGo, 40, 'Cloud base only ${above.round()} m above takeoff');
      } else if (above < cloudBaseMarginalM) {
        flag(Verdict.marginal, 10, 'Low cloud base (${above.round()} m above takeoff)');
      }
    }

    if (reasons.isEmpty) reasons.add('Looks good');
    return Assessment(
      hour: h,
      verdict: verdict,
      score: score.clamp(0, 100),
      takeoffWindKmh: speed,
      takeoffWindDir: dir,
      reasons: reasons,
    );
  }

  /// Chooses the forecast level that best represents the wind at launch height.
  /// 10 m winds refer to the (smoothed) model terrain, which in mountains is usually far
  /// below the takeoff, so pressure-level winds are used for high launches.
  (double, double) takeoffWind(Site site, WeatherHour h) {
    final above = site.takeoffElevationM - h.modelElevationM;
    if (above > 400 && site.takeoffElevationM >= 2300 && h.windSpeed700 != null && h.windDir700 != null) {
      return (h.windSpeed700!, h.windDir700!);
    }
    if (above > 400 && site.takeoffElevationM >= 1000 && h.windSpeed850 != null && h.windDir850 != null) {
      return (h.windSpeed850!, h.windDir850!);
    }
    return (h.windSpeed10m, h.windDir10m);
  }
}
