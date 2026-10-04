import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/flight/thermal_conditions.dart';
import '../core/geo.dart';
import '../core/leonardo.dart';
import '../core/live_thermal.dart';
import '../core/site.dart';
import '../core/thermal_climatology.dart';
import '../core/thermal_model.dart';
import '../services/app_state.dart';
import 'common.dart';

/// Live thermal conditions inferred from today's weather so far and the forecast,
/// set against historical weather of the same season.
class ThermalScreen extends StatefulWidget {
  const ThermalScreen({super.key});

  @override
  State<ThermalScreen> createState() => _ThermalScreenState();
}

class _ThermalScreenState extends State<ThermalScreen> {
  final app = AppState.instance;
  Timer? _tick;

  Site get site => app.thermalSiteId == null ? app.sitesByFavourite.first : app.siteById(app.thermalSiteId!);

  @override
  void initState() {
    super.initState();
    // Not during build: loading notifies listeners right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) app.loadClimatology(site);
    });
    // Keep "now" current; pull a fresh model run every 30 minutes.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      final loaded = app.forecastsLoadedAt;
      if (loaded == null || DateTime.now().difference(loaded) > const Duration(minutes: 30)) {
        app.refreshForecasts();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _select(Site s) {
    app.thermalSiteId = s.id;
    app.loadClimatology(s);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final hours = app.forecasts[site.id];
    final clim = app.climatologies[site.id];
    final report = hours == null
        ? null
        : LiveThermalReport.infer(site: site, hours: hours, now: app.siteNow(site), climatology: clim);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final s in app.sitesByFavourite)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: app.isFavourite(s) ? const Icon(Icons.star, size: 16, color: Colors.amber) : null,
                      label: Text(s.name),
                      selected: site.id == s.id,
                      onSelected: (_) => _select(s),
                    ),
                  ),
              ]),
            ),
          ),
          IconButton(
            onPressed: () {
              app.refreshForecasts();
              app.loadClimatology(site, force: app.climatologyErrors.containsKey(site.id));
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ]),
      ),
      if (app.loadingForecasts || app.loadingClimatology.contains(site.id)) const LinearProgressIndicator(),
      if (app.forecastErrors[site.id] case final e?) ErrorText('Forecast: $e'),
      if (app.climatologyErrors[site.id] case final e?) ErrorText('History: $e'),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (report != null) ...[
              _NowCard(report),
              const SizedBox(height: 10),
              _TodayCard(report),
              const SizedBox(height: 10),
            ],
            if (clim != null) _ClimatologyCard(clim, app.siteNow(site)),
            const SizedBox(height: 10),
            _XcCard(site),
            if (clim == null && app.loadingClimatology.contains(site.id))
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Loading ${AppState.historyYears} years of historical weather…'),
              ),
            const Disclaimer(),
          ],
        ),
      ),
    ]);
  }
}

