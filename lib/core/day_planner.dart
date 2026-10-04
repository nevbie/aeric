import 'flyability.dart';
import 'site.dart';
import 'thermal_model.dart';
import 'weather_hour.dart';

class FlyWindow {
  const FlyWindow({required this.start, required this.end, required this.worstVerdict, required this.averageScore});

  final DateTime start;

  /// Exclusive end (start of the first hour after the window).
  final DateTime end;
  final Verdict worstVerdict;
  final int averageScore;

  int get hours => end.difference(start).inHours;
}

class SiteDayPlan {
  const SiteDayPlan({
    required this.site,
    required this.date,
    required this.assessments,
    required this.thermals,
    required this.bestWindow,
  });

  final Site site;
  final DateTime date;
  final List<Assessment> assessments;

  /// Thermal estimate per assessed hour (same order as [assessments]).
  final List<ThermalEstimate> thermals;
  final FlyWindow? bestWindow;

  /// Strongest estimated thermal climb within the best window.
  double get bestWindowPeakClimb {
    final w = bestWindow;
    if (w == null) return 0;
    var best = 0.0;
    for (final t in thermals) {
      if (!t.time.isBefore(w.start) && t.time.isBefore(w.end) && t.climbMs > best) best = t.climbMs;
    }
    return best;
  }
}

class DayPlanner {
  const DayPlanner({
    this.assessor = const FlyabilityAssessor(),
    this.thermalModel = const ThermalModel(),
    this.firstHour = 9,
    this.lastHour = 19,
  });

  final FlyabilityAssessor assessor;
  final ThermalModel thermalModel;
  final int firstHour;
  final int lastHour;

  SiteDayPlan planDay(Site site, List<WeatherHour> forecast, DateTime date) {
    final day = dateOf(date);
    final allDay = forecast.where((h) => dateOf(h.time) == day).toList()..sort((a, b) => a.time.compareTo(b.time));
    // Thermals depend on the heating since sunrise, so estimate over the whole day first.
    final thermalsByTime = {for (final t in thermalModel.estimateDay(site, allDay)) t.time: t};
    final hours = allDay.where((h) => h.time.hour >= firstHour && h.time.hour <= lastHour).toList();
    final assessments = hours.map((h) => assessor.assess(site, h)).toList();
    return SiteDayPlan(
      site: site,
      date: day,
      assessments: assessments,
      thermals: [for (final h in hours) thermalsByTime[h.time]!],
      bestWindow: bestWindow(assessments),
    );
  }

  /// Ranks sites for a day: sites with a GO window first, then by window length, thermals and score.
  List<SiteDayPlan> rankSites(List<SiteDayPlan> plans) {
    int verdictRank(SiteDayPlan p) => p.bestWindow?.worstVerdict.index ?? 1 << 30;
    return [...plans]..sort((a, b) {
        var c = verdictRank(a).compareTo(verdictRank(b));
        if (c != 0) return c;
        c = (b.bestWindow?.hours ?? 0).compareTo(a.bestWindow?.hours ?? 0);
        if (c != 0) return c;
        c = b.bestWindowPeakClimb.compareTo(a.bestWindowPeakClimb);
        if (c != 0) return c;
        return (b.bestWindow?.averageScore ?? 0).compareTo(a.bestWindow?.averageScore ?? 0);
      });
  }

  /// Longest run of consecutive non-NO_GO hours; preferred by more GO hours, then length,
  /// then score.
  FlyWindow? bestWindow(List<Assessment> assessments) {
    final runs = <List<Assessment>>[];
    var current = <Assessment>[];
    for (final a in assessments) {
      final contiguous = current.isEmpty || current.last.hour.time.add(const Duration(hours: 1)) == a.hour.time;
      if (a.verdict == Verdict.noGo || !contiguous) {
        if (current.isNotEmpty) runs.add(current);
        current = [];
      }
      if (a.verdict != Verdict.noGo) current.add(a);
    }
    if (current.isNotEmpty) runs.add(current);
    if (runs.isEmpty) return null;

    int goCount(List<Assessment> r) => r.where((a) => a.verdict == Verdict.go).length;
    int scoreSum(List<Assessment> r) => r.fold(0, (s, a) => s + a.score);
    final best = runs.reduce((a, b) {
      var c = goCount(a).compareTo(goCount(b));
      if (c == 0) c = a.length.compareTo(b.length);
      if (c == 0) c = scoreSum(a).compareTo(scoreSum(b));
      return c >= 0 ? a : b;
    });
    return FlyWindow(
      start: best.first.hour.time,
      end: best.last.hour.time.add(const Duration(hours: 1)),
      worstVerdict: Verdict.values[best.map((a) => a.verdict.index).reduce((a, b) => a > b ? a : b)],
      averageScore: scoreSum(best) ~/ best.length,
    );
  }
}
