import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';

import '../flight/geo.dart';

enum TurnpointType { none, takeoff, sss, ess }

enum SssDirection { enter, exit }

enum GoalType { cylinder, line }

class Turnpoint {
  const Turnpoint({
    required this.name,
    required this.lat,
    required this.lon,
    required this.radiusM,
    this.altM = 0,
    this.description = '',
    this.type = TurnpointType.none,
  });

  final String name;
  final String description;
  final double lat;
  final double lon;
  final double altM;
  final double radiusM;
  final TurnpointType type;
}

/// A competition task (XCTrack "CLASSIC").
class Task {
  const Task({
    required this.turnpoints,
    this.sssDirection = SssDirection.exit,
    this.raceStart = true,
    this.timeGates = const [],
    this.goalType = GoalType.cylinder,
    this.deadline,
    this.takeoffOpen,
    this.takeoffClose,
  });

  final List<Turnpoint> turnpoints;
  final SssDirection sssDirection;

  /// RACE (start at the gate time) vs. ELAPSED-TIME (individual start).
  final bool raceStart;

  /// Start gates as UTC time of day.
  final List<Duration> timeGates;
  final GoalType goalType;
  final Duration? deadline;
  final Duration? takeoffOpen;
  final Duration? takeoffClose;

  int get sssIndex => turnpoints.indexWhere((t) => t.type == TurnpointType.sss);
  int get essIndex => turnpoints.indexWhere((t) => t.type == TurnpointType.ess);
  Turnpoint get goal => turnpoints.last;

  /// Nominal task distance along the optimised route from the first turnpoint.
  double get optimisedDistanceM {
    final tps = turnpoints.where((t) => t.type != TurnpointType.takeoff).toList();
    if (tps.length < 2) return 0;
    final route = optimiseRoute(tps.first.lat, tps.first.lon, tps.skip(1).toList(), goalLine: goalType == GoalType.line);
    return route.totalM;
  }

  Map<String, dynamic> toJson() => {
        'taskType': 'CLASSIC',
        'version': 1,
        'earthModel': 'WGS84',
        'turnpoints': [
          for (final t in turnpoints)
            {
              if (t.type != TurnpointType.none) 'type': t.type.name.toUpperCase(),
              'radius': t.radiusM.round(),
              'waypoint': {'name': t.name, 'description': t.description, 'lat': t.lat, 'lon': t.lon, 'altSmoothed': t.altM.round()},
            },
        ],
        if (takeoffOpen != null || takeoffClose != null)
          'takeoff': {
            if (takeoffOpen != null) 'timeOpen': _fmtTime(takeoffOpen!),
            if (takeoffClose != null) 'timeClose': _fmtTime(takeoffClose!),
          },
        'sss': {
          'type': raceStart ? 'RACE' : 'ELAPSED-TIME',
          'direction': sssDirection == SssDirection.enter ? 'ENTER' : 'EXIT',
          'timeGates': [for (final g in timeGates) _fmtTime(g)],
        },
        'goal': {'type': goalType == GoalType.line ? 'LINE' : 'CYLINDER', if (deadline != null) 'deadline': _fmtTime(deadline!)},
      };
}

String _fmtTime(Duration d) =>
    '${(d.inHours % 24).toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}Z';

Duration? _time(Object? v) {
  final m = RegExp(r'(\d\d):(\d\d):(\d\d)').firstMatch('${v ?? ''}');
  return m == null ? null : Duration(hours: int.parse(m.group(1)!), minutes: int.parse(m.group(2)!), seconds: int.parse(m.group(3)!));
}

/// Parses an XCTrack `.xctsk` file (version 1 JSON), or a QR code / text starting with
/// `XCTSK:` (version 2) or `XCTSKZ:` (zlib + base64).
Task parseTask(String text) {
  final t = text.trim();
  if (t.startsWith('XCTSKZ:')) {
    final bytes = const ZLibDecoder().decodeBytes(base64.decode(t.substring(7).trim()));
    return parseTask('XCTSK:${utf8.decode(bytes)}');
  }
  if (t.startsWith('XCTSK:')) return _parseV2(jsonDecode(t.substring(6)) as Map<String, dynamic>);
  final j = jsonDecode(t) as Map<String, dynamic>;
  if (j['version'] == 2 || j.containsKey('t')) return _parseV2(j);
  return _parseV1(j);
}