String _m(double v) => '${(v / 50).round() * 50} m';

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 104,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.labelSmall),
        Text(value, style: t.titleSmall),
      ]),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard(this.r);
  final LiveThermalReport r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = r.current;
    final w = r.weatherNow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Now at ${r.site.name} · ${hhmm(r.now)}', style: t.labelLarge)),
            FavouriteButton(r.site),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Dot(climbColor(c?.climbMs ?? 0), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(r.headline, style: t.titleMedium)),
          ]),
          if (c != null && w != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 10, children: [
              _Metric('Climb (est.)', '${c.climbMs.toStringAsFixed(1)} m/s'),
              _Metric('Updraft w*', '${c.wStarMs.toStringAsFixed(1)} m/s'),
              _Metric(c.cumulus ? 'Cloud base' : 'Thermal top', c.thermalDepthM > 0 ? _m(c.thermalTopMslM) : '–'),
              _Metric(
                'Above takeoff',
                c.thermalDepthM > 0 ? _m(math.max(0, c.thermalTopMslM - r.site.takeoffElevationM)) : '–',
              ),
              _Metric('Temperature', w.temperature2m == null ? '–' : '${w.temperature2m!.toStringAsFixed(1)} °C'),
              _Metric('Cloud cover', w.cloudCover == null ? '–' : '${w.cloudCover!.round()} %'),
              _Metric('Wind', '${w.windSpeed10m.round()} km/h ${compass(w.windDir10m)}'),
              _Metric('Sun on ground', '${c.radiationWm2.round()} W/m²'),
            ]),
          ],
          if (r.percentileNow case final p?) ...[
            const SizedBox(height: 14),
            Text('Compared with the same hour on historical days', style: t.labelSmall),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: p / 100, minHeight: 8, color: climbColor(c?.climbMs ?? 0)),
            ),
            const SizedBox(height: 2),
            Text('Stronger than ${p.round()} % of comparable days', style: t.bodySmall),
          ],
          if (c != null && c.notes.isNotEmpty || r.trends.isNotEmpty) ...[
            const Divider(height: 20),
            for (final s in r.trends) _Bullet(Icons.trending_up, s),
            for (final s in c?.notes ?? const <String>[]) _Bullet(Icons.info_outline, s),
          ],
        ]),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ]),
      );
}

/// Today hour by hour: estimated climb against the historical range for that hour.
class _TodayCard extends StatelessWidget {
  const _TodayCard(this.r);
  final LiveThermalReport r;

  static const _scaleMs = 4.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final clim = r.climatology;
    final rows = [
      for (var i = 0; i < r.today.length; i++)
        if (r.today[i].time.hour >= 8 && r.today[i].time.hour <= 19) i,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Today vs. history', style: t.titleMedium),
          for (final s in r.comparisons) _Bullet(Icons.history, s),
          if (r.peakPercentile case final p?)
            _Bullet(Icons.emoji_events_outlined, 'Today\'s peak ranks above ${p.round()} % of historical days'),
          const SizedBox(height: 10),
          Text(
            clim == null ? 'Estimated climb (m/s)' : 'Estimated climb (bar) vs. historical median and middle 50 % (grey)',
            style: t.labelSmall,
          ),
          const SizedBox(height: 4),
          for (final i in rows) _hourRow(context, i),
        ]),
      ),
    );
  }

  Widget _hourRow(BuildContext context, int i) {
    final e = r.today[i];
    final w = r.weatherToday[i];
    final hc = r.climatology?.at(e.time.hour);
    final isNow = r.weatherNow?.time == e.time;
    final small = Theme.of(context).textTheme.bodySmall;
    final grey = Theme.of(context).colorScheme.outlineVariant;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      color: isNow ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
      child: Row(children: [
        SizedBox(width: 44, child: Text(hhmm(e.time), style: small?.copyWith(fontWeight: isNow ? FontWeight.bold : null))),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            double x(double v) => box.maxWidth * (v / _scaleMs).clamp(0.0, 1.0);
            return SizedBox(
              height: 14,
              child: Stack(children: [
                if (hc != null)
                  Positioned(
                    left: x(hc.p25Climb),
                    width: math.max(2, x(hc.p75Climb) - x(hc.p25Climb)),
                    top: 2,
                    bottom: 2,
                    child: Container(color: grey),
                  ),
                Positioned(
                  left: 0,
                  width: x(e.climbMs),
                  top: 4,
                  bottom: 4,
                  child: Container(
                    decoration: BoxDecoration(color: climbColor(e.climbMs), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                if (hc != null)
                  Positioned(left: x(hc.medianClimb) - 1, width: 2, top: 0, bottom: 0, child: Container(color: onSurface)),
              ]),
            );
          }),
        ),
        SizedBox(width: 36, child: Text(e.climbMs.toStringAsFixed(1), textAlign: TextAlign.right, style: small)),
        SizedBox(
          width: 78,
          child: Text('${w.windSpeed10m.round()} ${compass(w.windDir10m)}', textAlign: TextAlign.right, style: small),
        ),
        SizedBox(
          width: 44,
          child: Text(w.cloudCover == null ? '' : '☁${w.cloudCover!.round()}', textAlign: TextAlign.right, style: small),
        ),
      ]),
    );
  }
}

