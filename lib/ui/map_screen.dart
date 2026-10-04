import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/day_planner.dart';
import '../core/flyability.dart';
import '../core/site.dart';
import '../core/thermal_grid.dart';
import '../core/thermal_model.dart';
import '../services/app_state.dart';
import 'common.dart';

/// Topographic base map with relief; fine for personal use, attribution required.
const topoTiles = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';

/// Historical thermal maps from thermal.kk7.ch, computed from XContest flights (non-commercial use).
String kk7Tiles(String layer) => 'https://thermal.kk7.ch/tiles/${layer}_all_all/{z}/{x}/{y}.png?src=aeric';

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
  bool _requested = false;

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
  Widget build(BuildContext context) {
    _ensureGrid();
    final grid = app.grid;
    final (lat, lon) = AppState.defaultMapCenter;
    final small = Theme.of(context).textTheme.bodySmall;

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(initialCenter: LatLng(lat, lon), initialZoom: 9.5),
        children: [
          if (_tiles) TileLayer(urlTemplate: topoTiles, userAgentPackageName: 'com.nevbie.aeric', maxNativeZoom: 17),
          if (_tiles && showSkyways)
            Opacity(
              opacity: 0.75,
              child: TileLayer(urlTemplate: kk7Tiles('skyways'), tms: true, maxNativeZoom: 12, userAgentPackageName: 'com.nevbie.aeric'),
            ),
          if (_tiles && showHotspots)
            Opacity(
              opacity: 0.8,
              child: TileLayer(urlTemplate: kk7Tiles('thermals'), tms: true, maxNativeZoom: 12, userAgentPackageName: 'com.nevbie.aeric'),
            ),
          if (showThermals && grid != null)
            PolygonLayer(polygons: [
              for (final c in grid.cells)
                if (_value(c) case final v? when v.climbMs >= 0.3)
                  Polygon(
                    points: [for (final (a, b) in c.corners) LatLng(a, b)],
                    color: climbColor(v.climbMs).withValues(alpha: 0.45),
                  ),
            ]),
          MarkerLayer(markers: [
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
              if (app.gridError case final e?) Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              Text(
                'Heatmap: estimated paraglider climb (aeric thermal model, Open-Meteo forecast). '
                '${showHotspots || showSkyways ? 'Hotspots/skyways: thermal.kk7.ch (XContest flights), non-commercial use. ' : ''}'
                'Markers: best window of the day, gold ring = favourite. 🔍 loads the heatmap for the visible area.',
                style: small?.copyWith(fontSize: 11),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
