import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/day_planner.dart';
import '../core/flight/thermal_conditions.dart';
import '../core/geo.dart';
import '../core/flyability.dart';
import '../core/site.dart';
import '../core/thermal_grid.dart';
import '../core/solar.dart';
import '../core/task/task.dart';
import '../core/thermal_model.dart';
import '../services/app_state.dart';
import '../services/airspace_store.dart';
import '../services/logbook.dart';
import '../services/task_store.dart';
import 'common.dart';
import 'place_editor.dart';

/// Topographic base map with relief; fine for personal use, attribution required.
const topoTiles = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';

/// Historical thermal maps from thermal.kk7.ch, computed from XContest flights (non-commercial use).
/// [layer] is e.g. `thermals_all_all` or the seasonal `thermals_jul_07`.
String kk7Tiles(String layer) => 'https://thermal.kk7.ch/tiles/$layer/{z}/{x}/{y}.png?src=aeric';

/// "Thermik-Karte": forecast thermal heatmap, historical hotspots/skyways and the takeoffs.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.showTiles});

  /// Network tile layers; null = [tilesEnabled].
  final bool? showTiles;

  /// Global switch for network tiles (widget tests turn it off).
  static bool tilesEnabled = true;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  final app = AppState.instance;

  int dayOffset = 0;

  /// 0 = strongest hour of the day, otherwise the hour of day.
  int hour = 0;
  bool showThermals = true;
  bool showHotspots = false;
  bool showSkyways = false;

  /// kk7 layers for this season and time of day instead of all-year.
  bool kk7Seasonal = true;

  /// Thermals from the logbook; [matchToday] highlights those flown in conditions like the
  /// forecast for the selected day/hour.
  bool showMine = true;
  bool showAirspace = true;
  bool matchToday = true;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    Logbook.instance.load();
    AirspaceStore.instance.load();
  }

  DateTime get _when => hour == 0
      ? DateTime(day.year, day.month, day.day, dayOffset == 0 ? DateTime.now().hour.clamp(10, 18) : 13)
      : DateTime(day.year, day.month, day.day, hour);

  String _kk7(String type) {
    if (!kk7Seasonal) return '${type}_all_all';
    final c = _map.camera.center;
    final sunrise = sunriseHourLocal(c.latitude, c.longitude, _when, DateTime.now().timeZoneOffset.inSeconds) ?? 6.5;
    return kk7Layer(type, _when, sunriseHour: sunrise);
  }

  /// Forecast weather at the selected time, from the favourite site nearest to the map centre.
  (WeatherCondition, Site)? _referenceCondition() {
    final c = _map.camera.center;
    (WeatherCondition, Site)? best;
    var bestD = double.infinity;
    for (final s in app.sites) {
      final f = app.forecasts[s.id];
      if (f == null) continue;
      final d = (s.lat - c.latitude).abs() + (s.lon - c.longitude).abs();
      if (d >= bestD) continue;
      final w = _when;
      final h = f.where((x) => x.time == DateTime(w.year, w.month, w.day, w.hour)).firstOrNull;
      if (h == null) continue;
      bestD = d;
      best = (WeatherCondition.of(h), s);
    }
    return best;
  }

  bool get _tiles => widget.showTiles ?? MapScreen.tilesEnabled;

  DateTime get day {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + dayOffset);
  }

  ThermalEstimate? _value(ThermalCell c) =>
      hour == 0 ? c.bestOf(day) : c.at(DateTime(day.year, day.month, day.day, hour));

  void _ensureGrid() {
    if (_requested || app.grid != null) return;
    _requested = true;
    final (lat, lon) = AppState.defaultMapCenter;
    Future.microtask(() => app.loadGrid(lat, lon));
  }

  SiteDayPlan? _plan(Site s) {
    final f = app.forecasts[s.id];
    return f == null ? null : const DayPlanner().planDay(s, f, day);
  }

  Future<void> _onSiteTap(Site s) async {
    final plan = _plan(s);
    final w = plan?.bestWindow;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s.name, style: Theme.of(ctx).textTheme.titleLarge)),
              FavouriteButton(s),
            ]),
            Text(
              '${s.takeoffElevationM.round()} m'
              '${s.landingElevationM == null ? '' : ' · landing ${s.landingElevationM!.round()} m'}',
            ),
            const SizedBox(height: 6),
            Row(children: [
              Dot(verdictColor(w?.worstVerdict ?? Verdict.noGo)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan == null
                      ? 'Forecast not loaded'
                      : w == null
                          ? 'No flyable window'
                          : '${hhmm(w.start)}–${hhmm(w.end)} · ${w.hours} h'
                              '${plan.bestWindowPeakClimb >= ThermalModel.usableClimbMs ? ' · thermals ≤ ${plan.bestWindowPeakClimb.toStringAsFixed(1)} m/s' : ''}',
                ),
              ),
            ]),
            if (s.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(s.notes, style: Theme.of(ctx).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.wb_sunny_outlined),
                label: const Text('Live thermals'),
                onPressed: () {
                  Navigator.pop(ctx);
                  app.showThermals(s);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _siteMarker(Site s) {
    final w = _plan(s)?.bestWindow;
    final fav = app.isFavourite(s);
    return GestureDetector(
      onTap: () => _onSiteTap(s),
      child: Container(
        decoration: BoxDecoration(
          color: verdictColor(w?.worstVerdict ?? Verdict.noGo),
          shape: BoxShape.circle,
          border: Border.all(color: fav ? Colors.amber : Colors.white, width: fav ? 3 : 2),
        ),
        child: const Icon(Icons.paragliding, size: 14, color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([AppState.instance, Logbook.instance, AirspaceStore.instance, TaskStore.instance]),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    _ensureGrid();
    final grid = app.grid;
    final (lat, lon) = AppState.defaultMapCenter;
    final small = Theme.of(context).textTheme.bodySmall;

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: LatLng(lat, lon),
          initialZoom: 9.5,
          onLongPress: (_, p) => showPlaceEditor(context, p.latitude, p.longitude),
        ),
        children: [
          if (_tiles) TileLayer(urlTemplate: topoTiles, userAgentPackageName: 'com.nevbie.aeric', maxNativeZoom: 17),
          if (_tiles && showSkyways)
            Opacity(
              opacity: 0.75,
              child: TileLayer(urlTemplate: kk7Tiles(_kk7('skyways')), tms: true, maxNativeZoom: 12, userAgentPackageName: 'com.nevbie.aeric'),
            ),
          if (_tiles && showHotspots)
            Opacity(
              opacity: 0.8,
              child: TileLayer(urlTemplate: kk7Tiles(_kk7('thermals')), tms: true, maxNativeZoom: 12, userAgentPackageName: 'com.nevbie.aeric'),
            ),
          if (showAirspace && AirspaceStore.instance.airspaces.isNotEmpty)
            PolygonLayer(polygons: [
              for (final a in AirspaceStore.instance.airspaces)
                Polygon(
                  points: [for (final (la, lo) in a.polygon) LatLng(la, lo)],
                  color: airspaceColor(a.cls).withValues(alpha: 0.08),
                  borderColor: airspaceColor(a.cls),
                  borderStrokeWidth: 1.2,
                ),
            ]),
          if (showMine && Logbook.instance.entries.isNotEmpty)
            Builder(builder: (context) {
              final ref = matchToday ? _referenceCondition()?.$1 : null;
              final spots = conditionalHotspots(Logbook.instance.allThermals, reference: ref);
              return CircleLayer(circles: [
                for (final h in spots)
                  CircleMarker(
                    point: LatLng(h.lat, h.lon),
                    radius: 120.0 + 50.0 * (h.count - 1).clamp(0, 8),
                    useRadiusInMeter: true,
                    color: (h.matching.isEmpty ? Colors.grey : climbColor(h.avgClimbMs)).withValues(alpha: h.matching.isEmpty ? 0.2 : 0.5),
                    borderColor: h.matching.isEmpty ? Colors.grey : Colors.white,
                    borderStrokeWidth: 1.5,
                  ),
              ]);
            }),
          if (showThermals && grid != null)
            PolygonLayer(polygons: [
              for (final c in grid.cells)
                if (_value(c) case final v? when v.climbMs >= 0.3)
                  Polygon(
                    points: [for (final (a, b) in c.corners) LatLng(a, b)],
                    color: climbColor(v.climbMs).withValues(alpha: 0.45),
                  ),
            ]),
          if (TaskStore.instance.task case final task?) ...[
            CircleLayer(circles: [
              for (final tp in task.turnpoints)
                CircleMarker(
                  point: LatLng(tp.lat, tp.lon),
                  radius: tp.radiusM,
                  useRadiusInMeter: true,
                  color: const Color(0x1A7B1FA2),
                  borderColor: const Color(0xFF7B1FA2),
                  borderStrokeWidth: 2,
                ),
            ]),
            PolylineLayer(polylines: [
              Polyline(
                points: () {
                  final tps = task.turnpoints;
                  final from = tps.indexWhere((t) => t.type.name != 'takeoff');
                  final first = tps[from < 0 ? 0 : from];
                  final r = optimiseRoute(first.lat, first.lon, tps.sublist((from < 0 ? 0 : from) + 1),
                      goalLine: task.goalType == GoalType.line);
                  return [LatLng(first.lat, first.lon), for (final (a, b) in r.points) LatLng(a, b)];
                }(),
                color: const Color(0xFF7B1FA2),
                strokeWidth: 3,
              ),
            ]),
          ],
          MarkerLayer(markers: [
            for (final l in app.landings)
              Marker(
                point: LatLng(l.lat, l.lon),
                width: 22,
                height: 22,
                child: Tooltip(
                  message: '${l.name} · ${l.elevationM.round()} m',
                  child: const Icon(Icons.flag, size: 20, color: Color(0xFF1565C0)),
                ),
              ),
            for (final s in app.sites)
              Marker(point: LatLng(s.lat, s.lon), width: 26, height: 26, child: _siteMarker(s)),
          ]),
          if (_tiles)
            const SimpleAttributionWidget(
              source: Text('© OpenStreetMap contributors, SRTM · OpenTopoMap (CC-BY-SA)'),
              alignment: Alignment.topRight,
            ),
        ],
      ),
      // Top: day and layer toggles.
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(i == 0 ? 'Today' : i == 1 ? 'Tomorrow' : weekdays[day.add(Duration(days: i - dayOffset)).weekday - 1]),
                  selected: dayOffset == i,
                  onSelected: (_) => setState(() => dayOffset = i),
                ),
              ),
            FilterChip(
              avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
              label: const Text('Thermals'),
              tooltip: 'Forecast thermal strength (heatmap)',
              selected: showThermals,
              onSelected: (v) => setState(() => showThermals = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.whatshot, size: 16),
              label: const Text('Hotspots'),
              tooltip: 'Thermal hotspots from historical flights (thermal.kk7.ch)',
              selected: showHotspots,
              onSelected: (v) => setState(() => showHotspots = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.layers, size: 16),
              label: const Text('Airspace'),
              tooltip: AirspaceStore.instance.airspaces.isEmpty
                  ? 'Import an OpenAIR airspace file in Settings'
                  : '${AirspaceStore.instance.airspaces.length} airspaces',
              selected: showAirspace && AirspaceStore.instance.airspaces.isNotEmpty,
              onSelected: (v) => setState(() => showAirspace = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.person_pin_circle, size: 16),
              label: const Text('My thermals'),
              tooltip: 'Thermals from your logbook flights',
              selected: showMine,
              onSelected: (v) => setState(() => showMine = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.air, size: 16),
              label: const Text('Like today'),
              tooltip: 'Highlight thermals flown in weather like the forecast (wind, cloud)',
              selected: matchToday,
              onSelected: (v) => setState(() => matchToday = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.calendar_month, size: 16),
              label: const Text('Season & time'),
              tooltip: 'kk7 layers for this season and time of day instead of the whole year',
              selected: kk7Seasonal,
              onSelected: (v) => setState(() => kk7Seasonal = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              avatar: const Icon(Icons.timeline, size: 16),
              label: const Text('Skyways'),
              tooltip: 'Typical thermal lines from historical flights (thermal.kk7.ch)',
              selected: showSkyways,
              onSelected: (v) => setState(() => showSkyways = v),
            ),
          ]),
        ),
      ),
      // Bottom: hour slider, legend, reload.
      Positioned(
        left: 8,
        right: 8,
        bottom: 8,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    hour == 0 ? 'Best hour' : '${hour.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: hour.toDouble(),
                    min: 0,
                    max: 19,
                    divisions: 19,
                    onChanged: (v) => setState(() => hour = v < 8 ? 0 : v.round()),
                  ),
                ),
                if (app.gridLoading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.travel_explore),
                    tooltip: 'Load thermal map here',
                    onPressed: () {
                      final c = _map.camera.center;
                      app.loadGrid(c.latitude, c.longitude);
                    },
                  ),
              ]),
              Wrap(spacing: 8, runSpacing: 2, children: [
                for (final (label, climb) in [('weak', 0.5), ('moderate', 1.5), ('strong', 2.5), ('very strong', 3.5)])
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 12, height: 12, color: climbColor(climb).withValues(alpha: 0.8)),
                    const SizedBox(width: 3),
                    Text(label, style: const TextStyle(fontSize: 11)),
                  ]),
              ]),
              if (showMine && matchToday && Logbook.instance.entries.isNotEmpty)
                Builder(builder: (context) {
                  final ref = _referenceCondition();
                  final spots = conditionalHotspots(Logbook.instance.allThermals, reference: ref?.$1);
                  final n = spots.where((h) => h.matching.isNotEmpty).length;
                  return Text(
                    ref == null
                        ? 'My thermals: ${spots.length} spots (no forecast for comparison yet)'
                        : 'My thermals: $n of ${spots.length} spots were flown in weather like ${hhmm(_when)} '
                            '(wind ${ref.$1.windKmh.round()} km/h ${compass(ref.$1.windFromDeg)}'
                            '${ref.$1.cloudCover == null ? '' : ', ☁${ref.$1.cloudCover!.round()} %'}, ${ref.$2.name.split(' (').first})',
                    style: small?.copyWith(fontSize: 11),
                  );
                }),
              if (app.gridError case final e?) Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              Text(
                'Heatmap: estimated paraglider climb (aeric thermal model, Open-Meteo forecast). '
                '${showHotspots || showSkyways ? 'Hotspots/skyways: thermal.kk7.ch (XContest flights), non-commercial use. ' : ''}'
                'Markers: best window of the day, gold ring = favourite, blue flags = landings. Long-press to add your own takeoff or landing. 🔍 loads the heatmap for the visible area.',
                style: small?.copyWith(fontSize: 11),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