/// What the season usually looks like at this site, from historical hourly weather.
class _ClimatologyCard extends StatelessWidget {
  const _ClimatologyCard(this.c, this.today);
  final ThermalClimatology c;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final small = t.bodySmall;
    final bold = small?.copyWith(fontWeight: FontWeight.bold);
    final window = c.typicalWindow;
    final hours = c.hours.keys.where((h) => h >= 8 && h <= 19).toList()..sort();

    Widget cell(String s, double w, {TextStyle? style, TextAlign align = TextAlign.right}) =>
        SizedBox(width: w, child: Text(s, textAlign: align, style: style ?? small));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Thermal climatology', style: t.titleMedium),
          Text(
            c.isEmpty
                ? 'No historical data available.'
                : '${c.days} days, ±${AppState.historyHalfWindowDays} days around ${today.day}.${today.month}. '
                    'in ${c.firstDay!.year}–${c.lastDay!.year} (ERA5 reanalysis)',
            style: small,
          ),
          if (!c.isEmpty) ...[
            const SizedBox(height: 6),
            _Bullet(Icons.wb_sunny_outlined, 'Usable thermals on ${(c.usableDayFraction * 100).round()} % of days'),
            _Bullet(
              Icons.schedule,
              window == null
                  ? 'Typical day: no usable thermals'
                  : 'Typical thermal window ${window.$1.toString().padLeft(2, '0')}:00–${(window.$2 + 1).toString().padLeft(2, '0')}:00',
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  cell('Hour', 40, style: bold, align: TextAlign.left),
                  cell('Climb', 46, style: bold),
                  cell('Usable', 52, style: bold),
                  cell('Temp', 50, style: bold),
                  cell('Cloud', 48, style: bold),
                  cell('Wind', 80, style: bold),
                  cell('Top', 64, style: bold),
                ]),
                for (final h in hours)
                  if (c.at(h) case final hc?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(children: [
                        cell('${h.toString().padLeft(2, '0')}:00', 40, align: TextAlign.left),
                        cell(hc.medianClimb.toStringAsFixed(1), 46,
                            style: small?.copyWith(color: climbColor(hc.medianClimb), fontWeight: FontWeight.w600)),
                        cell('${(hc.usableFraction * 100).round()} %', 52),
                        cell('${hc.meanTemp.toStringAsFixed(0)} °C', 50),
                        cell('${hc.meanCloudCover.round()} %', 48),
                        cell(
                          '${hc.meanWindKmh.round()} ${hc.windSteadiness >= 0.4 ? compass(hc.prevailingWindDir) : 'var'}',
                          80,
                        ),
                        cell(hc.medianTopMslM == null ? '–' : _m(hc.medianTopMslM!), 64),
                      ]),
                    ),
              ]),
            ),
            const SizedBox(height: 6),
            Text(
              'Climb = median estimated paraglider climb; Usable = share of days ≥ ${ThermalModel.usableClimbMs} m/s; '
              'Wind = mean speed (km/h) and prevailing direction.',
              style: small,
            ),
          ],
        ]),
      ),
    );
  }
}

/// XC flights from this takeoff on Leonardo (paraglidingforum.com) by the weather they were flown in.
class _XcCard extends StatelessWidget {
  const _XcCard(this.site);
  final Site site;

