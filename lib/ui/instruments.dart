import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/flight/geo.dart';
import '../core/geo.dart';
import '../services/flight_controller.dart';
import '../services/settings.dart';
import '../services/task_store.dart';
import 'common.dart';

/// Everything that can be put on an instrument page.
enum Instrument {
  altitude('Altitude'),
  agl('Above ground'),
  groundSpeed('Ground speed'),
  track('Track'),
  wind('Wind'),
  glide('Glide L/D'),
  landing('Landing'),
  neededLd('Needed L/D'),
  arrival('Arrival'),
  avg30('Average 30 s'),
  thermalAvg('Thermal average'),
  thermalGain('Thermal gain'),
  flightTime('Flight time'),
  taskNext('Task: next'),
  taskGoal('Task: goal'),
  airspace('Airspace'),
  maxAlt('Max altitude');

  const Instrument(this.label);
  final String label;

  static Instrument? byName(String n) => Instrument.values.where((i) => i.name == n).firstOrNull;
}

/// One page of tiles.
class InstrumentPage {
  InstrumentPage(this.name, this.tiles);
  String name;
  List<Instrument> tiles;

  Map<String, dynamic> toJson() => {'name': name, 'tiles': [for (final t in tiles) t.name]};
  factory InstrumentPage.fromJson(Map<String, dynamic> j) => InstrumentPage(
        '${j['name'] ?? 'Page'}',
        (j['tiles'] as List? ?? const []).cast<String>().map(Instrument.byName).whereType<Instrument>().toList(),
      );
}

List<InstrumentPage> defaultPages() => [
      InstrumentPage('Basic', [
        Instrument.altitude, Instrument.agl, Instrument.groundSpeed, Instrument.track, Instrument.wind,
        Instrument.glide, Instrument.landing, Instrument.neededLd, Instrument.arrival,
      ]),
      InstrumentPage('XC', [
        Instrument.thermalAvg, Instrument.thermalGain, Instrument.avg30, Instrument.wind, Instrument.glide,
        Instrument.altitude, Instrument.taskNext, Instrument.taskGoal, Instrument.flightTime,
      ]),
      InstrumentPage('Safety', [
        Instrument.airspace, Instrument.agl, Instrument.landing, Instrument.arrival, Instrument.neededLd,
        Instrument.maxAlt,
      ]),
    ];

String encodePages(List<InstrumentPage> pages) => jsonEncode([for (final p in pages) p.toJson()]);

List<InstrumentPage> decodePages(String? json) {
  if (json == null) return defaultPages();
  try {
    final pages = (jsonDecode(json) as List).cast<Map<String, dynamic>>().map(InstrumentPage.fromJson).toList();
    return pages.isEmpty ? defaultPages() : pages;
  } catch (_) {
    return defaultPages();
  }
}

/// Value, unit and colour of an instrument for the current flight state.
(String, String, Color?) instrumentValue(Instrument i, FlightController fc) {
  final f = fc.fix;
  final fg = fc.finalGlideToLanding;
  String n(double? v, [int d = 0]) => v == null ? '–' : v.toStringAsFixed(d);
  Color? reach(bool ok) => ok ? goColor : noGoColor;
  switch (i) {
    case Instrument.altitude:
      return (n(f?.altM), 'm${fc.hasBarometer ? ' baro' : ' GPS'}', null);
    case Instrument.agl:
      return (n(fc.aglM), 'm AGL', null);
    case Instrument.groundSpeed:
      return (f == null ? '–' : n(fc.groundSpeedKmh), 'km/h', null);
    case Instrument.track:
      return (fc.trackDeg == null ? '–' : '${fc.trackDeg!.round()}°', fc.trackDeg == null ? '' : compass(fc.trackDeg!), null);
    case Instrument.wind:
      final w = fc.wind;
      return (w == null ? '–' : n(w.speedKmh), w == null ? 'circle once' : 'km/h from ${compass(w.fromDeg)}', null);
    case Instrument.glide:
      return (n(fc.glideRatio, 1), 'L/D last 30 s', null);
    case Instrument.landing:
      return (
        fg == null ? '–' : '${fg.distanceKm.toStringAsFixed(1)} km',
        fc.landing == null || fg == null ? 'none within 40 km' : '${fc.landing!.name} · ${compass(fg.bearingDeg)}',
        null
      );
    case Instrument.neededLd:
      return (n(fg?.requiredGlideRatio, 1), 'incl. ${Settings.instance.safetyMarginM.round()} m margin', fg == null ? null : reach(fg.reachable));
    case Instrument.arrival:
      return (
        fg == null || fg.arrivalHeightM.isInfinite ? '–' : '${fg.arrivalHeightM.round()}',
        'm above margin',
        fg == null ? null : reach(fg.reachable)
      );
    case Instrument.avg30:
      return (n(fc.avg30Ms, 1), 'm/s', null);
    case Instrument.thermalAvg:
      return (n(fc.thermalAvgMs, 1), 'm/s in thermal', null);
    case Instrument.thermalGain:
      return (fc.thermalGainM == null ? '–' : '+${fc.thermalGainM!.round()}', 'm this thermal', null);
    case Instrument.flightTime:
      final t = fc.takeoffTime;
      if (t == null || f == null) return ('–', 'not flying', null);
      final d = f.time.difference(t);
      return ('${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}', 'h:min', null);
    case Instrument.taskNext:
      final p = TaskStore.instance.progress;
      final r = fc.taskRoute;
      if (p?.nextTurnpoint == null || r == null || r.legsM.isEmpty || f == null) return ('–', p == null ? 'no task' : 'next', null);
      final touch = r.points.first;
      return ('${(r.legsM.first / 1000).toStringAsFixed(1)} km', '${p!.nextTurnpoint!.name} · ${compass(bearingDeg(f.lat, f.lon, touch.$1, touch.$2))}', null);
    case Instrument.taskGoal:
      final r = fc.taskRoute;
      return (r == null ? '–' : '${(r.totalM / 1000).toStringAsFixed(1)} km', fc.taskRequiredGlide == null ? 'to goal' : 'L/D ${n(fc.taskRequiredGlide, 1)}', null);
    case Instrument.airspace:
      final w = fc.airspaceWarnings.firstOrNull;
      if (w == null) return ('clear', 'airspace', goColor);
      return (w.horizontalM == 0 ? 'IN' : '${w.horizontalM.round()} m', '${w.airspace.cls} ${w.airspace.name}', noGoColor);
    case Instrument.maxAlt:
      final alts = fc.track.map((x) => x.altM);
      return (alts.isEmpty ? '–' : '${alts.reduce(math.max).round()}', 'm max', null);
  }
}

class InstrumentTile extends StatelessWidget {
  const InstrumentTile(this.instrument, this.fc, {super.key, this.editing = false, this.onTap});
  final Instrument instrument;
  final FlightController fc;
  final bool editing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (value, unit, color) = instrumentValue(instrument, fc);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: editing ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(instrument.label, style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (editing) const Icon(Icons.edit, size: 14),
          ]),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (instrument == Instrument.wind && fc.wind != null)
                  Transform.rotate(angle: (fc.wind!.fromDeg + 180) * math.pi / 180, child: const Icon(Icons.navigation, size: 22)),
                Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
              ]),
            ),
          ),
          Text(unit, style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