Task _parseV1(Map<String, dynamic> j) {
  final tps = <Turnpoint>[];
  for (final raw in (j['turnpoints'] as List).cast<Map<String, dynamic>>()) {
    final w = raw['waypoint'] as Map<String, dynamic>;
    tps.add(Turnpoint(
      name: '${w['name'] ?? ''}',
      description: '${w['description'] ?? ''}',
      lat: (w['lat'] as num).toDouble(),
      lon: (w['lon'] as num).toDouble(),
      altM: (w['altSmoothed'] as num?)?.toDouble() ?? 0,
      radiusM: (raw['radius'] as num?)?.toDouble() ?? 400,
      type: switch ('${raw['type'] ?? ''}'.toUpperCase()) {
        'TAKEOFF' => TurnpointType.takeoff,
        'SSS' => TurnpointType.sss,
        'ESS' => TurnpointType.ess,
        _ => TurnpointType.none,
      },
    ));
  }
  final sss = j['sss'] as Map<String, dynamic>?;
  final goal = j['goal'] as Map<String, dynamic>?;
  final takeoff = j['takeoff'] as Map<String, dynamic>?;
  return Task(
    turnpoints: tps,
    sssDirection: '${sss?['direction']}'.toUpperCase() == 'ENTER' ? SssDirection.enter : SssDirection.exit,
    raceStart: '${sss?['type'] ?? 'RACE'}'.toUpperCase() == 'RACE',
    timeGates: (sss?['timeGates'] as List? ?? const []).map(_time).whereType<Duration>().toList(),
    goalType: '${goal?['type']}'.toUpperCase() == 'LINE' ? GoalType.line : GoalType.cylinder,
    deadline: _time(goal?['deadline']),
    takeoffOpen: _time(takeoff?['timeOpen']),
    takeoffClose: _time(takeoff?['timeClose']),
  );
}

/// Google polyline integer decoding (each z field: lon·1e5, lat·1e5, alt, radius).
List<int> decodePolylineInts(String s) {
  final out = <int>[];
  var i = 0;
  while (i < s.length) {
    var result = 0, shift = 0, b = 0;
    do {
      b = s.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && i < s.length);
    out.add((result & 1) != 0 ? ~(result >> 1) : result >> 1);
  }
  return out;
}

String encodePolylineInts(List<int> values) {
  final sb = StringBuffer();
  for (final v in values) {
    var x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) {
      sb.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    sb.writeCharCode(x + 63);
  }
  return sb.toString();
}

Task _parseV2(Map<String, dynamic> j) {
  final tps = <Turnpoint>[];
  for (final raw in (j['t'] as List).cast<Map<String, dynamic>>()) {
    final z = decodePolylineInts('${raw['z']}');
    if (z.length < 4) continue;
    tps.add(Turnpoint(
      name: '${raw['n'] ?? ''}',
      description: '${raw['d'] ?? ''}',
      lon: z[0] / 1e5,
      lat: z[1] / 1e5,
      altM: z[2].toDouble(),
      radiusM: z[3].toDouble(),
      type: switch (raw['t']) {
        2 => TurnpointType.sss,
        3 => TurnpointType.ess,
        _ => TurnpointType.none,
      },
    ));
  }
  final s = j['s'] as Map<String, dynamic>?;
  final g = j['g'] as Map<String, dynamic>?;
  return Task(
    turnpoints: tps,
    sssDirection: s?['d'] == 1 ? SssDirection.enter : SssDirection.exit,
    raceStart: (s?['t'] ?? 1) == 1,
    timeGates: (s?['g'] as List? ?? const []).map(_time).whereType<Duration>().toList(),
    goalType: g?['t'] == 1 ? GoalType.line : GoalType.cylinder,
    deadline: _time(g?['d']),
    takeoffOpen: _time(j['to']),
    takeoffClose: _time(j['tc']),
  );
}

// ------------------------------------------------------------------ optimised route

class OptimisedRoute {
  const OptimisedRoute(this.points, this.legsM);

  /// Touch points on each cylinder (same order as the turnpoints passed in).
  final List<(double, double)> points;

  /// Length of each leg: start → first point, then point to point.
  final List<double> legsM;

  double get totalM => legsM.fold(0.0, (a, b) => a + b);
}