  /// Forecast at 13:00 today (or tomorrow when it is late) for "flights in weather like …".
  (WeatherCondition, String)? _reference(AppState app) {
    final f = app.forecasts[site.id];
    if (f == null) return null;
    final now = app.siteNow(site);
    final day = now.hour >= 16 ? DateTime(now.year, now.month, now.day + 1) : DateTime(now.year, now.month, now.day);
    final h = f.where((x) => x.time == DateTime(day.year, day.month, day.day, 13)).firstOrNull;
    return h == null ? null : (WeatherCondition.of(h), now.hour >= 16 ? 'tomorrow 13:00' : 'today 13:00');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final t = Theme.of(context).textTheme;
    final stats = app.xcStats[site.id];
    final loading = app.loadingXc.contains(site.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('XC history (Leonardo)', style: t.titleMedium),
          if (stats == null) ...[
            Text(
              'XC flights that started here in the last 6 years (paraglidingforum.com Leonardo, metadata only), '
              'matched with the weather at their takeoff hour.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            loading
                ? const LinearProgressIndicator()
                : FilledButton.tonalIcon(
                    onPressed: () => app.loadXcStats(site),
                    icon: const Icon(Icons.download),
                    label: const Text('Load XC flights'),
                  ),
          ],
          if (app.xcErrors[site.id] case final e?) ErrorText(e),
          if (stats != null) ..._content(context, app, stats),
        ]),
      ),
    );
  }

  List<Widget> _content(BuildContext context, AppState app, SiteXcStats stats) {
    final t = Theme.of(context).textTheme;
    if (stats.flights.isEmpty) return [Text('No XC flights from this takeoff on Leonardo.', style: t.bodySmall)];
    final ref = _reference(app);
    final like = ref == null ? null : stats.like(ref.$1);
    final maxWind = stats.windRanking.isEmpty ? 1 : stats.windRanking.first.flights;
    final hours = stats.byHour.entries.toList()..sort((a, b) => b.value.flights.compareTo(a.value.flights));
    final months = stats.byMonth.values.where((b) => b.flights > 0).toList()..sort((a, b) => b.flights.compareTo(a.flights));
    String km(Bucket b) => b.avgKm == null ? '' : ' · Ø ${b.avgKm!.toStringAsFixed(0)} km';
    return [
      Text('${stats.flights.length} flights · ${stats.withWeather} with weather', style: t.bodySmall),
      if (ref != null && like != null)
        _Bullet(
          Icons.air,
          '${like.length} flights were flown in weather like ${ref.$2} '
          '(${ref.$1.windKmh.round()} km/h ${compass(ref.$1.windFromDeg)}'
          '${ref.$1.cloudCover == null ? '' : ', ☁${ref.$1.cloudCover!.round()} %'})'
          '${like.isEmpty ? '' : ', longest ${like.map((w) => w.flight.distanceKm ?? 0).reduce((a, b) => a > b ? a : b).toStringAsFixed(0)} km'}',
        ),
      const SizedBox(height: 8),
      Text('Wind at takeoff', style: t.labelMedium),
      for (final b in stats.windRanking)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            SizedBox(width: 40, child: Text(b.label, style: t.bodySmall)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: box.maxWidth * b.flights / maxWind,
                    height: 10,
                    decoration: BoxDecoration(color: aericBlue, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 96, child: Text('${b.flights}${km(b)}', textAlign: TextAlign.right, style: t.bodySmall)),
          ]),
        ),
      const SizedBox(height: 8),
      Text('Cloud cover at takeoff', style: t.labelMedium),
      Text(
        stats.byCloud.values.where((b) => b.flights > 0).map((b) => '${b.label}: ${b.flights}${km(b)}').join(' · '),
        style: t.bodySmall,
      ),
      if (hours.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Takeoff time', style: t.labelMedium),
        Text(hours.take(4).map((e) => '${e.key}:00 – ${e.value.flights}').join(' · '), style: t.bodySmall),
      ],
      const SizedBox(height: 8),
      Text('Best months', style: t.labelMedium),
      Text(months.take(4).map((b) => '${b.label} ${b.flights}${km(b)}').join(' · '), style: t.bodySmall),
      const SizedBox(height: 6),
      Text(
        'Source: paraglidingforum.com Leonardo (public listing). Times as recorded by the server.',
        style: t.bodySmall?.copyWith(fontSize: 11),
      ),
    ];
  }
}
