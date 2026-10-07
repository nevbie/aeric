import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/flight/fix.dart';
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

  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final dir = await _dir;
    final f = File('${dir.path}/index.json');
    if (f.existsSync()) {
      try {
        entries
          ..clear()
          ..addAll((jsonDecode(await f.readAsString()) as List).cast<Map<String, dynamic>>().map(LogEntry.fromJson));
      } catch (e) {
        // Never overwrite a damaged index: keep it aside and rebuild the list from the IGC files.
        debugPrint('logbook: damaged index ($e), rebuilding from IGC files');
        await f.rename('${dir.path}/index.corrupt-${DateTime.now().millisecondsSinceEpoch}.json');
        await _rebuild(dir);
      }
    }
    loaded = true;
    notifyListeners();
    await _recoverRecording();
    fillMissingConditions();
  }

  Future<void> _rebuild(Directory dir) async {
    entries.clear();
    for (final file in dir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.igc') || name == _recordingName) continue;
      try {
        final stats = const FlightAnalyzer().analyze(parseIgc(await file.readAsString()).fixes);
        if (stats != null) entries.add(_entryFrom(name.substring(0, name.length - 4), stats, 'imported'));
      } catch (e) {
        debugPrint('logbook: cannot read $name: $e');
      }
    }
    await _save();
  }

  /// Writes the index atomically (temp file + rename), so a crash never leaves half a file.
  Future<void> _save() async {
    entries.sort((a, b) => b.takeoff.compareTo(a.takeoff));
    final dir = await _dir;
    final tmp = File('${dir.path}/index.json.tmp');
    await tmp.writeAsString(jsonEncode([for (final e in entries) e.toJson()]), flush: true);
    await tmp.rename('${dir.path}/index.json');
  }

  /// Runs logbook changes one after another, so two saves of the same flight can't both pass
  /// the duplicate check.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() fn) {
    final result = _tail.then((_) => fn());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
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
    final entry = await _serial(() => _addIgc(text, source));
    if (entry != null) await _tagConditions(entry);
    return entry;
  }

  Future<LogEntry?> _addIgc(String text, String source) async {
    final stats = const FlightAnalyzer().analyze(parseIgc(text).fixes);
    if (stats == null) return null;
    final t = stats.takeoff.time;
    final id = '${t.year}${_pad2(t.month)}${_pad2(t.day)}-${_pad2(t.hour)}${_pad2(t.minute)}${_pad2(t.second)}';
    if (entries.any((e) => e.id == id)) return null;
    final entry = _entryFrom(id, stats, source);
    await File(await igcPath(entry)).writeAsString(text, flush: true);
    entries.add(entry);
    await _save();
    notifyListeners();
    return entry;
  }

  LogEntry _entryFrom(String id, FlightStats stats, String source) {
    String? site;
    var best = 3000.0;
    for (final s in AppState.instance.sites) {
      final d = distanceM(s.lat, s.lon, stats.takeoff.lat, stats.takeoff.lon);
      if (d < best) {
        best = d;
        site = s.name;
      }
    }
    return LogEntry(
      id: id,
      takeoff: stats.takeoff.time,
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
  }

  /// Saves a recording in which the analysis finds no flight (e.g. a hover-only soaring flight),
  /// so it is never thrown away. Kept as IGC in `logbook/unanalyzed/`.
  Future<File> saveUnanalyzed(String text) async {
    final dir = Directory('${(await _dir).path}/unanalyzed')..createSync(recursive: true);
    final f = File('${dir.path}/${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.igc');
    await f.writeAsString(text, flush: true);
    message = 'Recording saved without a detected flight: ${f.path}';
    notifyListeners();
    return f;
  }

  /// Saves a recorded flight: as a logbook entry, or as an unanalyzed IGC if no flight is found
  /// in it. Returns the entry, if any.
  Future<LogEntry?> saveRecording(String text) async {
    await load();
    final entry = await _saveRecordingLoaded(text);
    if (entry != null) await _tagConditions(entry);
    return entry;
  }

  Future<LogEntry?> _saveRecordingLoaded(String text) async {
    final entry = await _serial(() => _addIgc(text, 'recorded'));
    if (entry == null && !_isDuplicate(text)) await saveUnanalyzed(text);
    return entry;
  }

  bool _isDuplicate(String text) {
    final stats = const FlightAnalyzer().analyze(parseIgc(text).fixes);
    if (stats == null) return false;
    final t = stats.takeoff.time;
    final id = '${t.year}${_pad2(t.month)}${_pad2(t.day)}-${_pad2(t.hour)}${_pad2(t.minute)}${_pad2(t.second)}';
    return entries.any((e) => e.id == id);
  }

  // ------------------------------------------------------------------ crash recovery
  // While recording, every fix is appended to `recording.igc`. If the app is killed in flight,
  // the next start turns that file into a logbook entry.

  static const _recordingName = 'recording.igc';
  RandomAccessFile? _rec;
  final _recBuffer = StringBuffer();
  DateTime? _recFlushedAt;
  bool _recWanted = false;

  /// Starts a new recovery file (after recovering a leftover one from a crash).
  Future<void> startRecording({String pilot = '', String glider = ''}) async {
    _recWanted = true; // fixes arriving meanwhile are buffered
    await load();
    await _closeRecording();
    if (!_recWanted) return; // stopped while we were waiting
    final f = File('${(await _dir).path}/$_recordingName');
    _rec = f.openSync(mode: FileMode.write)..writeStringSync(igcHeader(DateTime.now(), pilot: pilot, glider: glider));
    _flushRecording();
  }

  /// Appends a fix; written to disk at least every 5 s.
  void appendFix(Fix f) {
    if (!_recWanted) return;
    _recBuffer.writeln(igcBRecord(f));
    final last = _recFlushedAt;
    if (last == null || f.time.difference(last).inSeconds.abs() >= 5) {
      _recFlushedAt = f.time;
      _flushRecording();
    }
  }

  void _flushRecording() {
    final r = _rec;
    if (r == null || _recBuffer.isEmpty) return;
    try {
      r
        ..writeStringSync(_recBuffer.toString())
        ..flushSync();
      _recBuffer.clear();
    } catch (e) {
      debugPrint('logbook: recovery write failed: $e');
    }
  }

  /// The flight was saved normally: the recovery file is no longer needed.
  Future<void> finishRecording() async {
    _recWanted = false;
    _recBuffer.clear();
    await _closeRecording();
    final f = File('${(await _dir).path}/$_recordingName');
    if (f.existsSync()) await f.delete();
  }

  Future<void> _closeRecording() async {
    final r = _rec;
    _rec = null;
    _recFlushedAt = null;
    if (r != null) await r.close();
  }

  /// Turns a recovery file left by a crash into a logbook entry. Runs once, while loading.
  Future<void> _recoverRecording() async {
    if (_rec != null) return; // the file belongs to the flight in progress
    final f = File('${(await _dir).path}/$_recordingName');
    if (!f.existsSync()) return;
    try {
      final igc = parseIgc(await f.readAsString());
      if (igc.fixes.length > 30) {
        await _saveRecordingLoaded(writeIgc(igc.fixes, pilot: igc.pilot ?? '', glider: igc.glider ?? ''));
      }
      await f.delete();
    } catch (e) {
      debugPrint('logbook: recovery failed: $e');
    }
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