/// Shortest path from (lat, lon) that touches every cylinder in order. Iteratively moves each
/// touch point to the spot on its circle that minimises the distance to its neighbours.
/// For a goal line the last point is the line centre.
OptimisedRoute optimiseRoute(double lat, double lon, List<Turnpoint> tps, {bool goalLine = false}) {
  if (tps.isEmpty) return const OptimisedRoute([], []);
  // Local metric projection around the start.
  final kx = 111320 * math.cos(lat * math.pi / 180), ky = 110540.0;
  (double, double) toXY(double la, double lo) => ((lo - lon) * kx, (la - lat) * ky);
  (double, double) toLL(double x, double y) => (lat + y / ky, lon + x / kx);
  double dist((double, double) a, (double, double) b) => math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  final centres = [for (final t in tps) toXY(t.lat, t.lon)];
  final radii = [for (final t in tps) t.radiusM];
  final pts = [...centres];
  const start = (0.0, 0.0);

  (double, double) best((double, double) c, double r, (double, double) prev, (double, double)? next) {
    if (r <= 0) return c;
    if (next == null) {
      // Last cylinder: closest point to the previous one.
      final d = dist(prev, c);
      return d <= r ? prev : (c.$1 + (prev.$1 - c.$1) / d * r, c.$2 + (prev.$2 - c.$2) / d * r);
    }
    // If the straight line prev→next crosses the cylinder, the cheapest touch is on that line.
    final dx = next.$1 - prev.$1, dy = next.$2 - prev.$2;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((c.$1 - prev.$1) * dx + (c.$2 - prev.$2) * dy) / len2).clamp(0.0, 1.0);
    final closest = (prev.$1 + t * dx, prev.$2 + t * dy);
    if (dist(closest, c) <= r) return closest;
    double cost(double a) {
      final p = (c.$1 + r * math.cos(a), c.$2 + r * math.sin(a));
      return dist(prev, p) + dist(p, next);
    }

    // Coarse search, then golden-section refinement around the best angle.
    var bestA = 0.0, bestCost = double.infinity;
    for (var i = 0; i < 72; i++) {
      final a = i * math.pi / 36;
      final cst = cost(a);
      if (cst < bestCost) {
        bestCost = cst;
        bestA = a;
      }
    }
    var lo = bestA - math.pi / 36, hi = bestA + math.pi / 36;
    const g = 0.6180339887;
    for (var i = 0; i < 40; i++) {
      final a1 = hi - g * (hi - lo), a2 = lo + g * (hi - lo);
      if (cost(a1) < cost(a2)) {
        hi = a2;
      } else {
        lo = a1;
      }
    }
    final a = (lo + hi) / 2;
    return (c.$1 + r * math.cos(a), c.$2 + r * math.sin(a));
  }

  for (var pass = 0; pass < 20; pass++) {
    var moved = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final prev = i == 0 ? start : pts[i - 1];
      final isLast = i == pts.length - 1;
      final next = isLast ? null : pts[i + 1];
      final p = isLast && goalLine ? centres[i] : best(centres[i], radii[i], prev, next);
      moved = math.max(moved, dist(p, pts[i]));
      pts[i] = p;
    }
    if (moved < 0.5) break;
  }
  // Touch points come from the flat projection; leg lengths use great-circle distance.
  final latLon = [for (final p in pts) toLL(p.$1, p.$2)];
  final legs = <double>[];
  var prev = (lat, lon);
  for (final p in latLon) {
    legs.add(distanceM(prev.$1, prev.$2, p.$1, p.$2));
    prev = p;
  }
  return OptimisedRoute(latLon, legs);
}

// ------------------------------------------------------------------ progress

enum TaskStage { beforeStart, racing, essReached, goal }

/// Follows a pilot through a task: start (enter/exit the SSS after a gate), tagging each
/// turnpoint cylinder, ESS and goal.
class TaskProgress {
  TaskProgress(this.task) : next = _firstIndex(task);

  final Task task;

  /// Index of the next turnpoint to reach.
  int next;
  TaskStage stage = TaskStage.beforeStart;
  DateTime? startTime;
  DateTime? essTime;
  bool? _insideSss;

  static int _firstIndex(Task t) {
    final i = t.turnpoints.indexWhere((tp) => tp.type != TurnpointType.takeoff);
    return i < 0 ? 0 : i;
  }

  Turnpoint? get nextTurnpoint => next < task.turnpoints.length ? task.turnpoints[next] : null;

  /// Next start gate after [utc] (UTC time of day), or null when none / already started.
  Duration? nextGate(DateTime utc) {
    final tod = Duration(hours: utc.hour, minutes: utc.minute, seconds: utc.second);
    for (final g in task.timeGates) {
      if (g > tod) return g - tod;
    }
    return null;
  }

  bool _gateOpen(DateTime utc) {
    if (task.timeGates.isEmpty) return true;
    final tod = Duration(hours: utc.hour, minutes: utc.minute, seconds: utc.second);
    return tod >= task.timeGates.first;
  }

  /// Updates with a new position; returns the turnpoint just reached (for a callout), if any.
  Turnpoint? update(DateTime utc, double lat, double lon) {
    final tp = nextTurnpoint;
    if (tp == null) return null;
    final inside = distanceM(lat, lon, tp.lat, tp.lon) <= tp.radiusM;
    if (tp.type == TurnpointType.sss) {
      final was = _insideSss;
      _insideSss = inside;
      final crossed = was != null &&
          (task.sssDirection == SssDirection.exit ? (was && !inside) : (!was && inside));
      if (!crossed || !_gateOpen(utc)) return null;
      startTime = task.raceStart && task.timeGates.isNotEmpty ? _lastGateBefore(utc) : utc;
      stage = TaskStage.racing;
      next++;
      return tp;
    }
    if (!inside) return null;
    if (tp.type == TurnpointType.ess) {
      essTime = utc;
      stage = TaskStage.essReached;
    }
    next++;
    if (next >= task.turnpoints.length) stage = TaskStage.goal;
    return tp;
  }

  DateTime _lastGateBefore(DateTime utc) {
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    final tod = utc.difference(day);
    final g = task.timeGates.where((g) => g <= tod).toList();
    return day.add(g.isEmpty ? tod : g.last);
  }

  Duration? get speedSectionTime => startTime == null || essTime == null ? null : essTime!.difference(startTime!);

  /// Optimised route from the pilot through the remaining turnpoints.
  OptimisedRoute remainingRoute(double lat, double lon) => optimiseRoute(
        lat,
        lon,
        task.turnpoints.sublist(math.min(next, task.turnpoints.length)),
        goalLine: task.goalType == GoalType.line,
      );
}
