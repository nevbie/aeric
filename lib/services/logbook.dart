import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/flight/flight_analysis.dart';
import '../core/flight/geo.dart';
import '../core/flight/igc.dart';
import '../core/flight/thermal_conditions.dart';
import '../core/weather_hour.dart';
import 'app_state.dart';

/// One flight in the logbook (the IGC file is stored next to the index).
class LogEntry {
  LogEntry({
    required this.id,
    required this.takeoff,
    required this.landing,
    required this.siteName,
    required this.lat,
    required this.lon,
    required this.maxAltM,
    required this.maxClimbMs,
    required this.trackKm,
    required this.maxFromTakeoffKm,
    required this.thermals,
    required this.source,
  });

  final String id;
  final DateTime takeoff;
  final DateTime landing;
  final String? siteName;
  final double lat;
  final double lon;
  final double maxAltM;
  final double maxClimbMs;
  final double trackKm;
  final double maxFromTakeoffKm;
  List<ConditionedThermal> thermals;

  /// 'recorded' or 'imported'.
  final String source;

  Duration get airtime => landing.difference(takeoff);
  bool get conditionsMissing => thermals.any((t) => t.condition == null);

  Map<String, dynamic> toJson() => {
        'id': id, 'takeoff': takeoff.toIso8601String(), 'landing': landing.toIso8601String(),
        'site': siteName, 'lat': lat, 'lon': lon, 'maxAlt': maxAltM, 'maxClimb': maxClimbMs,
        'trackKm': trackKm, 'maxFromKm': maxFromTakeoffKm, 'source': source,
        'thermals': [
          for (final t in thermals) {'spot': t.spot.toJson(), 'cond': t.condition?.toJson()},
        ],
      };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        id: j['id'] as String,
        takeoff: DateTime.parse(j['takeoff'] as String),
        landing: DateTime.parse(j['landing'] as String),
        siteName: j['site'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        maxAltM: (j['maxAlt'] as num).toDouble(),
        maxClimbMs: (j['maxClimb'] as num).toDouble(),
        trackKm: (j['trackKm'] as num).toDouble(),
        maxFromTakeoffKm: (j['maxFromKm'] as num).toDouble(),
        source: j['source'] as String? ?? 'imported',
        thermals: [
          for (final t in (j['thermals'] as List).cast<Map<String, dynamic>>())
            ConditionedThermal(
              ThermalSpot.fromJson(t['spot'] as Map<String, dynamic>),
              t['cond'] == null ? null : WeatherCondition.fromJson(t['cond'] as Map<String, dynamic>),
            ),
        ],
      );
}

/// Flight logbook: recorded and imported IGC files, their statistics and thermals, each thermal
/// tagged with the weather (ERA5) it was flown in.
class Logbook extends ChangeNotifier {
  Logbook({Future<Directory> Function()? dir}) : _dirFn = dir ?? _defaultDir;
  static final instance = Logbook();

  static Future<Directory> _defaultDir() async => Directory('${(await getApplicationDocumentsDirectory()).path}/logbook');

  final Future<Directory> Function() _dirFn;
  final List<LogEntry> entries = [];
  bool loaded = false;
  bool busy = false;
  String? message;

  Future<Directory> get _dir async => (await _dirFn())..createSync(recursive: true);

  Future<void> load() async {
    if (loaded) return;
    try {
      final f = File('${(await _dir).path}/index.json');
      if (f.existsSync()) {
        entries
          ..clear()
          ..addAll((jsonDecode(await f.readAsString()) as List).cast<Map<String, dynamic>>().map(LogEntry.fromJson));
      }
    } catch (e) {
      debugPrint('logbook: $e');
    }
    loaded = true;
    notifyListeners();
    fillMissingConditions();
  }

  Future<void> _save() async {
    entries.sort((a, b) => b.takeoff.compareTo(a.takeoff));
    await File('${(await _dir).path}/index.json').writeAsString(jsonEncode([for (final e in entries) e.toJson()]));
  }

  Future<String> igcPath(LogEntry e) async => '${(await _dir).path}/${e.id}.igc';

