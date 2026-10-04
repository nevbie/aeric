import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/airspace.dart';
import '../core/elevation.dart';
import '../core/flight/fix.dart';
import '../core/flight/flight_analysis.dart';
import '../core/flight/geo.dart';
import '../core/flight/glide.dart';
import '../core/flight/igc.dart';
import '../core/flight/thermal_assistant.dart';
import '../core/flight/vario.dart';
import '../core/flight/wind.dart';
import '../core/landing.dart';
import '../core/task/task.dart';
import '../core/devices/vario_protocols.dart';
import 'airspace_store.dart';
import 'app_state.dart';
import 'ble_vario.dart';
import 'logbook.dart';
import 'settings.dart';
import 'task_store.dart';
import 'vario_audio.dart';

enum FlightMode { idle, live, replay }

/// Everything the instrument screen shows, fed by GPS + barometer (live) or an IGC file (replay).
class FlightController extends ChangeNotifier {
  FlightController._();
  static final instance = FlightController._();

  final audio = VarioAudio();
  late final _tts = FlutterTts(); // lazy: only created when something is spoken
  bool get voice => Settings.instance.voice;

  FlightMode mode = FlightMode.idle;
  String? error;

  // Live values.
  Fix? fix;
  double groundSpeedKmh = 0;
  double? trackDeg;
  double varioMs = 0;
  double? avg30Ms;
  double? baroAltM;
  double? terrainM;
  WindEstimate? wind;
  double? glideRatio;
  FinalGlide? finalGlideToLanding;
  LandingField? landing;
  bool hasBarometer = false;
  bool flying = false;
  DateTime? takeoffTime;

  /// Airspaces we are in, about to enter or close to (most urgent first).
  List<AirspaceWarning> airspaceWarnings = const [];
  final _announced = <String, DateTime>{};
  static const _airspaceChecker = AirspaceChecker();

  /// Competition task navigation (when a task is loaded).
  OptimisedRoute? taskRoute;
  double? taskRequiredGlide;

  /// Thermal centering aid while circling.
  final _assistant = ThermalAssistant();
  ThermalAssist? assist;
  bool circling = false;

  /// Climb since circling started (thermal average) and its gain.
  double? thermalAvgMs;
  double? thermalGainM;

  double? get aglM => fix == null || terrainM == null ? null : fix!.altM - terrainM!;

  /// Recorded fixes of the current flight (1 Hz).
  final List<Fix> track = [];

  final _kalman = KalmanVario();

  /// GPS altitude is far noisier (±3–5 m) than a barometer, so the fallback filters harder.
  final _gpsKalman = KalmanVario(accelNoise: 0.4, altNoiseM: 4);
  final _avg = TimeAverage(const Duration(seconds: 30));
  double? _qnh;
  final List<(DateTime, double)> _qnhSamples = [];
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<BarometerEvent>? _baroSub;
  StreamSubscription<VarioSample>? _bleSub;
  DateTime? _lastExternalPressure;
  DateTime? _lastPhoneFix;

  /// Where the vario comes from: Bluetooth device, phone barometer or GPS.
  String get varioSource {
    final ble = BleVario.instance;
    if (_lastExternalPressure != null && ble.connected) return ble.deviceName ?? 'Bluetooth vario';
    return hasBarometer ? 'phone barometer' : 'GPS altitude';
  }
  Timer? _replayTimer;
  DateTime? _lastElevationAt;
  DateTime? _groundSince;
  int _circlingFixes = 0;
  Fix? _thermalStart;

  ElevationClient get _elevation => AppState.instance.elevation;

  void toggleMute() {
    audio.muted = !audio.muted;
    notifyListeners();
  }

  void toggleVoice() {
    Settings.instance.update((s) => s.voice = !s.voice);
    notifyListeners();
  }

