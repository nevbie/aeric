import 'package:flutter/material.dart';

import '../core/day_planner.dart';
import '../core/flyability.dart';
import '../core/geo.dart';
import '../core/thermal_model.dart';
import '../services/app_state.dart';
import 'common.dart';

/// Today / tomorrow / day after: sites ranked by their best flyable window.
class FlyScreen extends StatefulWidget {
  const FlyScreen({super.key});

  @override
  State<FlyScreen> createState() => _FlyScreenState();
}

class _FlyScreenState extends State<FlyScreen> {
  int dayOffset = 0;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final now = DateTime.now();
    final days = [for (var i = 0; i < 3; i++) DateTime(now.year, now.month, now.day + i)];
    const planner = DayPlanner();
    final plans = planner.rankSites([
      for (final s in app.sites)
        if (app.forecasts[s.id] case final f?) planner.planDay(s, f, days[dayOffset]),
    ]);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < days.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(i == 0 ? 'Today' : i == 1 ? 'Tomorrow' : weekdays[days[i].weekday - 1]),
                      selected: dayOffset == i,
                      onSelected: (_) => setState(() => dayOffset = i),
                    ),
                  ),
              ]),
            ),
          ),
          IconButton(onPressed: app.refreshForecasts, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ]),
      ),
      if (app.loadingForecasts) const LinearProgressIndicator(),
      for (final e in app.forecastErrors.entries)
        ErrorText('${app.sites.firstWhere((s) => s.id == e.key).name}: ${e.value}'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final p in plans) Padding(padding: const EdgeInsets.only(bottom: 10), child: _SiteCard(p)),
            const Disclaimer(),
          ],
        ),
      ),
    ]);
  }
}

class _SiteCard extends StatefulWidget {
  const _SiteCard(this.plan);
  final SiteDayPlan plan;

  @override
  State<_SiteCard> createState() => _SiteCardState();
}

class _SiteCardState extends State<_SiteCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final w = plan.bestWindow;
    final text = Theme.of(context).textTheme;
    final peak = plan.bestWindowPeakClimb;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => expanded = !expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Dot(verdictColor(w?.worstVerdict ?? Verdict.noGo)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(plan.site.name, style: text.titleMedium),
                  Text(
                    w == null
                        ? 'No flyable window'
                        : '${hhmm(w.start)}–${hhmm(w.end)} · ${w.hours} h · score ${w.averageScore}'
                            '${peak >= ThermalModel.usableClimbMs ? ' · thermals ≤ ${peak.toStringAsFixed(1)} m/s' : ''}',
                    style: text.bodyMedium,
                  ),
                ]),
              ),
              Text('${plan.site.takeoffElevationM.round()} m', style: text.labelMedium),
            ]),
            const SizedBox(height: 10),
            // Verdict strip (top) and thermal strip (bottom), one cell per daylight hour.
            Row(children: [
              for (final a in plan.assessments)
                Expanded(
                  child: Container(
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(color: verdictColor(a.verdict), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              for (final t in plan.thermals)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(color: climbColor(t.climbMs), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ]),
            if (expanded) ...[
              const Divider(height: 18),
              for (var i = 0; i < plan.assessments.length; i++) _HourRow(plan.assessments[i], plan.thermals[i]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow(this.a, this.t);
  final Assessment a;
  final ThermalEstimate t;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 48, child: Text(hhmm(a.hour.time), style: Theme.of(context).textTheme.labelLarge)),
        SizedBox(
          width: 86,
          child: Text(
            '${a.takeoffWindKmh.round()} km/h ${compass(a.takeoffWindDir)}',
            style: small?.copyWith(color: verdictColor(a.verdict), fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(
            t.usable ? '↑${t.climbMs.toStringAsFixed(1)}' : '–',
            style: small?.copyWith(color: climbColor(t.climbMs), fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(a.reasons.join('; '), style: small)),
      ]),
    );
  }
}