  Future<String?> readIgc(LogEntry e) async {
    final f = File(await igcPath(e));
    return f.existsSync() ? f.readAsString() : null;
  }

  /// All thermals of all flights (for the map).
  Iterable<ConditionedThermal> get allThermals => entries.expand((e) => e.thermals);

  /// Adds a flight from IGC text. Returns the entry, or null when the file contains no flight
  /// or is already in the logbook.
  Future<LogEntry?> addIgc(String text, {required String source}) async {
    await load();
    final igc = parseIgc(text);
    final stats = const FlightAnalyzer().analyze(igc.fixes);
    if (stats == null) return null;
    final t = stats.takeoff.time;
    final id = '${t.year}${_pad2(t.month)}${_pad2(t.day)}-${_pad2(t.hour)}${_pad2(t.minute)}${_pad2(t.second)}';
    if (entries.any((e) => e.id == id)) return null;

    String? site;
    var best = 3000.0;
    for (final s in AppState.instance.sites) {
      final d = distanceM(s.lat, s.lon, stats.takeoff.lat, stats.takeoff.lon);
      if (d < best) {
        best = d;
        site = s.name;
      }
    }
    final entry = LogEntry(
      id: id,
      takeoff: t,
      landing: stats.landing.time,
      siteName: site,
      lat: stats.takeoff.lat,
      lon: stats.takeoff.lon,
      maxAltM: stats.maxAltM,
      maxClimbMs: stats.maxClimbMs,
      trackKm: stats.trackKm,
      maxFromTakeoffKm: stats.maxFromTakeoffKm,
      thermals: [for (final s in stats.thermals) ConditionedThermal(s, null)],
      source: source,
    );
    await File(await igcPath(entry)).writeAsString(text);
    entries.add(entry);
    await _save();
    notifyListeners();
    await _tagConditions(entry);
    return entry;
  }

  /// Tags each thermal of [e] with the weather of its hour (ERA5 archive, or the forecast API's
  /// stored runs for the last days). Fails quietly offline; retried on next start.
  Future<void> _tagConditions(LogEntry e) async {
    if (!e.conditionsMissing) return;
    try {
      final hours = await AppState.instance.history.day(e.lat, e.lon, e.takeoff, today: DateTime.now());
      e.thermals = [
        for (final t in e.thermals)
          ConditionedThermal(t.spot, t.condition ?? _cond(weatherAt(hours, t.spot.start))),
      ];
      await _save();
      notifyListeners();
    } catch (err) {
      debugPrint('conditions for ${e.id}: $err');
    }
  }

  static WeatherCondition? _cond(WeatherHour? h) => h == null ? null : WeatherCondition.of(h);

  Future<void> fillMissingConditions() async {
    for (final e in [...entries]) {
      await _tagConditions(e);
    }
  }

  /// Imports .igc files and .zip archives of them (e.g. the XContest "Download: IGC" ZIP of your flights).
  Future<void> importFiles(List<(String, Uint8List)> files) async {
    busy = true;
    message = null;
    notifyListeners();
    var added = 0, skipped = 0;
    Future<void> one(String name, List<int> bytes) async {
      if (!name.toLowerCase().endsWith('.igc')) return;
      final e = await addIgc(utf8.decode(bytes, allowMalformed: true), source: 'imported');
      e == null ? skipped++ : added++;
    }

    for (final (name, bytes) in files) {
      try {
        if (name.toLowerCase().endsWith('.zip')) {
          for (final f in ZipDecoder().decodeBytes(bytes)) {
            if (f.isFile) await one(f.name, f.content);
          }
        } else {
          await one(name, bytes);
        }
      } catch (e) {
        skipped++;
        debugPrint('import $name: $e');
      }
    }
    busy = false;
    message = 'Imported $added flight${added == 1 ? '' : 's'}${skipped > 0 ? ', skipped $skipped (duplicate or no flight)' : ''}.';
    notifyListeners();
  }

  Future<void> delete(LogEntry e) async {
    entries.remove(e);
    final f = File(await igcPath(e));
    if (f.existsSync()) await f.delete();
    await _save();
    notifyListeners();
  }
}

String _pad2(int v) => v.toString().padLeft(2, '0');