  // ------------------------------------------------------------------ live
  Future<void> startLive() async {
    if (mode != FlightMode.idle) return;
    error = null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw 'Location services are off';
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw 'Location permission denied';
    } catch (e) {
      error = '$e';
      notifyListeners();
      return;
    }
    reset();
    mode = FlightMode.live;
    notifyListeners();
    WakelockPlus.enable().ignore();

    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'aeric is recording your flight',
              notificationText: 'Vario and GPS keep running with the screen off.',
              enableWakeLock: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.airborne,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );
    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        _lastPhoneFix = DateTime.now().toUtc();
        onPosition(
          Fix(time: _lastPhoneFix!, lat: p.latitude, lon: p.longitude, gpsAltM: p.altitude, baroAltM: baroAltM),
          speedKmh: p.speed >= 0 ? p.speed * 3.6 : null,
        );
      },
      onError: (Object e) {
        error = 'GPS: $e';
        notifyListeners();
      },
    );
    _baroSub = barometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
      (e) => onPressure(DateTime.now().toUtc(), e.pressure),
      onError: (Object _) => hasBarometer = false, // fall back to a GPS-altitude vario
      cancelOnError: true,
    );
    _bleSub = BleVario.instance.samples.listen(onExternal);
    BleVario.instance.reconnect().ignore();
    _applyAudioSettings();
    await audio.start(() => varioMs);
  }

  /// A reading from a Bluetooth vario: its pressure replaces the phone barometer; its GPS is
  /// used when the phone has no fix.
  void onExternal(VarioSample s, {DateTime? at}) {
    final now = at ?? DateTime.now().toUtc();
    if (s.pressureHpa != null) {
      onPressure(now, s.pressureHpa!, external: true);
    } else if (s.baroAltM != null) {
      onPressure(now, 1013.25 * math.pow(1 - s.baroAltM! / 44330.77, 1 / 0.190263), external: true);
    }
    final phoneStale = _lastPhoneFix == null || now.difference(_lastPhoneFix!).inSeconds > 3;
    if (s.hasPosition && phoneStale) {
      onPosition(Fix(time: now, lat: s.lat!, lon: s.lon!, gpsAltM: s.gpsAltM ?? fix?.gpsAltM ?? 0, baroAltM: baroAltM),
          speedKmh: s.groundSpeedKmh);
    }
  }

  void _applyAudioSettings() {
    audio.mapper = Settings.instance.toneMapper;
    audio.volume = Settings.instance.volume;
  }

  Future<void> stop() async {
    await _gpsSub?.cancel();
    await _baroSub?.cancel();
    await _bleSub?.cancel();
    _bleSub = null;
    _gpsSub = null;
    _baroSub = null;
    _replayTimer?.cancel();
    _replayTimer = null;
    await audio.stop();
    WakelockPlus.disable().ignore();
    final wasLive = mode == FlightMode.live;
    mode = FlightMode.idle;
    notifyListeners();
    if (wasLive && track.length > 30) {
      final st = Settings.instance;
      await Logbook.instance.addIgc(writeIgc(track, pilot: st.pilot, glider: st.glider), source: 'recorded');
    }
  }

  // ------------------------------------------------------------------ replay
  /// Plays an IGC file through the same pipeline (vario, wind, glide, sound) at [speed]x.
  Future<void> startReplay(IgcFlight flight, {int speed = 10}) async {
    if (mode != FlightMode.idle || flight.fixes.isEmpty) return;
    reset();
    mode = FlightMode.replay;
    notifyListeners();
    _applyAudioSettings();
    await audio.start(() => varioMs);
    var i = 0;
    final fixes = flight.fixes;
    final start = DateTime.now();
    final t0 = fixes.first.time;
    _replayTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final simNow = t0.add(DateTime.now().difference(start) * speed);
      while (i < fixes.length && !fixes[i].time.isAfter(simNow)) {
        final f = fixes[i];
        // Feed the altitude as pressure so the barometer path is exercised too.
        onPressure(f.time, 1013.25 * math.pow(1 - f.altM / 44330.77, 1 / 0.190263));
        onPosition(f);
        i++;
      }
      if (i >= fixes.length) stop();
    });
  }

  // ------------------------------------------------------------------ pipeline
  void reset() {
    _kalman.reset();
    _gpsKalman.reset();
    _avg.clear();
    _qnh = null;
    _qnhSamples.clear();
    track.clear();
    fix = null;
    wind = null;
    glideRatio = null;
    finalGlideToLanding = null;
    landing = null;
    terrainM = null;
    varioMs = 0;
    avg30Ms = null;
    flying = false;
    takeoffTime = null;
    hasBarometer = false;
    _groundSince = null;
    _circlingFixes = 0;
    _thermalStart = null;
    thermalAvgMs = null;
    thermalGainM = null;
    airspaceWarnings = const [];
    _announced.clear();
    _assistant.clear();
    assist = null;
    taskRoute = null;
    taskRequiredGlide = null;
    circling = false;
    _lastExternalPressure = null;
    _lastPhoneFix = null;
  }

  /// Barometer sample. Altitude is calibrated (QNH) against the first GPS fixes.
  void onPressure(DateTime t, double hPa, {bool external = false}) {
    // A connected Bluetooth vario wins over the phone's barometer.
    if (external) {
      _lastExternalPressure = t;
    } else if (_lastExternalPressure != null && t.difference(_lastExternalPressure!).inSeconds.abs() < 3) {
      return;
    }
    hasBarometer = true;
    if (_qnh == null) {
      _qnhSamples.add((t, hPa));
      return;
    }
    baroAltM = pressureToAltitudeM(hPa, qnhHpa: _qnh!);
    varioMs = _kalman.update(t, baroAltM!);
  }

  void onPosition(Fix raw, {double? speedKmh}) {
    // Calibrate the barometer once GPS altitude has settled (10 fixes), or right away in replay.
    if (_qnh == null && hasBarometer && _qnhSamples.isNotEmpty && (track.length >= 10 || mode == FlightMode.replay)) {
      final p = _qnhSamples.last.$2;
      _qnh = mode == FlightMode.replay ? 1013.25 : (Settings.instance.qnhHpa ?? qnhFor(p, _calibrationAltitude(raw)));
      _qnhSamples.clear();
    }
    final f = Fix(time: raw.time, lat: raw.lat, lon: raw.lon, gpsAltM: raw.gpsAltM, baroAltM: hasBarometer ? baroAltM : null);
    final prev = fix;
    fix = f;
    if (!hasBarometer) varioMs = _gpsKalman.update(f.time, f.gpsAltM); // GPS-only fallback
    _avg.add(f.time, varioMs);
    avg30Ms = _avg.value;
    if (prev != null) {
      groundSpeedKmh = speedKmh ?? FlightAnalyzer.speedKmh(prev, f);
      if (distanceM(prev.lat, prev.lon, f.lat, f.lon) > 1) trackDeg = bearingDeg(prev.lat, prev.lon, f.lat, f.lon);
    }
    if (track.isEmpty || f.time.difference(track.last.time).inMilliseconds >= 900) track.add(f);

    _updateFlying(f);
    _updateThermal(f);
    _updateWindAndGlide(f);
    _updateTerrain(f);
    _updateAirspace(f);
    _updateTask(f);
    notifyListeners();
  }

  void _updateTask(Fix f) {
    final progress = TaskStore.instance.progress;
    if (progress == null) {
      taskRoute = null;
      taskRequiredGlide = null;
      return;
    }
    final reached = progress.update(f.time, f.lat, f.lon);
    if (reached != null) {
      _say(switch (progress.stage) {
        TaskStage.racing when reached.type == TurnpointType.sss => 'Start. Go!',
        TaskStage.essReached when reached.type == TurnpointType.ess => 'End of speed section',
        TaskStage.goal => 'Goal!',
        _ => 'Turnpoint ${reached.name} reached',
      });
      TaskStore.instance.changed();
    }
    taskRoute = progress.nextTurnpoint == null ? null : progress.remainingRoute(f.lat, f.lon);
    final goal = progress.task.goal;
    final above = f.altM - goal.altM - Settings.instance.safetyMarginM;
    taskRequiredGlide = taskRoute == null || above <= 0 ? null : taskRoute!.totalM / above;
  }

  void _updateAirspace(Fix f) {
    final spaces = AirspaceStore.instance.airspaces;
    if (spaces.isEmpty) {
      airspaceWarnings = const [];
      return;
    }
    airspaceWarnings = _airspaceChecker.check(
      spaces,
      lat: f.lat,
      lon: f.lon,
      altM: f.altM,
      groundM: terrainM ?? 0,
      qnhHpa: _qnh ?? Settings.instance.qnhHpa ?? 1013.25,
      trackDeg: trackDeg,
      groundSpeedKmh: groundSpeedKmh,
    );
    // Speak each urgent airspace at most once a minute.
    for (final w in airspaceWarnings) {
      if (w.level != AirspaceLevel.inside) continue;
      final key = '${w.airspace.cls} ${w.airspace.name}';
      final last = _announced[key];
      if (last != null && f.time.difference(last).inSeconds < 60) continue;
      _announced[key] = f.time;
      _say(w.predicted ? 'Airspace ahead: ${w.airspace.name}' : 'Inside airspace ${w.airspace.name}');
    }
  }

  /// Takeoff height if we're on a known launch, otherwise GPS.
  double _calibrationAltitude(Fix f) {
    for (final s in AppState.instance.sites) {
      if (distanceM(s.lat, s.lon, f.lat, f.lon) < 150) return s.takeoffElevationM;
    }
    return f.gpsAltM;
  }

  void _updateFlying(Fix f) {
    // Takeoff: moving faster than walking for the last 15 s.
    if (!flying && groundSpeedKmh > 15 && track.length > 15) {
      final recent = track.sublist(track.length - 15);
      if (FlightAnalyzer.speedKmh(recent.first, recent.last) > 12) {
        flying = true;
        takeoffTime = f.time;
      }
    }
    if (flying) {
      if (groundSpeedKmh < 3) {
        _groundSince ??= f.time;
        if (f.time.difference(_groundSince!).inSeconds > 90 && mode == FlightMode.live) {
          flying = false;
          _say('Landed. Flight saved.');
          stop();
        }
      } else {
        _groundSince = null;
      }
    }
  }

  void _updateThermal(Fix f) {
    final recent = _since(f.time, 30);
    var turned = 0.0;
    for (var i = 2; i < recent.length; i++) {
      final a = recent[i - 2], b = recent[i - 1], c = recent[i];
      if (distanceM(a.lat, a.lon, b.lat, b.lon) < 1 || distanceM(b.lat, b.lon, c.lat, c.lon) < 1) continue;
      turned += turnDeg(bearingDeg(a.lat, a.lon, b.lat, b.lon), bearingDeg(b.lat, b.lon, c.lat, c.lon));
    }
    circling = turned.abs() >= 300;
    _assistant.add(LiftSample(f.time, f.lat, f.lon, varioMs));
    assist = circling
        ? _assistant.evaluate(now: f.time, lat: f.lat, lon: f.lon, windFromDeg: wind?.fromDeg ?? 0, windKmh: wind?.speedKmh ?? 0)
        : null;
    if (circling) {
      _circlingFixes++;
      _thermalStart ??= recent.first;
      final dt = f.time.difference(_thermalStart!.time).inSeconds;
      thermalGainM = f.altM - _thermalStart!.altM;
      thermalAvgMs = dt > 0 ? thermalGainM! / dt : null;
    } else if (_thermalStart != null && _circlingFixes > 0) {
      if ((thermalGainM ?? 0) > 50 && thermalAvgMs != null) {
        _say('Thermal average ${thermalAvgMs!.toStringAsFixed(1)}, gained ${thermalGainM!.round()} metres');
      }
      _thermalStart = null;
      _circlingFixes = 0;
    }
  }

  void _updateWindAndGlide(Fix f) {
    if (track.length % 5 == 0) {
      final w = windFromCircling(_since(f.time, 45));
      if (w != null && w.quality > 0.8) wind = w;
      glideRatio = currentGlideRatio(_since(f.time, 30));
    }
    // Final glide to the nearest known landing field.
    final st = Settings.instance;
    LandingField? best;
    var bestD = double.infinity;
    for (final l in AppState.instance.landings) {
      final d = distanceM(f.lat, f.lon, l.lat, l.lon);
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    landing = bestD < 40000 ? best : null;
    finalGlideToLanding = landing == null
        ? null
        : finalGlide(
            lat: f.lat, lon: f.lon, altM: f.altM,
            goalLat: landing!.lat, goalLon: landing!.lon, goalElevationM: landing!.elevationM,
            windFromDeg: wind?.fromDeg ?? 0, windKmh: wind?.speedKmh ?? 0,
            polar: st.polar, safetyM: st.safetyMarginM,
          );
  }

  void _updateTerrain(Fix f) {
    final cached = _elevation.cached(f.lat, f.lon);
    if (cached != null) {
      terrainM = cached;
      return;
    }
    final last = _lastElevationAt;
    if (last != null && f.time.difference(last).inSeconds < 10) return;
    _lastElevationAt = f.time;
    _elevation.elevation(f.lat, f.lon).then((e) {
      terrainM = e;
      notifyListeners();
    }).catchError((Object _) {});
  }

  List<Fix> _since(DateTime t, int seconds) {
    var i = track.length;
    while (i > 0 && t.difference(track[i - 1].time).inSeconds <= seconds) {
      i--;
    }
    return track.sublist(i);
  }

  void _say(String text) {
    if (!voice || mode == FlightMode.idle) return;
    _tts.speak(text).catchError((Object _) => 0);
  }
}
